# Problemas conhecidos e roadmap detalhado

Este documento é um guia de execução para investigar e corrigir os problemas do projeto Forest. Ele descreve o que o código demonstra, onde olhar, uma ordem de trabalho segura e como confirmar a correção. A IA deve ler os arquivos atuais antes de editar: nomes, linhas e comportamento podem mudar.

## Como interpretar o status

- **Confirmado no código:** a inconsistência está visível nas fontes, mas o sintoma de jogo ainda pode precisar de reprodução.
- **Reproduzido em runtime:** o erro/sintoma foi visto executando o projeto.
- **Precisa validar:** existe um caminho plausível; testar com save/cena real antes de mudar.
- **Precisa medir:** pode custar desempenho, mas não há profiling que prove impacto.
- **Resolvido:** mudança aplicada e verificada; não significa ganho de FPS se não houver benchmark.

## Antes de qualquer alteração

1. Consulte **docs/README.md**, **docs/MISSIONS_AND_PROGRESSION.md** e **docs/PERFORMANCE_AND_STREAMING.md**.
2. Confira Git status e preserve alterações que já estavam no workspace.
3. Use uma cópia do save. Não altere nem apague user://savegame.json real para testar.
4. Faça uma alteração de cada vez. Valide GDScript no Godot; mudanças de gameplay exigem fluxo real e leitura da aba de erros.
5. Não declare resolvido apenas porque o script compila: teste save novo, save antigo, reload, eventos repetidos e sequência de missão.
6. Não prometa FPS sem baseline e comparação sob condições equivalentes.

---

## P0 — Integridade de sessão, save e ciclo de missão

### 1. Tempo jogado é acumulado e somado repetidamente

**Status:** confirmado no código.  
**Arquivos:** scripts/autoload/jogo.gd; scripts/autoload/save_system.gd.  
**Pontos a inspecionar:** Jogo._process(), Jogo._salvar_progresso_missao(), SaveSystem.salvar().

**O que ocorre:** Jogo.tempo_sessao recebe delta continuamente. Cada chamada a _salvar_progresso_missao() soma todo o valor acumulado a tempo_jogado_seg, mas não guarda um marcador do que já foi contabilizado. A mesma sessão pode ser adicionada em vários objetivos e conclusões de missão. Jogo também usa PROCESS_MODE_ALWAYS, então o contador pode incluir menu, loading e pausas.

**Como corrigir:**

1. Decida e documente o que significa tempo_jogado_seg: somente mapa ativo? Inclui tutorial? Exclui menu, loading e pausa?
2. Separe tempo total da sessão de tempo ainda não salvo. Exemplo conceitual: acumule delta apenas quando gameplay estiver ativo; no pedido de save, copie o delta pendente para o save e não some novamente o tempo anterior.
3. Só marque o delta como salvo depois que SaveSystem confirmar que a escrita teve sucesso. Hoje salvar() não retorna sucesso; considere mudar o contrato para retornar bool ou emitir resultado explícito.
4. Se houver dois pedidos no mesmo frame, o segundo não pode somar o mesmo intervalo. Combine isso com a fila de save da seção seguinte.
5. Não dependa de procurar o nome da tela de loading em muitos scripts. Prefira um estado explícito de gameplay ou grupo/sinal controlado pela transição para o mapa.
6. Defina o que acontece se o jogo fecha antes do próximo objetivo. O save de pausa/fechamento deve incluir somente o delta ainda não persistido.

**Não fazer:** zerar tempo_sessao em todo evento sem atualizar o save com segurança; isso pode perder tempo se a gravação falhar.

**Validação:**

- Registre um valor base de tempo salvo.
- Passe um intervalo conhecido no menu e outro no mapa; confirme a regra escolhida.
- Conclua dois objetivos em sequência; o tempo total não pode dobrar.
- Pause/retome e feche/reabra.
- Simule falha de abertura/escrita do arquivo sem apagar o save real e confira se o delta continua pendente.

### 2. Conclusão do último objetivo pode gravar o save duas vezes no mesmo fluxo

**Status:** confirmado pelo fluxo de sinais.  
**Arquivos:** scripts/missions/mission_base.gd; scripts/missions/mission_manager.gd; scripts/autoload/jogo.gd; scripts/autoload/save_system.gd.  
**Pontos a inspecionar:** MissionBase.completar_objetivo(), MissionBase._concluir_missao(), MissionManager._on_objective_completed(), MissionManager._on_mission_completed(), Jogo._salvar_progresso_missao().

