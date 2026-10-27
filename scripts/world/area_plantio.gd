extends Area3D
## AreaPlantio: área onde o jogador pode plantar milho clicando no chão.
##
## Uso:
## 1. Colocar um Area3D na área de terra (entre silo e parque solar)
## 2. Adicionar este script
## 3. Configurar: mission_id, objective_id, quantidade_necessaria
## 4. O jogador clica com o mouse dentro da área para plantar milho

class_name AreaPlantio

signal milho_plantado(posicao: Vector3)
signal plantio_completo(quantidade: int)

@export var mission_id: String = ""
@export var objective_id: String = ""
@export var quantidade_necessaria: int = 5
@export var cena_milho: String = "res://scenes/world/milho_plantavel.tscn"
@export var distancia_max_plantio: float = 15.0

var _milhos_plantados: int = 0
var _cena_milho: PackedScene
var _player: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_cena_milho = load(cena_milho) as PackedScene
	if _cena_milho == null:
		push_error("AreaPlantio: cena do milho não encontrada: " + cena_milho)
	
	add_to_group("area_plantio")
	
	# Referências
	_player = get_tree().get_first_node_in_group("jogador") as Node3D
	_camera = get_viewport().get_camera_3d()
	
	set_process_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _esta_ativa():
		return
	if not event.is_action_pressed("interagir"):
		return
	
	var player = get_tree().get_first_node_in_group("jogador") as Node3D
	if player == null:
		return
	
	# Verifica se o jogador está perto o suficiente da área
	var dist := global_position.distance_to(player.global_position)
	if dist > distancia_max_plantio:
		return
	
	# Raycast da câmera para o chão
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	
	var origem := camera.global_position
	var direcao := -camera.global_transform.basis.z
	var alvo := origem + direcao * 100.0
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origem, alvo)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 0xFFFFFFFF  # atinge todas as camadas (inclui Terrain3D)
	var resultado := space_state.intersect_ray(query)
	
	if resultado.is_empty():
		return
	
	var ponto := resultado.position as Vector3
	
	# Verifica se o ponto está dentro da área de plantio (usando o raio do collision shape)
	if not _ponto_dentro_da_area(ponto):
		return
	
	_plantar_milho(ponto)


func _ponto_dentro_da_area(ponto: Vector3) -> bool:
	# Verifica se o ponto está dentro dos limites do Area3D (usando o CollisionShape)
	var shape := _achar_collision_shape()
	if shape == null:
		return true  # Sem shape definido, permite em qualquer lugar próximo
	
	# Distância do ponto ao centro da área
	var dist := global_position.distance_to(ponto)
	var raio_efetivo := 8.0  # raio padrão de plantio
	
	if shape.shape is SphereShape3D:
		raio_efetivo = (shape.shape as SphereShape3D).radius
	elif shape.shape is BoxShape3D:
		var size := (shape.shape as BoxShape3D).size
		raio_efetivo = max(size.x, size.z) * 0.7
	
	return dist <= raio_efetivo


func _achar_collision_shape() -> CollisionShape3D:
	for filho in get_children():
		if filho is CollisionShape3D:
			return filho as CollisionShape3D
	return null


func _plantar_milho(ponto: Vector3) -> void:
	if _cena_milho == null:
		return
	
	var milho := _cena_milho.instantiate()
	if milho == null:
		push_error("AreaPlantio: falha ao instanciar milho")
		return
	
	# Ajusta a posição para ficar no chão (um pouco acima da superfície do raio)
	milho.global_position = ponto + Vector3(0, 0.1, 0)
	
	# Pequena variação aleatória na rotação para ficar mais natural
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	milho.rotation = Vector3(0, rng.randf_range(0, TAU), 0)
	
	var pai := get_tree().current_scene
	if pai == null:
		pai = get_parent()
	if pai:
		pai.add_child(milho)
	
	_milhos_plantados += 1
	milho_plantado.emit(ponto)
	print("[AreaPlantio] Milho plantado: ", _milhos_plantados, " / ", quantidade_necessaria)
	
	if _milhos_plantados >= quantidade_necessaria:
		plantio_completo.emit(_milhos_plantados)
		_completar_objetivo()


func _esta_ativa() -> bool:
	if mission_id.is_empty():
		return true
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		return false
	var ativa: Variant = mm.get_missao_ativa()
	return ativa != null and str(ativa.mission_id) == mission_id


func _completar_objetivo() -> void:
	if is_instance_valid(Jogo):
		Jogo.registrar_descoberta("area_plantio_milho")
	
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm != null and mm.has_method("check_progress"):
		mm.check_progress({"mission_id": mission_id, "objective_id": objective_id})


## API pública

func get_quantidade_plantada() -> int:
	return _milhos_plantados


func resetar() -> void:
	_milhos_plantados = 0
