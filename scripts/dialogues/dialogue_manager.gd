extends Node
## DialogueManager: sistema de diálogos data-driven, somente áudio (sem legendas).
##
## Estrutura de dados:
##   res://data/dialogues/index.json              -> lista de arquivos carregados
##   res://data/dialogues/<categoria>/*.json      -> definições de diálogos
##   res://assets/audio/dialogues/<categoria>/*   -> áudios (.wav/.ogg/.mp3)
##
## Formato de um diálogo:
## {
##   "id": "primeira_entrega_inicio",
##   "speaker": "player",
##   "audio": "player/primeira_entrega_1.wav",
##   "once": true,
##   "triggers": [
##     { "type": "mission_activated", "mission_id": "primeira_entrega" }
##   ],
##   "conditions": { "intro_seen": true }
## }
##
## Triggers suportados:
##   mission_activated, mission_completed, objective_completed,
##   area_entered, area_exited, npc_interaction, custom_signal, manual
##
## Condições suportadas:
##   intro_seen (bool), mission_active (id), mission_completed (id),
##   objective_incomplete (id), objective_complete (id), not_played (bool)
##
## Os diálogos marcados com "once" nunca repetem dentro do mesmo save.

signal dialogue_started(dialogue_id: String, speaker: String)
signal dialogue_finished(dialogue_id: String)

const INDEX_PATH := "res://data/dialogues/index.json"
const DIALOGUES_ROOT := "res://data/dialogues/"
const AUDIO_ROOT := "res://assets/audio/dialogues/"
const SAVE_KEY := "dialogos_tocados"

var _registry: Dictionary = {}   # dialogue_id -> dados do diálogo
var _played: Dictionary = {}     # dialogue_id -> true (persistido no save)
var _queue: Array = []           # fila de {id, data, once}
var _current_id: String = ""
var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "DialoguePlayer"
	_player.bus = "Voz" if AudioServer.get_bus_index("Voz") >= 0 else "Master"
	add_child(_player)
	_player.finished.connect(_on_audio_finished)

	_carregar_flags()
	_carregar_registry()
	_conectar_sinais()


## Carregamento ───────────────────────────────────────────────────────────────

func _carregar_flags() -> void:
	var raw: Variant = SaveSystem.dados.get(SAVE_KEY, {})
	if raw is Dictionary:
		_played = (raw as Dictionary).duplicate()
	else:
		_played = {}


func _carregar_registry() -> void:
	_registry.clear()

	var arq := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if arq == null:
		push_error("DialogueManager: índice não encontrado em " + INDEX_PATH)
		return

	var parsed: Variant = JSON.parse_string(arq.get_as_text())
	if not (parsed is Dictionary):
		push_error("DialogueManager: índice inválido em " + INDEX_PATH)
		return

	var entries_raw: Variant = (parsed as Dictionary).get("entries", [])
	var entries: Array = entries_raw if entries_raw is Array else []
	for entry_raw in entries:
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var categoria: String = str(entry.get("category", ""))
		var arquivo: String = str(entry.get("file", ""))
		if categoria.is_empty() or arquivo.is_empty():
			push_warning("DialogueManager: entrada inválida no índice: " + str(entry))
			continue
		_carregar_arquivo(categoria, arquivo)

	print("[DialogueManager] ", _registry.size(), " diálogo(s) carregado(s).")


func _carregar_arquivo(categoria: String, arquivo: String) -> void:
	var caminho: String = DIALOGUES_ROOT + arquivo
	var arq := FileAccess.open(caminho, FileAccess.READ)
	if arq == null:
		push_warning("DialogueManager: arquivo não encontrado: " + caminho)
		return

	var parsed: Variant = JSON.parse_string(arq.get_as_text())
	if not (parsed is Dictionary):
		push_warning("DialogueManager: JSON inválido em " + caminho)
		return

	var lista_raw: Variant = (parsed as Dictionary).get("dialogues", [])
	var lista: Array = lista_raw if lista_raw is Array else []
	for d_raw in lista:
		if not (d_raw is Dictionary):
			continue
		var d: Dictionary = d_raw
		var id: String = str(d.get("id", ""))
		if id.is_empty():
			push_warning("DialogueManager: diálogo sem 'id' em " + caminho)
			continue
		if _registry.has(id):
			push_warning("DialogueManager: id duplicado ignorado: " + id)
			continue
		d["category"] = categoria
		d["source"] = arquivo
		_registry[id] = d