**Sequência atual:** completar_objetivo emite objective_completed antes de verificar/concluir a missão. MissionManager salva o estado em memória e repassa o sinal; Jogo chama SaveSystem.salvar(). Se esse era o último objetivo, _concluir_missao() emite mission_completed logo depois; Jogo chama salvar novamente. SaveSystem serializa e escreve JSON de forma síncrona.

**Como corrigir com baixo risco:**

1. Introduza um pedido de save coalescido: vários pedidos no mesmo frame marcam dados como sujos, mas só executam uma gravação deferida.
2. Antes da serialização, sincronize o estado final das missões e XP para SaveSystem.dados. Uma chamada deferida ao final do fluxo de sinais pode permitir que MissionBase conclua antes da gravação.
3. Não use um simples “ignorar segundo save” que descarte dados. O pedido deve continuar pendente até ocorrer gravação bem-sucedida.
4. Faça o fechamento/pausa forçar ou aguardar a gravação pendente conforme suportado pelo ciclo de vida do Godot.
5. Guarde uma cópia de segurança ao mudar a rotina de escrita. A escrita atual abre o save diretamente em modo WRITE, que pode truncar o arquivo antes de a nova serialização terminar.
6. Mantenha sinais existentes ou migre todos os ouvintes em HUD, XP, missões e diálogo.

**Validação:**

- Instrumente temporariamente a quantidade de chamadas a salvar().
- Complete um objetivo não final: deve salvar uma vez ao fim do evento.
- Complete o objetivo final: deve salvar uma vez com objetivo completo, missão concluída, XP atualizado e próxima missão consistente.
- Teste pausa/fechamento quando há gravação deferida.
- Verifique que erro de escrita não marca dados como limpos.

### 3. Eventos de conclusão podem ocorrer antes de MissionManager conectar os ouvintes

**Status:** confirmado pela ordem do código; precisa reprodução.  
**Arquivo:** scripts/missions/mission_manager.gd.  
**Pontos a inspecionar:** MissionManager._ready(), _carregar_missoes(), _restaurar_do_save(), _definir_missao_ativa().

**O que ocorre:** _ready() carrega missões e chama _restaurar_do_save() antes de conectar mission_completed e objective_completed de cada instância. A restauração pode ativar uma DiscoveryMission. O método _on_activate() examina descobertas salvas, completa objetivos e pode emitir mission_completed durante essa ativação. Se isso ocorrer antes das conexões do manager, ele perde o evento que deveria salvar o estado e ativar a próxima missão. O ponteiro _missao_ativa pode continuar apontando para uma missão que já se concluiu.

**Como corrigir:**

1. Separe carregamento de objetos, ligação de sinais, restauração de dados e ativação.
2. Ordem recomendada: criar todas as instâncias; construir índice por ID; conectar sinais do manager às missões; carregar estados salvos sem ativar; escolher a missão elegível; só então chamar a rotina de ativação que pode reconciliar descobertas.
3. Se a restauração precisar emitir eventos, garanta explicitamente que os ouvintes estão conectados antes.
4. Faça _definir_missao_ativa() não deixar o ponteiro global apontando para missão concluída durante a reconciliação. Após ativação, reavalie estado e selecione a próxima pendente quando necessário.
5. Proteja conexões contra duplicação com is_connected(), inclusive em reload de save durante o mesmo processo.
6. Teste closure/bind de objective_completed: cada missão deve enviar seu próprio mission_id. Se houver dúvida, conecte usando helper que captura um ID local imutável e valide com sinais de duas missões diferentes.

**Validação:**

- Faça save de teste com missão ativa cujas descobertas necessárias já estejam todas em descobertas.
- Inicie o jogo e confirme que o manager avança exatamente uma vez.
- Confirme missão ativa retornada pela API, HUD, save e log.
- Carregue save com descoberta parcial e confirme que somente os objetivos existentes são reconciliados.

### 4. XP e recompensa precisam ser consistentes no mesmo commit

**Status:** precisa validar com reload; guardas atuais existem em memória.  
**Arquivos:** scripts/missions/mission_base.gd; scripts/autoload/xp_manager.gd; scripts/missions/mission_manager.gd; scripts/autoload/jogo.gd; scripts/autoload/save_system.gd.

