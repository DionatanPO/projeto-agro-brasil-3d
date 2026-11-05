# Desempenho e streaming

## Estado conhecido

- Godot 4.7.2 observado em desktop Vulkan/Forward+ com Radeon RX 6600M.
- **world.tscn** contém Terrain3D e quatro regiões: centro, norte, leste e sul.
- **scripts/world/world_streamer.gd** usa raio de carregamento 60 e descarga 100 no mapa observado.
- O streamer divide cenas regionais/props; não assume que o Terrain3D completo descarrega por região.
- Após corrigir declarações de chunk inválidas, MCP executou loading até o mapa. Foram observados três chunks próximos e zero erros naquele momento. Isso não é medição de FPS.
- Presets gráficos: **scripts/autoload/qualidade_grafica.gd**.
- Plantio ativo: nós individuais, até 400; alternativa MultiMesh não conectada.
- Existem shaders principal e mobile de água em **terrain mat/water/**.

## Regras do streamer

- Seleção de jogador usa NodePath/grupo.
- Atualização é periódica, não precisa rodar a cada frame.
- Distância usa borda horizontal do volume do chunk.
- Só obtenha recurso assíncrono após THREAD_LOAD_LOADED.
- Se jogador sair do raio durante carga, descartar resultado sem instanciar.
- Não liberar nós com outro dono ativo.
- Testar a pé, drone e trator.

## Terrain3D e LOD

Elevar last_lod sem geometria adicional causou “No LOD 1 for mesh id ...”. Valores foram corrigidos para 0. Não aumentar até confirmar LOD real importado para cada asset. O parâmetro mesh_lods de QualidadeGrafica não cria geometria ausente. Teste alterações de range/sombra no runtime.

## Custo de CPU a medir

- Plantio instancia até 400 cenas/nós individuais; medir em 0, 100 e 400.
- Pulverização percorre plantas por emissão do sinal do drone; já usa distância ao quadrado. Medir antes de adicionar grid/throttling e verificar cobertura ao voar rápido.
- Jogador/drone/trator exigem processamento contínuo para movimento, física, input, câmera e feedback. Procurar busca de árvore, formatação de texto, carga síncrona, criação de recurso e escrita repetida.
- SaveSystem escreve JSON sincronamente quando chamado. Conclusão do último objetivo pode disparar saves de objetivo e missão.
- Jogo soma tempo de sessão ao salvar; conferir se inclui menu e se soma trechos repetidos.

## Custo de GPU a medir

- Vegetação Terrain3D: densidade, ranges, sombras e LODs disponíveis.
- Água: confirme qual shader está atribuído em cada plataforma. O shader principal usa amostras de tela/profundidade; há variante mobile simplificada.
- Transparências, lens flare, céu, partículas, luzes e sombras.
- Resolução/upscaling e número real de draw calls, objetos e primitivas.
- Identifique se o gargalo é CPU ou GPU antes de escolher mudança.

## MultiMesh

**scripts/world/area_plantio_multimesh.gd** não está ligado à cena observada. Ainda precisa de paridade de material visual pulverizado, sinais de missão/drone, save/load, restauração, reset e transformes. Não trocar script diretamente. Comparar no mesmo cenário/hardware; MultiMesh pode reduzir overhead, mas não garante um draw call nem ganho específico.

## Culling, áudio e exportação

- VisibilityOptimizer existe; confirme onde está anexado. Lógica de visibilidade por objeto pode custar CPU e precisa testar reentrada na tela.
- Conte players de áudio e atenuação antes de removê-los.
- Shader Baker apareceu desativado nos presets consultados; confirme export atual antes de mudar.
- Desktop Forward+ não representa Android. Teste em aparelho alvo.

## Protocolo de benchmark

1. Fixar plataforma/build, resolução, preset, posição e duração.
2. Capturar baseline em repouso e durante deslocamento, drone, spray e 400 plantas.
3. Registrar FPS, frame time, física, draw calls/objetos, memória e contagem de nós/orphans quando disponíveis.
4. Fazer uma mudança por vez e repetir.
5. Aquecer recursos para medir gameplay estável; medir stutter de primeiro uso separadamente.
6. Verificar erros, missão, save e visual após otimizar.

O MCP conectado anteriormente não expôs a ferramenta de monitor de desempenho (“Unknown runtime tool”). Use profiler nativo ou corrija compatibilidade do plugin antes de confiar em números MCP.

## Otimizações recentes

- **character/scripts/trator_jogador.gd:** prompt/distância atualizam a 10 Hz e só perto; proximidade segue sendo verificada.
- **character/scripts/jogador.gd:** mesma animação não reobtém recurso/reconfigura loop a cada passo de física.
- Ambos foram validados pelo MCP sem erro de sintaxe; painel reportou zero erros naquele momento.
- Não houve benchmark numérico dessas mudanças.

