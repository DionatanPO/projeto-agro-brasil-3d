extends Area3D
## AreaTrigger: Área genérica para disparar eventos de missão.
## Configurável via inspector - sem código customizado por missão.
##
## Uso:
## 1. Adicionar AreaTrigger na cena (world.tscn)
## 2. Configurar: trigger_type, mission_id, objective_id, discovery_id
## 3. O MissionManager ouve os sinais e atualiza a missão

class_name AreaTrigger

signal player_entered(trigger)
signal player_exited(trigger)
signal interaction_requested(trigger)  # Jogador pressionou E

enum TriggerType {
	ENTER_AREA,        # Jogador entrou na área (discovery/area_enter)
	INTERACTION,       # Jogador pressionou E próximo (interacao)
	AUTO_COMPLETE,     # Completa objetivo automaticamente ao entrar
}

@export var trigger_type: TriggerType = TriggerType.ENTER_AREA

@export var mission_id: String = ""           # ID da missão relacionada
@export var objective_id: String = ""         # ID do objetivo a completar
@export var discovery_id: String = ""         # ID da descoberta a registrar (para ENTER_AREA)

@export var require_active_mission: bool = true  # Só dispara se missão estiver ativa
@export var auto_register_discovery: bool = true # Registra discovery_id automaticamente

@export var show_prompt: bool = true           # Mostra "Pressione E" no HUD
@export var prompt_text: String = "Pressione E para interagir"
@export var interaction_distance: float = 3.0  # Distância max para interação

var _player_inside: bool = false
var _player_ref: Node3D = null
var _prompt_showing: bool = false


func _ready() -> void:
	# Configura colisão
	var shape = CylinderShape3D.new()
	shape.radius = 5.0
	shape.height = 2.0
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 1.0, 0)
	add_child(col)
	
	# Conecta sinais de área
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Monitoramento de input para interação
	set_process_input(true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if trigger_type != TriggerType.INTERACTION:
		return
	if not _player_inside or not _player_ref:
		return
	
	var dist := global_position.distance_to(_player_ref.global_position)
	var can_interact := dist <= interaction_distance
	
	if can_interact and not _prompt_showing and show_prompt:
		_mostrar_prompt()
	elif not can_interact and _prompt_showing:
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
	player_entered.emit(self)
	
	if trigger_type == TriggerType.ENTER_AREA:
		_processar_enter_area()
	elif trigger_type == TriggerType.AUTO_COMPLETE:
		_processar_auto_complete()


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
	
	# Registra descoberta se configurado
	if auto_register_discovery and not discovery_id.is_empty():
		if is_instance_valid(Jogo):
			Jogo.registrar_descoberta(discovery_id)
	
	# Emite sinal para MissionManager processar
	# (MissionManager conecta a este sinal via mission_id/objective_id)


func _processar_auto_complete() -> void:
	if require_active_mission and not _missao_esta_ativa():
		return
	# Missão/objetivo completado automaticamente
	# MissionManager vai ouvir via sinal personalizado se necessário


func _missao_esta_ativa() -> bool:
	if mission_id.is_empty():
		return true  # Sem mission_id = sempre ativo
	var mm = get_node_or_null("/root/MissionManager")
	if mm:
		var m = mm.get_missao_ativa()
		return m != null and m.mission_id == mission_id
	return false


func _mostrar_prompt() -> void:
	if not show_prompt or _prompt_showing:
		return
	_prompt_showing = true
	# Emite sinal para HUD mostrar (HUD pode conectar a este sinal)
	player_entered.emit(self)  # Reutiliza sinal existente


func _esconder_prompt() -> void:
	if not _prompt_showing:
		return
	_prompt_showing = false
	player_exited.emit(self)  # Reutiliza sinal existente


## API para MissionManager configurar dinamicamente ────────────────────────

func configurar(p_mission_id: String, p_objective_id: String, p_discovery_id: String = "", p_type: int = 0) -> void:
	mission_id = p_mission_id
	objective_id = p_objective_id
	discovery_id = p_discovery_id
	trigger_type = TriggerType(p_type)