**Risco:** MissionBase aplica recompensas na conclusão, XPManager atualiza valores em memória e SaveSystem grava o dicionário. Em caso de saída abrupta entre atualizar XP, marcar missão e gravar, pode haver XP perdido ou recompensa repetida quando o evento for reproduzido. A proteção _concluida evita repetição só depois de estado restaurado corretamente.

**Como corrigir:**

1. Garanta que estado da missão concluída, objetivo, XP/nível e eventual marcador de recompensa sejam atualizados em SaveSystem.dados antes de serializar.
2. Centralize a finalização: uma transição idempotente de “ativa/incompleta” para “concluída”, depois recompensas, depois um pedido de save. Repetir a mesma conclusão deve não fazer nada.
3. Se a conclusão puder chamar efeitos não idempotentes além de XP, registre o que foi concedido por ID de recompensa. Não crie ledger sem necessidade demonstrada.
4. Faça SaveSystem informar sucesso de gravação. Não marque recompensa/save como persistido antes de a escrita terminar.
5. Para robustez contra arquivo truncado, considerar salvar em temporário, validar escrita e substituir o arquivo anterior com fallback/backup. Testar as particularidades de substituição no Windows.

**Validação:** repetir sinal de conclusão; recarregar imediatamente; comparar XP, nível, missão e número de sinais/recompensas. Resultado deve ser uma recompensa só e estado concluído.

---

## P1 — Campanha, objetivos e validação de dados

### 5. Trigger do centro usa um objective_id ausente no JSON

**Status:** confirmado ao comparar world.tscn e data/configs/missoes.json.  
**Arquivos:** world.tscn; data/configs/missoes.json; scripts/world/area_trigger.gd; scripts/missions/discovery_mission.gd.

AreaFazendaCentroTrigger declara objective_id apresentar_fazenda e registra fazenda_centro. A missão mostrar_fazenda_agrobot contém escanear_solar, escanear_eolico e escanear_silo. O mapa de descobertas da missão é criado a partir do JSON; portanto apresentar_fazenda não é um objetivo conhecido.

**Decida a intenção antes de editar:**

- Se centro da fazenda é somente ponto educativo/diálogo: mantenha fazenda_centro como descoberta de conteúdo e limpe objective_id e possivelmente mission_id do trigger se não forem necessários. Confirme que os diálogos não dependem desses valores.
- Se visitar o centro deve ser um quarto objetivo: adicione objetivo com ID apresentar_fazenda e alvo fazenda_centro ao JSON, ajuste texto/HUD e teste pré-requisito/conclusão.
- Se a visita é obrigatória para a campanha mas não deve ficar no diário, crie uma regra de objetivo/evento explícita em vez de deixar um ID órfão.

**Validação:** busca global por ambos IDs; entre na área antes/durante/depois da missão; confirme descoberta, diálogo, diário e conclusão da missão.

### 6. Missão 7 pode pular a ação de abrigar equipamentos

**Status:** causa confirmada no código/configuração; efeito deve ser reproduzido em runtime.  
**Arquivos:** data/configs/missoes.json; world.tscn; scripts/missions/discovery_mission.gd; scripts/autoload/jogo.gd; scripts/world/clima.gd.

Missão 6 conclui retornar_sede com alvo sede. Missão 7 também define abrigar_equipamentos com o mesmo alvo sede. Jogo guarda descobertas globalmente e não emite novo sinal para ID repetido. DiscoveryMission, ao ativar, verifica descobertas anteriores; se sede estiver salva, pode completar abrigar_equipamentos imediatamente, sem ação de abrigo. Não foi encontrado handler explícito para abrigar equipamentos.

**Correção recomendada:**

1. Dê ao objetivo final um alvo distinto, por exemplo equipamentos_abrigados, sem reutilizar a descoberta sede.
2. Defina a ação de jogo que significa “abrigar”: interação explícita no abrigo ou mover equipamentos específicos para uma área segura. Escolha de acordo com o gameplay desejado.
3. Faça a ação registrar o novo evento somente quando a missão proteger_equipamentos estiver ativa e as condições estiverem satisfeitas.
4. Conecte o evento ao objetivo abrigar_equipamentos. Não registre essa descoberta ao apenas entrar na sede.
5. Preserve descoberta sede para retorno/diálogos da missão 6. Se saves existentes precisarem de compatibilidade, não apagar fatos salvos; apenas deixe de usá-los como condição do objetivo novo.
6. Confirme que chuva, instruções e estado de equipamentos combinam com a ação. clima.gd já observa início da missão 7 e interrompe a chuva.

