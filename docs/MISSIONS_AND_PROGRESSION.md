# Missões, objetivos e progressão

## Fontes da verdade

- Definições: **data/configs/missoes.json**.
- Gerenciador: **scripts/missions/mission_manager.gd**, autoload MissionManager.
- Classe base: **scripts/missions/mission_base.gd**.
- Implementação atual: **scripts/missions/discovery_mission.gd**.
- Descobertas: **scripts/autoload/jogo.gd**, autoload Jogo.
- Persistência: **scripts/autoload/save_system.gd**, autoload SaveSystem.
- XP e níveis: **scripts/autoload/xp_manager.gd**, autoload XPManager.
- HUD: **scripts/ui/hud.gd**.
- Conteúdo educativo: **data/configs/conteudos.json**.
- Áreas genéricas: **scripts/world/area_trigger.gd**.
- Eventos especiais: **area_encomenda.gd**, **area_plantio.gd**, **estacao_colocacao.gd**, **drone_jogador.gd**.

IDs são contratos entre JSON, cenas, save, diálogos e código. Antes de mudar um, pesquise globalmente e planeje migração para valores que já possam estar salvos.

## Campanha configurada

| Ordem | ID | Objetivos do JSON | Pré-requisito | XP |
|---:|---|---|---|---:|
| 1 | primeira_entrega | ir_local; encontrar_encomenda | nenhum | 100 |
| 2 | mostrar_fazenda_agrobot | escanear_solar; escanear_eolico; escanear_silo | primeira_entrega | 100 |
| 3 | plantio_milho | plantar_milho | mostrar_fazenda_agrobot | 150 |
| 4 | operacao_drone_milho | pegar_drone; pulverizar_milho | plantio_milho | 100 |
| 5 | colocar_estacao | encontrar_area_estacao; colocar_estacao | operacao_drone_milho | 200 |
| 6 | conhecer_agua | retornar_sede | colocar_estacao | 150 |
| 7 | proteger_equipamentos | abrigar_equipamentos | conhecer_agua | 150 |

Confirme no JSON antes de alterar; esta tabela deriva da configuração atual.

## Como os objetivos são disparados

### Primeira Entrega

AreaEncomendaTrigger em **world.tscn** registra local_encomenda ao entrar na área durante a missão. **scripts/world/area_encomenda.gd** abre o pacote e registra pacote. As duas descobertas completam a missão.

### Mostrar a Fazenda para o Agrobot

Triggers em **world.tscn** registram parque_solar, parque_eolico e silo; esses três alvos estão no JSON.

Existe também AreaFazendaCentroTrigger com objective_id apresentar_fazenda e discovery_id fazenda_centro. Esse objetivo não está em missoes.json. A descoberta pode ser usada por conteúdo/diálogo, mas a referência de objective_id precisa de confirmação antes de adicionar ou remover objetivo.

### Plantio de Milho

AreaPlantio em **world.tscn** usa **scripts/world/area_plantio.gd**, mission_id plantio_milho, objective_id plantar_milho e quantidade necessária 400. Uma interação planta até três pés, respeitando o máximo. Ao atingir 400, registra area_plantio_milho e conclui o objetivo. Posições são salvas para restauração. A implementação ativa cria nós individuais.

### Operação Drone: Pulverização

O drone registra drone_agricola ao ser ativado. Durante o spray emite pulverizando com sua posição. AreaPlantio busca plantas dentro do raio, registra novas posições pulverizadas e atualiza o percentual. percentual_necessario está em 0.8 (80%). Ao alcançar o limite registra milho_pulverizado. Progresso percentual e posições pulverizadas são estados distintos.

### Instalação da estação

AreaEstacaoDialogueTrigger registra area_estacao. **scripts/world/estacao_colocacao.gd** controla instalação e registra estacao_colocada/conclusão. Teste os dois objetivos separadamente e após reload.

### Chuva e proteção de equipamentos

AreaSedeTrigger registra sede para retornar_sede. **scripts/world/clima.gd** altera o clima ao iniciar proteger_equipamentos.

**Risco confirmado para investigar:** abrigar_equipamentos usa alvo_id sede, igual ao objetivo retornar_sede da missão anterior. DiscoveryMission reaproveita descobertas persistentes ao ativar uma missão. Se sede já estiver no save, a missão 7 pode completar esse objetivo automaticamente ao ser ativada, sem o jogador abrigar equipamento. Defina uma ação/evento próprio para o objetivo final e teste saves em que sede já foi descoberta.

## Ciclo de vida

1. MissionManager lê o JSON e cria objetos de missão como filhos.
2. DiscoveryMission mapeia alvo_id para objective_id e conecta-se a Jogo.descoberta_registrada.
3. MissionManager restaura missoes_estado; saves antigos podem usar missoes_concluidas.
4. A missão elegível é ativada e mission_changed é emitido.
5. O mundo registra descobertas ou chama conclusão por API.
6. MissionBase atualiza progresso, emite objective_completed e conclui após todos os objetivos.
7. XP vem das recompensas; MissionManager emite mission_completed e agenda a próxima missão.
8. HUD e DialogueManager reagem aos sinais.

DiscoveryMission só reage quando ativa. Na ativação ela reconcilia descobertas já salvas. Preserve a idempotência desse comportamento.

## Save

SaveSystem usa user://savegame.json. Chaves padrão incluem:

- versao, descobertas, missoes_estado e legado missoes_concluidas.
- xp, nivel e tempo_jogado_seg.
- posições de jogador, drone, trator e veículo selecionado.
- milhos_plantados_posicoes e milhos_pulverizados_posicoes.
- preferências de áudio, VSync, controles e tutorial.

SaveSystem carrega JSON na inicialização e grava quando solicitado; também agenda gravação em pausa/fechamento. Migrações devem preservar dados existentes. Consulte **KNOWN_ISSUES_AND_ROADMAP.md** para riscos atuais.

## XP e níveis

- Recompensas de missão são declaradas no JSON e aplicadas por MissionBase.
- XPManager mantém valores em cache e atualiza SaveSystem.dados; emite xp_changed, level_changed e level_up_reached.
- Limite: nível 30. Base de XP 100 e fator de crescimento 1.5. O custo do próximo nível é inteiro de 100 × 1.5^(nível atual - 1); XP total é a soma dos custos anteriores.
- Há métodos legados de XP por descoberta/missão/tempo. Confirme referências antes de tratá-los como sistema ativo.
- A migração de save antigo estima 100 XP por missão, embora recompensas atuais incluam 150 e 200. Não alterar sem plano de migração.

## Regras para editar a campanha

- IDs únicos e estáveis; objetivos com tipos suportados.
- Cada alvo deve estar conectado a evento real.
- Pré-requisitos formam grafo sem ciclos.
- Descobertas anteriores devem ser reconciliadas conscientemente.
- Objetivo/recompensa não pode duplicar em sinais repetidos.
- Separar descoberta permanente de progresso parcial.
- Testar objetivo, conclusão, próxima missão, UI, diálogo e reload.