## Conexões com o mundo ───────────────────────────────────────────────────────

func _conectar_sinais() -> void:
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		push_warning("DialogueManager: MissionManager indisponível.")
	else:
		if mm.has_signal("mission_changed") and not mm.is_connected("mission_changed", _on_mission_changed):
			mm.connect("mission_changed", _on_mission_changed)
		if mm.has_signal("mission_completed") and not mm.is_connected("mission_completed", _on_mission_completed):
			mm.connect("mission_completed", _on_mission_completed)
		if mm.has_signal("objective_completed") and not mm.is_connected("objective_completed", _on_objective_completed):
			mm.connect("objective_completed", _on_objective_completed)

	if not SaveSystem.progresso_carregado.is_connected(_on_save_loaded):
		SaveSystem.progresso_carregado.connect(_on_save_loaded)


func _on_save_loaded(_dados: Dictionary) -> void:
	# Novo jogo / save recarregado: zera diálogos tocados e para a reprodução atual.
	_carregar_flags()
	_queue.clear()
	_current_id = ""
	if _player != null and _player.playing:
		_player.stop()


## API pública ────────────────────────────────────────────────────────────────

func play(dialogue_id: String) -> void:
	"""Toca um diálogo diretamente (entra na fila)."""
	if not _registry.has(dialogue_id):
		push_warning("DialogueManager: diálogo desconhecido: " + dialogue_id)
		return
	var data: Dictionary = _registry[dialogue_id]
	var once: bool = bool(data.get("once", false))
	if once and _ja_tocado(dialogue_id):
		return
	_enfileirar(dialogue_id, data, once)


func play_immediate(dialogue_id: String) -> void:
	"""Interrompe o diálogo atual e toca este imediatamente."""
	if not _registry.has(dialogue_id):
		push_warning("DialogueManager: diálogo desconhecido: " + dialogue_id)
		return
	if _player != null and _player.playing:
		_player.stop()
	if not _current_id.is_empty():
		var antigo: String = _current_id
		_current_id = ""
		dialogue_finished.emit(antigo)
	_queue.clear()
	var data: Dictionary = _registry[dialogue_id]
	_iniciar(dialogue_id, data, bool(data.get("once", false)))


func esta_tocando() -> bool:
	return not _current_id.is_empty()


func id_atual() -> String:
	return _current_id


func on_intro_finished() -> void:
	"""Chamado pela IntroCutscene ao terminar. Reavalia os diálogos da missão ativa."""
	_reevaluar_missao_ativa()


func request_custom(signal_name: String) -> void:
	"""Permite que sistemas externos disparem triggers do tipo 'custom_signal'."""
	_avaliar_todos({ "type": "custom_signal", "signal": signal_name })


func register_area_trigger(area: Node) -> void:
	"""Chamado por AreaTrigger._ready() para conectar os sinais de área."""
	if area == null:
		return
	if area.has_signal("player_entered") and not area.is_connected("player_entered", _on_area_entered):
		area.connect("player_entered", _on_area_entered)
	if area.has_signal("player_exited") and not area.is_connected("player_exited", _on_area_exited):
		area.connect("player_exited", _on_area_exited)
	if area.has_signal("interaction_requested") and not area.is_connected("interaction_requested", _on_area_interaction):
		area.connect("interaction_requested", _on_area_interaction)


## Handlers de sinais ────────────────────────────────────────────────────────

func _on_mission_changed(mission_id: Variant) -> void:
	if mission_id == null:
		return
	var mid: String = str(mission_id)
	if mid.is_empty():
		return
	_avaliar_todos({ "type": "mission_activated", "mission_id": mid })


func _on_mission_completed(mission_id: String) -> void:
	_avaliar_todos({ "type": "mission_completed", "mission_id": mission_id })


func _on_objective_completed(mission_id: String, objective_id: String) -> void:
	_avaliar_todos({
		"type": "objective_completed",
		"mission_id": mission_id,
		"objective_id": objective_id,
	})