**Validação:** testar save novo; save em que sede já está descoberta; chegar à sede sem interagir (objetivo deve permanecer); executar ação de abrigo (objetivo deve completar); sair/recarregar e confirmar que não repete recompensa.

### 7. Ordem de ativação/restauração aceita estados contraditórios

**Status:** confirmado no algoritmo; testar saves com dados contraditórios.  
**Arquivo:** scripts/missions/mission_manager.gd.  
**Funções:** _restaurar_do_save(), _definir_missao_ativa(), _prerequisitos_ok(), _ativar_proxima_pendente().

Ao carregar, o manager percorre estados e chama _definir_missao_ativa() para cada uma marcada ativa. A última fica no ponteiro global, enquanto outras podem manter flags ou disparar reconciliação. A função de ativação também salva o estado durante a restauração.

**Como corrigir:**

1. Faça duas fases: primeiro carregar os registros em cada missão sem efeitos; depois escolher a missão ativa.
2. Considere ativa somente missão que não esteja concluída, tenha pré-requisitos satisfeitos e esteja presente na configuração atual.
3. Se houver várias candidatas, escolha uma regra determinística, preferencialmente a missão válida de menor ordem entre as salvas, ou documente outra regra.
4. Marque as demais como inativas.
5. Se nenhuma salva for válida, use _ativar_proxima_pendente().
6. Normalize SaveSystem.dados["missoes_estado"] depois de todas as instâncias carregadas; não regrave repetidamente dentro do loop.
7. Não descarte progresso de missão desconhecida em save sem política de migração.

**Validação:** saves de teste com zero, uma e várias ativas; ativa concluída; pré-requisito faltando; missão removida do JSON. O jogo deve escolher uma única missão válida e não perder progresso de objetivos reconhecidos.

### 8. Validação dos pré-requisitos não cobre ciclos longos e depende da ordem

**Status:** confirmado no código.  
**Arquivo:** scripts/missions/mission_manager.gd, _validar_missoes().

A lista ids_vistos é preenchida durante a mesma passagem que verifica pré-requisitos. Dependência válida pode ser reportada como não carregada se aparecer depois no JSON. A detecção atual verifica ciclo de apenas dois passos e não encontra necessariamente A → B → C → A.

**Como corrigir:**

1. Na primeira passagem, validar tipos básicos e construir Dictionary de missão por ID completo.
2. Na segunda passagem, verificar referências inexistentes e IDs repetidos sem consultar ordem de iteração.
3. Detectar ciclos em todo o grafo por DFS com estados não visitado/em processamento/concluído, ou algoritmo equivalente.
4. Produzir mensagem com a cadeia do ciclo para facilitar correção do JSON.
5. Validar ordem separadamente de dependência; a propriedade ordem é apresentação/sequência, não prova de que o grafo está correto.
6. Não alterar dados automaticamente para “consertar” um ciclo.

**Validação:** criar cópias temporárias de dados com dependência posterior válida, referência inexistente, ciclo de duas e três missões; confirmar diagnóstico adequado e restaurar JSON original.

### 9. Alvos de descoberta repetidos sobrescrevem objetivos

**Status:** confirmado no código.  
**Arquivos:** scripts/missions/discovery_mission.gd; scripts/missions/mission_manager.gd.

_construir_mapa_descobertas() armazena um único objective_id para cada alvo_id. Se dois objetivos da mesma missão usam o mesmo alvo, a última atribuição substitui a primeira.

**Como corrigir:**

- Opção simples: validar unicidade de alvo_id por missão e emitir erro com ID da missão/alvo.
- Se um evento deve completar vários objetivos, mudar a estrutura para alvo_id -> lista de objective_id e completar cada objetivo uma única vez.
- Evitar mexer na persistência de descobertas globais; resolver no mapeamento de missão.

**Validação:** testar JSON com alvo duplicado e confirmar erro ou conclusão de todos os objetivos conforme a regra escolhida.

### 10. Progresso parcial não emite sinal nem sincroniza save

**Status:** confirmado no contrato de funções; verificar efeito na HUD e reload.  
**Arquivos:** scripts/missions/mission_base.gd; scripts/missions/mission_manager.gd; scripts/world/area_plantio.gd; scripts/ui/hud.gd; scripts/autoload/save_system.gd.

