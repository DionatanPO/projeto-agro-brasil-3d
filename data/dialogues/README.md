# Sistema de Diálogos

Diálogos são **somente áudio** (sem legendas). Todo o conteúdo vem de dados (JSON),
nunca de código hardcoded.

## Estrutura

```
data/dialogues/
├── index.json                 # registro: só os arquivos listados aqui são carregados
├── missions/                  # diálogos ligados a missões
│   └── primeira_entrega.json
├── npcs/                      # diálogos de NPCs (futuro)
├── system/                    # narração, tutoriais, avisos
└── player/                    # monólogos do jogador
    └── monologues.json

assets/audio/dialogues/
├── missions/
├── npcs/
├── system/
└── player/
```

O caminho em `"audio"` é relativo a `res://assets/audio/dialogues/`.

## Formato

```json
{
  "id": "primeira_entrega_inicio",
  "speaker": "player",
  "audio": "player/primeira_entrega_1.wav",
  "once": true,
  "triggers": [
    { "type": "mission_activated", "mission_id": "primeira_entrega" }
  ],
  "conditions": { "intro_seen": true }
}
```

| Campo | Descrição |
| --- | --- |
| `id` | Identificador único. Usado nas flags de "já tocou". |
| `speaker` | `player`, `npc`, `narrator`… (para roteamento de voz no futuro). |
| `audio` | Caminho relativo do áudio. |
| `once` | Se `true`, nunca repete dentro do mesmo save. |
| `triggers` | Lista de eventos que disparam o diálogo (o primeiro que casar vence). |
| `conditions` | Filtros extras avaliados no momento do trigger. |

## Triggers

| Tipo | Campos | Quando dispara |
| --- | --- | --- |
| `mission_activated` | `mission_id` | Uma missão se torna a ativa. |
| `mission_completed` | `mission_id` | Uma missão é concluída. |
| `objective_completed` | `mission_id`, `objective_id` | Um objetivo é concluído. |
| `area_entered` | `area_id`, `mission_id` (opcional) | Jogador entra numa `AreaTrigger`. |
| `area_exited` | `area_id`, `mission_id` (opcional) | Jogador sai da `AreaTrigger`. |
| `npc_interaction` | `mission_id`, `objective_id` | Jogador interage (E) numa `AreaTrigger`. |
| `custom_signal` | `signal` | `DialogueManager.request_custom("nome")`. |
| `manual` | — | Só toca via `DialogueManager.play("id")`. |

## Condições

| Condição | Valor | Regra |
| --- | --- | --- |
| `intro_seen` | `bool` | Cutscene de introdução já foi vista? |
| `mission_active` | `mission_id` | A missão informada é a missão ativa. |
| `mission_completed` | `mission_id` | A missão informada já foi concluída. |
| `objective_incomplete` | `objective_id` | Objetivo da missão ativa ainda não foi concluído. |
| `objective_complete` | `objective_id` | Objetivo da missão ativa já foi concluído. |
| `not_played` | `bool` | Diálogo ainda não tocou neste save. |

## Fluxo da Primeira Entrega

1. Cutscene de introdução termina → `DialogueManager.on_intro_finished()`
   → `primeira_entrega_inicio` (monólogo do jogador).
2. Jogador entra na `AreaTrigger` da encomenda → `primeira_entrega_chegou_area`.
3. Jogador abre a caixa → descoberta `pacote` → objetivo `encontrar_encomenda`
   concluído → `primeira_entrega_abriu_caixa`.

## Como adicionar um NPC

1. Criar `data/dialogues/npcs/nome_do_npc.json` com um ou mais diálogos.
2. Adicionar o arquivo em `data/dialogues/index.json`.
3. Colocar os áudios em `assets/audio/dialogues/npcs/`.
4. Na cena, adicionar um `AreaTrigger` com `trigger_type = INTERACTION`,
   `dialogue_area_id` e os ids de missão/objetivo desejados.