func _on_area_entered(area: Node) -> void:
	var context := _contexto_de_area(area, "area_entered")
	if context.is_empty():
		return
	_avaliar_todos(context)


func _on_area_exited(area: Node) -> void:
	var context := _contexto_de_area(area, "area_exited")
	if context.is_empty():
		return
	_avaliar_todos(context)


func _on_area_interaction(area: Node) -> void:
	var context := _contexto_de_area(area, "npc_interaction")
	if context.is_empty():
		return
	var objective_id: String = _string_da_propriedade(area, "objective_id")
	if objective_id.is_empty():
		return
	context["objective_id"] = objective_id
	_avaliar_todos(context)


## Avaliação de triggers ─────────────────────────────────────────────────────

func _avaliar_todos(context: Dictionary) -> void:
	for dialogue_id in _registry.keys():
		_avaliar_dialogo(str(dialogue_id), context)


func _avaliar_dialogo(dialogue_id: String, context: Dictionary) -> void:
	var data: Dictionary = _registry[dialogue_id]

	var triggers_raw: Variant = data.get("triggers", [])
	var triggers: Array = triggers_raw if triggers_raw is Array else []
	for trigger_raw in triggers:
		if not (trigger_raw is Dictionary):
			continue
		var trigger: Dictionary = trigger_raw
		if not _trigger_corresponde(trigger, context):
			continue

		var conds_raw: Variant = data.get("conditions", {})
		var conds: Dictionary = conds_raw if conds_raw is Dictionary else {}
		if not _condicoes_ok(conds, dialogue_id):
			continue

		var once: bool = bool(data.get("once", false)) or bool(trigger.get("once", false))
		if once and _ja_tocado(dialogue_id):
			continue

		_enfileirar(dialogue_id, data, once)
		return  # primeiro trigger que casa (prioridade = ordem no JSON)


func _trigger_corresponde(trigger: Dictionary, context: Dictionary) -> bool:
	var tipo: String = str(trigger.get("type", ""))
	if tipo != str(context.get("type", "")):
		return false

	match tipo:
		"mission_activated", "mission_completed":
			return str(trigger.get("mission_id", "")) == str(context.get("mission_id", ""))

		"objective_completed":
			return str(trigger.get("mission_id", "")) == str(context.get("mission_id", "")) \
				and str(trigger.get("objective_id", "")) == str(context.get("objective_id", ""))

		"area_entered", "area_exited":
			if str(trigger.get("area_id", "")) != str(context.get("area_id", "")):
				return false
			var mission_trigger: String = str(trigger.get("mission_id", ""))
			if mission_trigger.is_empty():
				return true
			return mission_trigger == str(context.get("mission_id", ""))

		"npc_interaction":
			return str(trigger.get("mission_id", "")) == str(context.get("mission_id", "")) \
				and str(trigger.get("objective_id", "")) == str(context.get("objective_id", ""))

		"custom_signal":
			return str(trigger.get("signal", "")) == str(context.get("signal", ""))

	return false


func _condicoes_ok(conds: Dictionary, dialogue_id: String) -> bool:
	if conds.is_empty():
		return true

	if conds.has("intro_seen"):
		var esperado: bool = bool(conds.get("intro_seen", true))
		if bool(SaveSystem.dados.get("intro_mundo_vista", false)) != esperado:
			return false

	if bool(conds.get("not_played", false)) and _ja_tocado(dialogue_id):
		return false

	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		return not (conds.has("mission_active") or conds.has("mission_completed") \
			or conds.has("objective_incomplete") or conds.has("objective_complete"))

	if conds.has("mission_active"):
		var ativa: Variant = mm.get_missao_ativa()
		if ativa == null or str(ativa.mission_id) != str(conds.get("mission_active", "")):
			return false

	if conds.has("mission_completed"):
		var missao: Variant = mm.get_mission(str(conds.get("mission_completed", "")))
		if missao == null or not bool(missao.is_concluida()):
			return false

	var obj_incompleto: String = str(conds.get("objective_incomplete", ""))
	if not obj_incompleto.is_empty():
		var ativa2: Variant = mm.get_missao_ativa()
		if ativa2 == null or float(ativa2.get_progresso_objetivo(obj_incompleto)) >= 1.0:
			return false

	var obj_completo: String = str(conds.get("objective_complete", ""))
	if not obj_completo.is_empty():
		var ativa3: Variant = mm.get_missao_ativa()
		if ativa3 == null or float(ativa3.get_progresso_objetivo(obj_completo)) < 1.0:
			return false

	return true