atualizar_progresso_objetivo() apenas altera o Dictionary interno da missão. Não emite sinal nem informa ao MissionManager que o estado mudou. AreaPlantio usa isso para percentual de pulverização e registra descoberta separada ao chegar ao limite.

Além disso, MissionManager._on_save_saved() atualiza missoes_estado após SaveSystem já ter serializado/escrito o JSON. Essa ordem pode deixar no arquivo o progresso anterior, especialmente para progresso parcial que não emite objective_completed.

**Como corrigir:**

1. Defina uma API única de atualização parcial em MissionManager ou em MissionBase com sinal contendo mission_id, objective_id e progresso.
2. Atualize o estado em memória antes de solicitar save.
3. Faça HUD/diário ouvir sinal de progresso e atualizar sem polling.
4. Para spray, não salve em disco em cada frame. Marque progresso como dirty e salve em eventos espaçados, ao sair da missão ou em pausa/fechamento. O limite/intervalo deve ser escolhido sem perder progresso importante.
5. Antes de serializar, sincronize MissionManager para SaveSystem.dados; não use um sinal disparado depois da escrita como preparação do save.
6. Mantenha conclusão formal separada: progresso chegar a 1 deve chamar a mesma rotina idempotente de conclusão, ou a API deve documentar que o chamador precisa concluir explicitamente.
7. Evite que progresso tardio altere missão concluída ou missão diferente.

**Validação:** pulverizar algumas plantas, salvar/fechar/reabrir e conferir percentual; atingir 80%; repetir a emissão; confirmar que objetivo e recompensa ocorrem uma vez.

### 11. XP antigo é migrado com valor fixo incompatível

**Status:** confirmado no código/configuração.  
**Arquivos:** scripts/autoload/xp_manager.gd; scripts/missions/mission_base.gd; data/configs/missoes.json; scripts/autoload/save_system.gd.

_reconciliar_xp_missoes() estima XP antigo como 100 × número de missões concluídas. JSON atual paga 100, 150 ou 200. A fórmula pode atribuir menos do que deveria ou reconciliar incorretamente se o save antigo já contém XP parcial.

**Como corrigir:**

1. Identifique quais versões de save realmente precisam de migração e como o campo missoes_concluidas foi produzido.
2. Não use somente a contagem de missões para inferir XP se recompensas variaram ou podem ter sido concedidas separadamente.
3. Use tabela de versão antiga/recompensa conhecida ou um marcador explícito de recompensa concedida, conforme os dados disponíveis.
4. Preserve sempre XP atual maior que o cálculo retroativo.
5. Atualize xp e nivel juntos e só marque versão migrada depois de concluir a conversão.
6. Evite que carregar o mesmo save aplique a migração repetidamente.

**Validação:** saves cópia com zero XP, XP parcial, várias missões antigas e versão nova; comparar antes/depois e recarregar duas vezes.

### 12. Missão sem objetivos pode passar como completa

**Status:** risco confirmado pela interação de dois métodos.  
**Arquivos:** scripts/missions/mission_manager.gd; scripts/missions/mission_base.gd; scripts/missions/discovery_mission.gd.

O validador avisa quando objetivos está vazio, mas _verificar_todos_objetivos() retorna true se não encontra objetivo pendente. DiscoveryMission._on_activate() chama _check_completion(), então uma missão inválida sem objetivos pode concluir na ativação.

**Como corrigir:** rejeitar a missão sem objetivos antes de instanciar/ativar, ou declarar uma semântica explícita para missões instantâneas. Não deixar apenas como warning se a conclusão não for intencional.

**Validação:** usar JSON temporário com missão sem objetivo e confirmar erro claro, sem XP nem avanço da campanha.

### 13. Tipo de missão desconhecido cai silenciosamente em DiscoveryMission

**Status:** confirmado no código.  
**Arquivo:** scripts/missions/mission_manager.gd, _criar_missao_de_dict().

Um erro de tipo no JSON gera warning, mas cria DiscoveryMission. A missão aparece carregada e pode ficar travada porque o tipo não corresponde ao comportamento esperado.

**Como corrigir:** falhar criação e reportar tipo/id de missão; ou usar fallback somente em modo de desenvolvimento e marcá-lo claramente. Não adicionar tipos sem implementação real.

**Validação:** typo temporário em tipo; o carregamento deve apontar a definição inválida e não afirmar que a missão foi carregada normalmente.

---

## P1 — Desempenho a medir antes de otimizar

### 14. Até 400 plantas são nós individuais

