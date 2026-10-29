extends Node3D
## MissionBase: Classe base abstrata para todas as missões.
## Subclasses implementam check_progress() para lógica específica.
##
## Uso: Instanciar via MissionManager.register_mission() ou definir em JSON.

class_name MissionBase

signal objective_completed(objective_id: String)
signal mission_completed(mission_id: String)
signal mission_failed(mission_id: String, reason: String)

# Identificador único da missão (deve bater com o JSON)
@export var mission_id: String = ""

# Título exibido no HUD/diário
@export var titulo: String = ""

# Descrição longa
@export var descricao: String = ""

# Objetivos: Array de {id, texto, tipo, alvo_id, quantidade, opcional}
@export var objetivos: Array = []

# Recompensas: Array de {tipo: "xp|spawn|item", valor, cena_id, ...}
@export var recompensas: Array = []

# Pré-requisitos: IDs de missões que devem estar concluídas
@export var requer: Array = []

# Ordem de exibição/sequência
@export var ordem: int = 0

# Estado interno (serializável para save)
var _progresso_objetivos: Dictionary = {}  # objective_id -> progresso (float 0..1 ou int)
var _ativa: bool = false
var _concluida: bool = false
var _falhou: bool = false


func _ready() -> void:
	# Inicializa progresso dos objetivos
	for obj in objetivos:
		var oid: String = str(obj.get("id", ""))
		if not oid.is_empty():
			_progresso_objetivos[oid] = 0


## API Pública ────────────────────────────────────────────────────────────────

func get_mission_id() -> String:
	return mission_id


func is_ativa() -> bool:
	return _ativa


func is_concluida() -> bool:
	return _concluida


func is_falhada() -> bool:
	return _falhou


func get_progresso_objetivo(objective_id) -> float:
	return _progresso_objetivos.get(objective_id, 0.0)


func get_progresso_total() -> float:
	if objetivos.is_empty():
		return 1.0
	var total: float = 0.0
	for obj in objetivos:
		var oid: String = str(obj.get("id", ""))
		total += _progresso_objetivos.get(oid, 0.0)
	return total / objetivos.size()


## Métodos Virtuais (subclasses sobrescrevem) ────────────────────────────────

func _on_register() -> void:
	"""Chamado ao registrar no MissionManager. Carrega estado do save."""
	pass


func _on_activate() -> void:
	"""Chamado quando a missão torna-se a ativa atual."""
	_ativa = true


func _on_deactivate() -> void:
	"""Chamado quando a missão deixa de ser a ativa."""
	_ativa = false


func check_progress(game_state: Dictionary) -> bool:
	"""
	Verifica se a missão deve progredir/completar baseado no estado do jogo.
	Retorna true se a missão foi concluída nesta verificação.
	Deve ser implementado pela subclasse.
	"""
	push_error("MissionBase.check_progress() deve ser implementado na subclasse: " + mission_id)
	return false


func on_objective_event(event_type: String, event_data: Dictionary) -> bool:
	"""
	Recebe eventos do jogo (descoberta, coleta, kill, etc.).
	Retorna true se algum objetivo progrediu.
	"""
	return false


## Recompensas ────────────────────────────────────────────────────────────────

func _aplicar_recompensas() -> void:
	for r in recompensas:
		_aplicar_recompensa_unica(r)


func _aplicar_recompensa_unica(reward: Dictionary) -> void:
	var tipo: String = str(reward.get("tipo", ""))
	match tipo:
		"xp":
			var valor: int = int(reward.get("valor", 0))
			if valor > 0 and is_instance_valid(XPManager):
				XPManager.add_xp(valor)
		"spawn":
			var cena_path: String = str(reward.get("cena", ""))
			if not cena_path.is_empty():
				_spawn_recompensa_cena(cena_path, reward)
		"item":
			# Para futuro sistema de inventário
			pass
		_:
			push_warning("MissionBase: tipo de recompensa desconhecido: " + tipo)


