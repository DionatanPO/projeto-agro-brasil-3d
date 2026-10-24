extends Node
## MissionManager: Gerencia o ciclo de vida das missões.
## - Carrega missões do JSON
## - Controla qual é a missão ativa
## - Persiste estado no SaveSystem
## - Emite sinais para UI (HUD, diário)

# NOTA: Não usar class_name aqui - o autoload em project.godot se chama "MissionManager"
# e já é acessível globalmente como MissionManager

signal mission_changed(mission_id)      # Missão ativa mudou (String or null)
signal mission_completed(mission_id: String)           # Missão concluída
signal mission_failed(mission_id: String, reason: String)
signal objective_completed(mission_id: String, objective_id: String)
signal missions_updated                                # Lista de missões mudou (para UI)

const CAMINHO_MISSOES := "res://data/configs/missoes.json"

var _todas_missoes: Array = []
var _missao_ativa = null
var _carregado: bool = false


func _ready() -> void:
	_carregar_missoes()
	_restaurar_do_save()
	
	# Conecta sinais do SaveSystem
	SaveSystem.progresso_carregado.connect(_on_save_loaded)
	SaveSystem.progresso_salvo.connect(_on_save_saved)
	
	# Conecta sinais das missões
	for m in _todas_missoes:
		m.mission_completed.connect(_on_mission_completed.bind(m.mission_id))
		m.mission_failed.connect(_on_mission_failed.bind(m.mission_id))
		m.objective_completed.connect(_on_objective_completed.bind(m.mission_id))


func _carregar_missoes() -> void:
	_todas_missoes.clear()
	
	var arq := FileAccess.open(CAMINHO_MISSOES, FileAccess.READ)
	if arq == null:
		push_error("MissionManager: arquivo não encontrado: " + CAMINHO_MISSOES)
		return
	
	var parsed: Variant = JSON.parse_string(arq.get_as_text())
	if not (parsed is Dictionary):
		push_error("MissionManager: JSON inválido")
		return
	
	var missoes_data: Array = (parsed as Dictionary).get("missoes", [])
	
	# Ordena por ordem
	missoes_data.sort_custom(func(a: Variant, b: Variant) -> bool:
		var oa: int = (a as Dictionary).get("ordem", 0) if a is Dictionary else 0
		var ob: int = (b as Dictionary).get("ordem", 0) if b is Dictionary else 0
		return oa < ob
	)
	
	for m_data: Variant in missoes_data:
		if not (m_data is Dictionary):
			continue
		var d: Dictionary = m_data as Dictionary
		if not d.has("id"):
			continue
		
		var mission = _criar_missao_de_dict(d)
		if mission:
			_todas_missoes.append(mission)
			add_child(mission)  # Para _ready e sinais
			mission._on_register()
	
	_carregado = true
	missions_updated.emit()
	print("[MissionManager] Carregadas ", _todas_missoes.size(), " missões")


func _criar_missao_de_dict(data: Dictionary) -> MissionBase:
	var tipo: String = str(data.get("tipo", "discovery"))
	var mission: MissionBase
	
	match tipo:
		"discovery", "descoberta":
			mission = DiscoveryMission.new()
		_:
			push_warning("MissionManager: tipo de missão desconhecido '", tipo, "', usando DiscoveryMission")
			mission = DiscoveryMission.new()
	
	# Preenche campos comuns
	mission.mission_id = str(data.get("id", ""))
	mission.titulo = str(data.get("titulo", ""))
	mission.descricao = str(data.get("descricao", ""))
	mission.ordem = int(data.get("ordem", 0))
	
	# Objetivos
	mission.objetivos = data.get("objetivos", [])
	
	# Recompensas
	mission.recompensas = data.get("recompensas", [])
	
	# Pré-requisitos
	mission.requer = data.get("requer", [])
	
	return mission


func _restaurar_do_save() -> void:
	var save_data: Dictionary = SaveSystem.dados
	var missoes_save: Array = save_data.get("missoes_estado", [])
	
	if missoes_save.is_empty():
		# Migração: save antigo só tinha array de IDs concluídas
		_migrar_save_antigo(save_data)
		return
	
	for m_save: Variant in missoes_save:
		if not (m_save is Dictionary):
			continue
		var d: Dictionary = m_save as Dictionary
		var mid: String = str(d.get("mission_id", ""))
		var mission = get_mission(mid)
		if mission:
			mission.load_save_data(d)
			if mission.is_concluida():
				print("[MissionManager] Missão restaurada como concluída: ", mid)
			elif mission.is_ativa():
				_definir_missao_ativa(mission)
	
	# Se nenhuma ativa, ativa a primeira pendente
	if _missao_ativa == null:
		_ativar_proxima_pendente()


func _migrar_save_antigo(save_data: Dictionary) -> void:
	"""Migra save antigo (apenas array missoes_concluidas) para novo formato."""
	var concluidas_antigas: Array = save_data.get("missoes_concluidas", [])
	var descobertas: Array = save_data.get("descobertas", [])
	
	for m in _todas_missoes:
		if m.mission_id in concluidas_antigas:
			# Marca todos objetivos como completos
			for obj in m.objetivos:
				var oid: String = str(obj.get("id", ""))
				if not oid.is_empty():
					m._progresso_objetivos[oid] = 1.0
			m._concluida = true
			print("[MissionManager] Migração: missão ", m.mission_id, " marcada como concluída")
	
	# Ativa a primeira não concluída
	_ativar_proxima_pendente()