**Status:** precisa medir, não presumir gargalo.  
**Arquivos:** world.tscn; scripts/world/area_plantio.gd; scripts/world/area_plantio_multimesh.gd; scenes/world/milho_plantavel.tscn.

Mapa usa AreaPlantio e instâncias individuais até 400. Existe uma implementação alternativa MultiMesh, mas ela não está conectada e ainda precisa de paridade visual/funcional.

**Plano de medição e eventual troca:**

1. Medir cena com 0, 100 e 400 plantas na mesma posição/câmera.
2. Registrar CPU frame, GPU frame, draw calls, objetos e memória.
3. Inspecionar se cada milho tem animação, colisão, material ou script que impeça instancing.
4. Se custo for relevante, completar MultiMesh mantendo cor/material de pulverização. Uma possibilidade é usar custom data ou cores por instância, mas validar material/shader.
5. Revisar conexão do drone, missão ativa, progresso, reset, save/load e transformação local/global na alternativa.
6. Comparar visual e gameplay nos mesmos cenários antes de conectar script à cena.

**Não assumir:** 400 nós equivalem exatamente a 400 draw calls; materiais, batching e renderizador influenciam. MultiMesh não garante um único draw call em qualquer material.

### 15. Spray varre todas as plantas por sinal

**Status:** precisa medir.  
**Arquivos:** character/scripts/drone_jogador.gd; scripts/world/area_plantio.gd.

Cada emissão enquanto spray está ativo percorre as plantas. Já se usa length_squared, que evita raiz quadrada.

**Como proceder:**

1. Profile CPU durante spray com 400 plantas.
2. Se for custo dominante, testar primeiro reduzir frequência de consulta usando intervalo fixo e posição mais recente do drone.
3. Confirmar que o intervalo não deixa falhas ao voar rápido; considerar acumular segmento entre posições ou testar trajetória.
4. Só depois considerar grid espacial por células. Atualize índice quando planta é criada/restaurada/resetada.
5. Evite formar strings de chave de posição para cada planta a cada emissão; use índice eficiente sem mudar formato de save.

**Validação:** percorrer fileiras em velocidade lenta/rápida, parar em bordas, carregar plantas pulverizadas e repetir spray; não duplicar progresso.

### 16. Terrain3D, água, sombras e culling

**Status:** precisa medir por plataforma.  
**Arquivos:** world.tscn; scripts/autoload/qualidade_grafica.gd; shaders em terrain mat/water/ e env models/plants/.

- last_lod maior que a geometria disponível já causou “No LOD 1 for mesh id ...”; valores foram corrigidos para 0. Não aumentar sem conferir malha LOD real.
- Há shader mobile de água; confirmar material atribuído no mundo/export.
- Confirmar vegetação e sombras efetivamente ativas em cada preset.
- VisibilityOptimizer existe, mas confirmar anexos. Um _process por objeto pode custar CPU.
- Contar áudio/partículas/lens flare antes de remover.

**Procedimento:** perfilar CPU e GPU; alterar um fator por vez; validar visual e runtime. Testar export no dispositivo alvo. O desktop Forward+ não prova comportamento Android.

---

## Resolvido recentemente

- **Parse inválido dos chunks:** world.tscn passou a usar subresources válidos; MCP executou loading até o mapa.
- **LOD indisponível:** last_lod voltou a 0 nos assets afetados; execução posterior não reportou esse erro.
- **Prompt do trator:** texto/distância atualiza a 10 Hz quando jogador está perto.
- **Animação do jogador:** o mesmo recurso não é buscado/reconfigurado quando a animação não muda.
- As duas alterações de script passaram por validação de sintaxe MCP; painel reportou zero erros naquele momento. Não houve benchmark de FPS.

---

## Ordem de execução recomendada

1. Primeiro corrigir ordem de conexão/restauração das missões, pois um evento de conclusão perdido pode travar a campanha após reload.
2. Em seguida corrigir contagem de tempo e coalescer gravações.
3. Corrigir alvo de missão 7 e decidir objetivo do trigger do centro.
4. Normalizar missão ativa, validar grafo, IDs, alvos e tipos.
5. Padronizar progresso parcial e sincronização antes de gravar.
6. Corrigir migração de XP usando saves de teste.
7. Medir plantio/pulverização e renderização.
8. Só implementar MultiMesh, grid, mudanças de shader/culling ou redução de áudio se profiling justificar.
9. Atualizar status deste arquivo com evidência, testes e limitações após cada correção.