## Fila e reprodução ────────────────────────────────────────────────────────

func _enfileirar(dialogue_id: String, data: Dictionary, once: bool) -> void:
	if _current_id == dialogue_id:
		return
	for item_raw in _queue:
		if item_raw is Dictionary and str((item_raw as Dictionary).get("id", "")) == dialogue_id:
			return
	_queue.append({ "id": dialogue_id, "data": data, "once": once })
	_tocar_proximo()


func _tocar_proximo() -> void:
	if not _current_id.is_empty():
		return
	while not _queue.is_empty():
		var item_raw: Variant = _queue.pop_front()
		if not (item_raw is Dictionary):
			continue
		var item: Dictionary = item_raw
		var data_raw: Variant = item.get("data", {})
		if not (data_raw is Dictionary):
			continue
		if _iniciar(str(item.get("id", "")), data_raw, bool(item.get("once", false))):
			return


func _iniciar(dialogue_id: String, data: Dictionary, once: bool) -> bool:
	var audio_rel: String = str(data.get("audio", ""))
	if audio_rel.is_empty():
		push_warning("DialogueManager: diálogo sem áudio: " + dialogue_id)
		return false

	var caminho: String = AUDIO_ROOT + audio_rel
	if not ResourceLoader.exists(caminho):
		push_warning("DialogueManager: áudio não encontrado: " + caminho + " (diálogo " + dialogue_id + ")")
		return false

	var stream: AudioStream = load(caminho) as AudioStream
	if stream == null:
		push_warning("DialogueManager: falha ao carregar áudio: " + caminho)
		return false

	_player.stream = stream
	_player.play()
	_current_id = dialogue_id

	if once:
		_marcar_tocado(dialogue_id)

	dialogue_started.emit(dialogue_id, str(data.get("speaker", "player")))
	print("[DialogueManager] Tocando: ", dialogue_id, " -> ", caminho)
	return true


func _on_audio_finished() -> void:
	var finalizado: String = _current_id
	_current_id = ""
	if not finalizado.is_empty():
		dialogue_finished.emit(finalizado)
		print("[DialogueManager] Finalizado: ", finalizado)
	_tocar_proximo()


## Flags persistidas ────────────────────────────────────────────────────────

func _ja_tocado(dialogue_id: String) -> bool:
	return bool(_played.get(dialogue_id, false))


func _marcar_tocado(dialogue_id: String) -> void:
	if _ja_tocado(dialogue_id):
		return
	_played[dialogue_id] = true
	SaveSystem.dados[SAVE_KEY] = _played
	SaveSystem.salvar()


func _reevaluar_missao_ativa() -> void:
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		return
	var ativa: Variant = mm.get_missao_ativa()
	if ativa == null:
		return
	var mid: String = str(ativa.mission_id)
	if mid.is_empty():
		return
	_avaliar_todos({ "type": "mission_activated", "mission_id": mid })


## Helpers de área ───────────────────────────────────────────────────────────

func _contexto_de_area(area: Node, tipo: String) -> Dictionary:
	if area == null:
		return {}
	var area_id: String = _string_da_propriedade(area, "dialogue_area_id")
	if area_id.is_empty():
		area_id = str(area.name)
	if area_id.is_empty():
		return {}

	var context: Dictionary = { "type": tipo, "area_id": area_id }
	# Usa a missão ATIVA, e não a missão configurada no nó da área: um diálogo
	# de área só deve tocar enquanto a missão dele estiver em andamento.
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm != null:
		var ativa: Variant = mm.get_missao_ativa()
		if ativa != null:
			var mid: String = str(ativa.mission_id)
			if not mid.is_empty():
				context["mission_id"] = mid
	return context


func _string_da_propriedade(objeto: Object, propriedade: String) -> String:
	if objeto == null:
		return ""
	var valor: Variant = objeto.get(propriedade)
	if valor == null:
		return ""
	return str(valor)