func _spawn_recompensa_cena(cena_path: String, reward: Dictionary) -> void:
	var cena = load(cena_path) as PackedScene
	if cena == null:
		push_error("MissionBase: cena de recompensa não encontrada: " + cena_path)
		return
	var instancia = cena.instantiate()
	if instancia == null:
		push_error("MissionBase: falha ao instanciar recompensa: " + cena_path)
		return
	
	# Posição de spawn: usa jogador se disponível, senão posição da missão
	var pos_spawn := Vector3.ZERO
	var player = get_tree().get_first_node_in_group("jogador") as Node3D
	if player:
		pos_spawn = player.global_position
	elif has_method("get_global_position"):
		pos_spawn = get_global_position()
	
	# Adiciona na cena atual
	var pai := get_tree().current_scene
	if pai == null:
		pai = get_parent()
	if pai:
		pai.add_child(instancia)
		instancia.global_position = pos_spawn
		
		# Se tem método ativar, chama (ex: Agrobot.ativar)
		if instancia.has_method("ativar"):
			instancia.ativar(pos_spawn)
	
	print("[MissionBase] Recompensa spawnada: ", cena_path, " em ", pos_spawn)


## Persistência (Save/Load) ─────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	"""Retorna dicionário serializável com o estado da missão."""
	return {
		"mission_id": mission_id,
		"ativa": _ativa,
		"concluida": _concluida,
		"falhou": _falhou,
		"progresso_objetivos": _progresso_objetivos,
	}


func load_save_data(data: Dictionary) -> void:
	"""Restaura estado da missão a partir do save."""
	_ativa = data.get("ativa", false)
	_concluida = data.get("concluida", false)
	_falhou = data.get("falhou", false)
	_progresso_objetivos = data.get("progresso_objetivos", {})
	
	# Se já concluída, garante que recompensas não sejam dadas de novo
	if _concluida:
		_concluida = true  # mantém


func resetar_estado() -> void:
	"""Zera o estado da missão (usado ao iniciar um Novo Jogo)."""
	_ativa = false
	_concluida = false
	_falhou = false
	_progresso_objetivos.clear()
	for obj in objetivos:
		var oid: String = str(obj.get("id", ""))
		if not oid.is_empty():
			_progresso_objetivos[oid] = 0.0


## Helpers ──────────────────────────────────────────────────────────────────

func _marcar_objetivo_completo(objective_id: String) -> void:
	if _progresso_objetivos.has(objective_id):
		_progresso_objetivos[objective_id] = 1.0
		objective_completed.emit(objective_id)
		print("[MissionBase] Objetivo completo: ", mission_id, " -> ", objective_id)


func _atualizar_progresso_objetivo(objective_id: String, progresso: float) -> void:
	if _progresso_objetivos.has(objective_id):
		_progresso_objetivos[objective_id] = clampf(progresso, 0.0, 1.0)


func atualizar_progresso_objetivo(objective_id: String, progresso: float) -> void:
	"""Atualiza o progresso de um objetivo (0.0 a 1.0). Chamado por sistemas externos (ex: AreaPlantio)."""
	_atualizar_progresso_objetivo(objective_id, progresso)


func _verificar_todos_objetivos() -> bool:
	for obj in objetivos:
		var oid: String = str(obj.get("id", ""))
		if _progresso_objetivos.get(oid, 0.0) < 1.0:
			return false
	return true


func _concluir_missao() -> void:
	if _concluida:
		return
	_concluida = true
	_ativa = false
	_aplicar_recompensas()
	mission_completed.emit(mission_id)
	print("[MissionBase] Missão CONCLUÍDA: ", mission_id)


func _falhar_missao(reason: String) -> void:
	if _falhou or _concluida:
		return
	_falhou = true
	_ativa = false
	mission_failed.emit(mission_id, reason)
	print("[MissionBase] Missão FALHOU: ", mission_id, " - ", reason)