---

## Ajustes recomendados de robustez: missões e diálogos

Esta seção transforma a avaliação arquitetural em tarefas concretas para quem for implementar. A arquitetura atual separa parte dos dados da lógica e usa sinais, mas os itens abaixo devem ser concluídos antes de ampliar bastante o número de missões, ramificações ou autores de conteúdo.

### A. Tornar transições de missão idempotentes

**Arquivos principais:** `scripts/missions/mission_base.gd`, `scripts/missions/mission_manager.gd`, `scripts/autoload/jogo.gd`, `scripts/autoload/save_system.gd`, `scripts/autoload/xp_manager.gd`.

1. Conectar os sinais de cada instância antes de restaurar ou ativar qualquer missão.
2. Dividir restauração em fases: instanciar e indexar; carregar estados sem efeitos colaterais; conectar sinais; reconciliar descobertas; escolher e ativar a missão.
3. Ao carregar save contraditório, selecionar deterministicamente uma única missão ativa válida e desativar as demais.
4. Fazer `completar_objetivo()` não emitir sinal se o objetivo já estiver concluído. Aplicar conclusão e XP no máximo uma vez, inclusive após reload ou repetição do evento.
5. Padronizar o commit: atualizar estado do objetivo/missão, aplicar XP, sincronizar `SaveSystem.dados`, solicitar gravação. Não preparar o save em sinal emitido depois da gravação.
6. Agrupar pedidos emitidos no mesmo fluxo. O último objetivo pode emitir conclusão do objetivo e da missão, mas deve resultar em uma gravação final consistente, sem duas gravações síncronas redundantes.
7. Manter a gravação pendente até a escrita confirmar sucesso; erro de escrita não pode marcar os dados como persistidos.

**Aceite:** repetir eventos não duplica sinais, XP ou save; ao carregar um save cuja descoberta já completa uma missão, manager, HUD e save indicam corretamente a próxima missão.

### B. Unificar o contrato de objetivo e progresso parcial

**Arquivos principais:** `scripts/missions/mission_base.gd`, `scripts/missions/mission_manager.gd`, `scripts/missions/discovery_mission.gd`, chamadores em `scripts/world/` e UI do diário/HUD.

1. Documentar e validar os tipos de objetivo realmente suportados. Não anunciar `area_enter` ou `interacao` sem caminho completo que atualize esses objetivos.
2. Criar API central de evento/progresso parcial que receba `mission_id`, `objective_id` e valor, validando IDs, missão ativa, intervalo e estado.
3. Emitir sinal de progresso com identidade do objetivo e valor atualizado; HUD e diário reagem ao sinal sem polling.
4. Para progresso frequente (ex.: pulverização), marcar dados como sujos e gravar em checkpoints/eventos importantes, sem escrever JSON a cada frame.
5. Quando o progresso atingir o limite, encaminhar para a mesma conclusão idempotente dos demais tipos.
6. Ignorar atualizações tardias de objetivo/missão concluídos, salvo se um tipo declarar explicitamente que pode continuar.

**Aceite:** progresso aparece no HUD, persiste ao salvar/reabrir e atingir o limite conclui objetivo/recompensa uma vez.

### C. Validar grafo e referências dos dados

**Arquivos principais:** `scripts/missions/mission_manager.gd`, `data/configs/missoes.json`, `data/dialogues/index.json`, `data/dialogues/**/*.json`, `world.tscn` e scripts de gatilho.

1. Construir primeiro mapas completos de IDs; depois validar referências sem depender da ordem dos itens nos arquivos.
2. Detectar IDs duplicados de missão, objetivo, diálogo e alvo de descoberta. Se vários objetivos puderem compartilhar um alvo, modelar alvo para lista e completar cada um conforme regra documentada.
3. Detectar ciclos em todo o grafo, inclusive dependências com três ou mais missões, e imprimir a cadeia do ciclo.
4. Validar referências ausentes, tipos desconhecidos, missões sem objetivos, campos JSON com tipo incorreto e campos obrigatórios vazios. Erros críticos devem impedir ativação, não cair silenciosamente em `DiscoveryMission`.
5. Validar gatilhos de diálogo: missão/objetivo existentes, `area_id` existente, `custom_signal` com nome e produtor, condições válidas e diálogo listado no índice.
6. Validar campos de objetivos em `world.tscn`; referência órfã deve ser corrigida ou intencionalmente removida.
7. Executar validação de dados antes de aceitar conteúdo novo. Manter casos de referência ausente, ciclo longo, ID duplicado, gatilho órfão e tipo inválido.

