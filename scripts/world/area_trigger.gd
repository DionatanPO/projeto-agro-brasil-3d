extends Area3D
## AreaTrigger: área genérica para disparar eventos de missão e diálogos.
## Totalmente configurável pelo inspector - sem código por missão.
##
## Uso:
## 1. Adicionar um nó AreaTrigger na cena.
## 2. Configurar: trigger_type, mission_id, objective_id, discovery_id,
##    dialogue_area_id, raio/altura.
## 3. Missões e diálogos reagem via sinais (MissionManager / DialogueManager).
##
## Se nenhum CollisionShape3D for adicionado como filho, um cilindro é criado
## automaticamente com base em `radius` e `height`.

class_name AreaTrigger

signal player_entered(trigger)
signal player_exited(trigger)
signal interaction_requested(trigger)   # Jogador pressionou E
signal prompt_show_requested(trigger)   # Para o HUD mostrar "Pressione E"
signal prompt_hide_requested(trigger)

enum TriggerType {
	ENTER_AREA,      # Jogador entrou na área (registra descoberta)
	INTERACTION,     # Jogador pressionou E próximo
	AUTO_COMPLETE,   # Completa objetivo automaticamente ao entrar
}

@export var trigger_type: TriggerType = TriggerType.ENTER_AREA

@export_group("Missão")
@export var mission_id: String = ""          # ID da missão relacionada
@export var objective_id: String = ""        # ID do objetivo relacionado
@export var discovery_id: String = ""        # Descoberta registrada ao entrar
@export var require_active_mission: bool = true
@export var auto_register_discovery: bool = true

@export_group("Diálogo")
## Identificador usado nos JSONs de diálogo ("area_id").
## Se vazio, usa o nome do nó.
@export var dialogue_area_id: String = ""

@export_group("Scanner do Agrobot")
## Quantos pulsos de scanner o Agrobot dispara automaticamente ao entrar.
@export var pulsos_ao_entrar: int = 2

@export_group("Colisão")
@export var radius: float = 5.0
@export var height: float = 2.0
@export var collision_offset_y: float = 1.0
## Cria automaticamente o CollisionShape3D se o nó não tiver um filho.
@export var auto_create_collision: bool = true

@export_group("Interação")
@export var show_prompt: bool = true
@export var interaction_distance: float = 3.0

var _player_inside: bool = false
var _player_ref: Node3D = null
var _prompt_showing: bool = false


func _ready() -> void:
	add_to_group("area_trigger")

	if auto_create_collision and _achar_collision_shape() == null:
		_criar_collision_shape()

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	set_process_input(trigger_type == TriggerType.INTERACTION)
	set_physics_process(trigger_type == TriggerType.INTERACTION)

	var dm: Variant = get_node_or_null("/root/DialogueManager")
	if dm != null and dm.has_method("register_area_trigger"):
		dm.register_area_trigger(self)

	var mm_sinais: Variant = get_node_or_null("/root/MissionManager")
	if mm_sinais != null and mm_sinais.has_signal("mission_changed") \
			and not mm_sinais.is_connected("mission_changed", _on_mission_changed):
		mm_sinais.connect("mission_changed", _on_mission_changed)


func _criar_collision_shape() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var col := CollisionShape3D.new()
	col.name = "AutoCollisionShape3D"
	col.shape = shape
	col.position = Vector3(0, collision_offset_y, 0)
	add_child(col)


func _achar_collision_shape() -> CollisionShape3D:
	for filho in get_children():
		if filho is CollisionShape3D:
			return filho as CollisionShape3D
	return null


func _physics_process(_delta: float) -> void:
	if trigger_type != TriggerType.INTERACTION:
		return
	if not _player_inside or _player_ref == null:
		return

	var dist := global_position.distance_to(_player_ref.global_position)
	var pode_interagir := dist <= interaction_distance

	if pode_interagir and not _prompt_showing and show_prompt:
		_mostrar_prompt()
	elif not pode_interagir and _prompt_showing:
		_esconder_prompt()


func _input(event: InputEvent) -> void:
	if trigger_type != TriggerType.INTERACTION:
		return
	if not _player_inside or not _prompt_showing:
		return
	if event.is_action_pressed("interagir"):
		interaction_requested.emit(self)
		_esconder_prompt()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("jogador"):
		return

	_player_inside = true
	_player_ref = body
	# Emitido antes de registrar a descoberta: diálogos de chegada ainda veem
	# o objetivo como pendente.
	player_entered.emit(self)
	_pulsar_agrobot()

	if trigger_type == TriggerType.ENTER_AREA:
		_processar_enter_area()
	elif trigger_type == TriggerType.AUTO_COMPLETE:
		_processar_auto_complete()


func _on_mission_changed(_mission_id: Variant) -> void:
	# Se o jogador já estava dentro da área quando a missão ficou ativa,
	# o body_entered não dispara de novo: reavalia a entrada agora.
	if not _player_inside or _player_ref == null:
		return
	if trigger_type == TriggerType.INTERACTION:
		return
	if not mission_id.is_empty() and not _missao_esta_ativa():
		return
	player_entered.emit(self)
	_pulsar_agrobot()
	if trigger_type == TriggerType.ENTER_AREA:
		_processar_enter_area()
	elif trigger_type == TriggerType.AUTO_COMPLETE:
		_processar_auto_complete()


func _pulsar_agrobot() -> void:
	## Dispara o efeito de scanner do Agrobot (o mesmo do LT/Q), automaticamente.
	var agrobot: Node = get_tree().get_first_node_in_group("agrobot")
	if agrobot == null:
		return
	if agrobot.has_method("pulsar_automatico"):
		agrobot.pulsar_automatico(pulsos_ao_entrar)
	elif agrobot.has_method("disparar_pulso"):
		agrobot.disparar_pulso()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("jogador"):
		return

	_player_inside = false
	_player_ref = null
	_esconder_prompt()
	player_exited.emit(self)


func _processar_enter_area() -> void:
	if require_active_mission and not _missao_esta_ativa():
		return
	if auto_register_discovery and not discovery_id.is_empty():
		if is_instance_valid(Jogo):
			Jogo.registrar_descoberta(discovery_id)


func _processar_auto_complete() -> void:
	if require_active_mission and not _missao_esta_ativa():
		return
	# Objetivos são concluídos via descoberta ou sinal. Mantido para uso futuro.


func _missao_esta_ativa() -> bool:
	if mission_id.is_empty():
		return true
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		return false
	var ativa: Variant = mm.get_missao_ativa()
	return ativa != null and str(ativa.mission_id) == mission_id


func _mostrar_prompt() -> void:
	if not show_prompt or _prompt_showing:
		return
	_prompt_showing = true
	prompt_show_requested.emit(self)


func _esconder_prompt() -> void:
	if not _prompt_showing:
		return
	_prompt_showing = false
	prompt_hide_requested.emit(self)


## API para configurar dinamicamente ─────────────────────────────────────────

func configurar(p_mission_id: String, p_objective_id: String, p_discovery_id: String = "", p_type: TriggerType = TriggerType.ENTER_AREA) -> void:
	mission_id = p_mission_id
	objective_id = p_objective_id
	discovery_id = p_discovery_id
	trigger_type = p_type
