# Forest — visão geral do projeto

## O jogo

Forest é um jogo 3D de fazenda com exploração e conteúdo educativo. O jogador visita áreas da propriedade, conhece estruturas e informações sobre agricultura, usa o Agrobot, planta milho, pilota um drone e instala uma estação meteorológica. A campanha conduz essas atividades por objetivos e diálogos.

O conteúdo educativo fica em **data/configs/conteudos.json**. Exemplos: solo, soja, milho, água, tecnologia, pacote, centro da fazenda, parques solar/eólico, silo, plantio e estação meteorológica.

## Versão e plataforma observadas

- Projeto configurado com feature Godot 4.7; execução consultada em Godot 4.7.2.
- A execução observada usou Vulkan, Forward+ e AMD Radeon RX 6600M.
- Há opções voltadas a dispositivos móveis, mas esta máquina não representa benchmark mobile.
- Confirme versão, renderizador e plataforma antes de decisões técnicas.

## Fluxo de cenas

- Cena inicial configurada: **scenes/ui/menus/menu_inicial.tscn**.
- O menu conduz à tela de loading em **scenes/ui/menus/loading.tscn**.
- O loading carrega o mapa **world.tscn**.
- O mapa contém jogador, drone, trator, HUD, áreas de interação, clima, terreno e cenas regionais.
- Regiões: **scenes/world/regioes/regiao_centro.tscn**, norte, leste e sul.
- Personagens/veículos ficam em **character/scenes/**; interface em **scenes/ui/**.

Confirme os caminhos em project.godot e nas cenas quando alterar inicialização/carregamento.

## Autoloads

Os autoloads configurados em project.godot são:

| Nome | Arquivo / addon | Responsabilidade |
|---|---|---|
| InputSetup | scripts/autoload/input_setup.gd | Ações e controles |
| PhantomCameraManager | addon Phantom Camera | Câmeras |
| SaveSystem | scripts/autoload/save_system.gd | Save local em user://savegame.json |
| MissionManager | scripts/missions/mission_manager.gd | Estado e ciclo de missões |
| AudioConfig | scripts/autoload/audio_config.gd | Configuração de áudio |
| Jogo | scripts/autoload/jogo.gd | Descobertas, conteúdo, diário e sessão |
| XPManager | scripts/autoload/xp_manager.gd | XP, nível e sinais para UI |
| MCPRuntime | addon Godot MCP | Integração de inspeção/runtime |
| QualidadeGrafica | scripts/autoload/qualidade_grafica.gd | Presets gráficos |
| DialogueManager | scripts/dialogues/dialogue_manager.gd | Triggers, fila e reprodução de diálogos |

A ordem dos autoloads pode importar. Consulte project.godot antes de alterar inicialização e sinais.

## Sistemas de mundo

- **scripts/world/area_trigger.gd:** área genérica orientada a sinais; registra descoberta, interação e triggers de diálogo.
- **scripts/world/area_encomenda.gd:** interação com pacote.
- **scripts/world/area_plantio.gd:** plantio individual, persistência de posição e pulverização.
- **scripts/world/area_plantio_multimesh.gd:** alternativa MultiMesh não conectada ao mapa observado.
- **scripts/world/estacao_colocacao.gd:** instalação da estação.
- **scripts/world/clima.gd:** comportamento climático ligado a missão.
- **scripts/world/world_streamer.gd** e **chunk_data.gd:** carregamento/descarregamento das regiões.
- **scripts/world/limite_mapa.gd** e **rio_barreira.gd:** limites do espaço jogável.
- **scripts/world/tutorial_drone.gd** e **intro_cutscene.gd:** tutorial e introdução.

Confirme se o script está anexado a uma cena antes de concluir que está ativo.

## Personagens e controles

- **character/scripts/jogador.gd:** movimento a pé, animação, câmera, salto e áudio.
- **character/scripts/drone_jogador.gd:** pilotagem, interação, efeitos, spray e sinal de posição.
- **character/scripts/trator_jogador.gd:** condução, entrada/saída, câmera, rodas, áudio e prompt.
- **character/scripts/agrobot.gd:** comportamento do Agrobot.
- **scripts/ui/controles_toque.gd** e **scripts/ui/dispositivo.gd:** controles por dispositivo.

Os processos contínuos nesses controladores servem movimento, física e feedback. Reduza trabalho somente com profiling e preserve gravidade, colisão e input.

## Dados e recursos

- Missões: **data/configs/missoes.json**.
- Conteúdo educativo: **data/configs/conteudos.json**.
- Diálogos: **data/dialogues/**.
- Recursos de ambiente: **env models/**, **terrain mat/** e **terrain_Data/**.
- Addons incluem Terrain3D, Sky3D, Phantom Camera, lens flare e Godot MCP.

## Como navegar

1. Pesquise quem chama o sistema.
2. Leia o script e a cena que o instancia.
3. Leia JSON e recursos usados.
4. Verifique sinais emitidos e ouvintes.
5. Valide no fluxo real, além da sintaxe.