**Aceite:** mensagens indicam arquivo, ID e referência inválida; reordenar JSON não muda o resultado; gatilhos órfãos não passam despercebidos.

### D. Corrigir gatilhos e alinhar conteúdo atual

1. Em `dialogue_manager.gd`, indexar `custom_signal` pela chave do campo `signal`, a mesma usada pela consulta. Esse gatilho não é identificado por `mission_id`/`objective_id`.
2. Localizar chamadas reais de `request_custom()` e assegurar produtor para cada sinal configurado. `intro_started` deve ser emitido no início real da intro, ou o diálogo deve usar o gatilho correto.
3. Fazer `play_immediate()` obedecer `once` e registro persistido, salvo opção explícita para repetição. Centralizar essa verificação entre API direta, gatilhos e reprodução imediata.
4. Resolver o diálogo `conhecer_solo`, cuja missão não existe na configuração atual: reintroduzir intencionalmente, remapear conteúdo ou retirar a entrada se for legado confirmado.
5. Resolver `apresentar_fazenda`, definido no trigger do centro mas ausente da missão: decidir se é objetivo ou só ponto de diálogo e alinhar cena/JSON.
6. Separar o alvo `sede` do objetivo “abrigar equipamentos”. Esse objetivo precisa depender de uma ação/evento distinto, não do histórico de visitar a sede.

**Aceite:** cada evento configurado encontra e toca o diálogo esperado, respeita condições/`once`, e não há IDs órfãos entre missões, diálogos e cenas.

### E. Política de migração e persistência

1. Versionar o formato do save e escrever migrações sequenciais. Não inferir XP histórico usando uma recompensa fixa quando as recompensas variam.
2. Preservar progresso de missões desconhecidas/removidas até existir política explícita de migração; registrar IDs para diagnóstico.
3. Preparar estado completo antes da escrita e proteger o save anterior contra falha durante gravação; retornar sucesso/erro ao chamador.
4. Contabilizar tempo apenas nos estados definidos como gameplay e somar somente o delta ainda não persistido.

**Aceite:** save novo, antigo, migração, erro de escrita simulado e saída com progresso pendente mantêm missão, descobertas, XP, tempo e diálogos consistentes.

### F. Regressão funcional da campanha

Em cópia de save, percorrer início, progresso parcial, diálogo de ativação, áreas, conclusão, XP, missão seguinte, save/load e repetição de eventos. Cobrir especialmente descoberta salva antes da ativação; duas missões ativas no save; pulverização parcial; último objetivo; diálogo `once`; `custom_signal`; pré-requisito inválido; abrigo com `sede` já descoberta. Registrar estado esperado por caso; compilação isolada não comprova fluxo correto.

---

## Grama e vegetação: distância, fade e medição

**Diagnóstico:** no save consultado, o preset atual é `baixo`. Os assets da grama do Terrain3D estavam configurados para desaparecer a 15 m. Os `MultiMeshInstance3D` gerados também tinham `visibility_range_end_margin = 0` e fade desativado, portanto o limite de visibilidade era abrupto. O streamer regional não controla a grama: ela é instanciada pelo Terrain3D.

**Implementação e próximos passos:**

1. Usar distâncias moderadas por preset para grama. Aumentar range pode elevar custo de GPU, então medir antes de ampliar outras plantas ou a densidade.
2. Aplicar `VISIBILITY_RANGE_FADE_SELF` somente às instâncias MultiMesh dos assets de grama, após o Terrain3D as criar ou atualizar. Reaplicar ao trocar preset/recriar instâncias, sem percorrer todos os nós em `_process()`.
3. Confirmar que o range do asset permite a margem completa e que a transição fica estável andando, usando trator/drone e girando a câmera.
4. Comparar aparência, FPS/frame time e contagem de instâncias nos três presets e na mesma posição. Fade pode manter grama visível por mais tempo; não afirmar ganho de FPS sem benchmark.
5. Se continuar ocorrendo pop-in de geração/posição, revisar culling interno da versão Terrain3D e LODs realmente disponíveis. Não aumentar `last_lod` sem geometria LOD válida para cada asset.

**Aceite:** não há um anel duro de grama à frente da câmera; a grama próxima mantém densidade adequada; frame time é comparado com baseline equivalente.