func _ativar_proxima_pendente() -> void:
	for m in _todas_missoes:
		if not m.is_concluida() and not m.is_falhada():
			# Verifica pré-requisitos
			var prereqs_ok: bool = true
			for req_id in m.requer:
				var req_mission = get_mission(req_id)
				if not req_mission or not req_mission.is_concluida():
					prereqs_ok = false
					break
			if prereqs_ok:
				_definir_missao_ativa(m)
				return
	# Nenhuma pendente disponível
	_missao_ativa = null
	mission_changed.emit(null)


func _definir_missao_ativa(mission: MissionBase) -> void:
	if _missao_ativa == mission:
		return
	
	if _missao_ativa:
		_missao_ativa._on_deactivate()
	
	_missao_ativa = mission
	if _missao_ativa:
		_missao_ativa._on_activate()
		_save_missoes_estado()
	
	mission_changed.emit(_missao_ativa.mission_id if _missao_ativa else null)
	print("[MissionManager] Missão ativa: ", _missao_ativa.mission_id if _missao_ativa else "nenhuma")


func _on_mission_completed(mission_id: String) -> void:
	print("[MissionManager] Missão completada: ", mission_id)
	_save_missoes_estado()
	mission_completed.emit(mission_id)
	
	# Ativa próxima missão após um frame (deixa UI reagir)
	call_deferred("_ativar_proxima_pendente")


func _on_mission_failed(mission_id: String, reason: String) -> void:
	print("[MissionManager] Missão falhou: ", mission_id, " - ", reason)
	_save_missoes_estado()
	mission_failed.emit(mission_id, reason)


func _on_objective_completed(mission_id: String, objective_id: String) -> void:
	objective_completed.emit(mission_id, objective_id)
	_save_missoes_estado()


func _on_save_loaded(data: Dictionary) -> void:
	# SaveSystem recarregou (ex: Continue jogo) - restaura estado
	_restaurar_do_save()


func _on_save_saved() -> void:
	# SaveSystem salvou - garante que nosso estado está no dicionário
	_save_missoes_estado()


func _save_missoes_estado() -> void:
	var arr: Array = []
	for m in _todas_missoes:
		arr.append(m.get_save_data())
	SaveSystem.dados["missoes_estado"] = arr
	# Não chamamos SaveSystem.salvar() aqui para evitar loop - 
	# o SaveSystem já salva periodicamente ou em eventos importantes


## API Pública ────────────────────────────────────────────────────────────────

func get_mission(mission_id):
	for m in _todas_missoes:
		if m.mission_id == mission_id:
			return m
	return null


func get_missao_ativa():
	return _missao_ativa


func get_todas_missoes():
	return _todas_missoes.duplicate()


func get_proxima_pendente():
	for m in _todas_missoes:
		if not m.is_concluida() and not m.is_falhada():
			var prereqs_ok: bool = true
			for req_id in m.requer:
				var req_m = get_mission(req_id)
				if not req_m or not req_m.is_concluida():
					prereqs_ok = false
					break
			if prereqs_ok:
				return m
	return null


func esta_concluida(mission_id: String) -> bool:
	var m = get_mission(mission_id)
	return m != null and m.is_concluida()


func total_concluidas() -> int:
	var count := 0
	for m in _todas_missoes:
		if m.is_concluida():
			count += 1
	return count


func total_missoes() -> int:
	return _todas_missoes.size()


## Para compatibilidade com código antigo (Missoes autoload) ────────────────

func concluidas() -> Array:
	var arr: Array = []
	for m in _todas_missoes:
		if m.is_concluida():
			arr.append(m.mission_id)
	return arr


func por_id() -> Dictionary:
	var d: Dictionary = {}
	for m in _todas_missoes:
		d[m.mission_id] = {
			"id": m.mission_id,
			"titulo": m.titulo,
			"descricao": m.descricao,
			"objetivos": m.objetivos,
			"pontos_ids": _extrair_pontos_ids(m.objetivos),
			"dialogo_id": "",  # legacy
			"ordem": m.ordem,
		}
	return d


func objetivos_da_missao(mission_id: String) -> Array:
	var m = get_mission(mission_id)
	return m.objetivos if m else []


func missao_atual() -> Dictionary:
	var m = get_missao_ativa()
	if m:
		return {
			"id": m.mission_id,
			"titulo": m.titulo,
			"descricao": m.descricao,
			"objetivos": m.objetivos,
			"ordem": m.ordem,
		}
	return {}


func dialogo_da_missao_atual() -> String:
	var m = get_missao_ativa()
	return ""  # legacy


func _extrair_pontos_ids(objetivos: Array) -> Array:
	var arr: Array = []
	for obj in objetivos:
		if obj is Dictionary:
			var alvo: String = str(obj.get("alvo_id", ""))
			if not alvo.is_empty():
				arr.append(alvo)
	return arr