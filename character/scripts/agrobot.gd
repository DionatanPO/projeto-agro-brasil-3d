extends Node3D
class_name Agrobot

## Agrobot: drone companheiro que flutua acima da cabeca e segue o jogador.
## Q / LT dispara um pulso de scanner (um anel que se expande no chao).
##
## Tudo o que o agrobot precisa esta NESTE script + a cena agrobot.tscn.
## Nao existe mais script separado de scanner.

@export var velocidade_seguir: float = 10.0
## Altura em relacao a origem do jogador (a origem fica ~1 m acima do chao).
## 1.0 deixa o agrobot logo acima da cabeca.
@export var offset_acima: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var raio_scanner: float = 18.0
@export var duracao_pulso: float = 1.4

var _jogador: Node3D = null
var _ativo := true
var _anel: MeshInstance3D
var _anel_mat: StandardMaterial3D
var _pulso := 1.0


func _ready() -> void:
	add_to_group("agrobot")
	_jogador = get_tree().get_first_node_in_group("jogador")
	if _jogador != null:
		global_position = _jogador.global_position + offset_acima
	_criar_anel()
	set_process(true)


func _process(delta: float) -> void:
	if not _ativo:
		return
	if _jogador == null or not is_instance_valid(_jogador):
		_jogador = get_tree().get_first_node_in_group("jogador")
		if _jogador == null:
			return

	# Segue acima da cabeca (suavizacao independente do framerate).
	var alvo := _jogador.global_position + offset_acima
	global_position = global_position.lerp(alvo, 1.0 - exp(-velocidade_seguir * delta))

	# Olha para o jogador (apenas yaw).
	var direcao := _jogador.global_position - global_position
	direcao.y = 0.0
	if direcao.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direcao.x, direcao.z), 1.0 - exp(-8.0 * delta))

	if Input.is_action_just_pressed("escanear"):
		disparar_pulso()

	_animar_pulso(delta)


## Chamado pela AreaEncomenda ao abrir a caixa.
func ativar(posicao_jogador: Vector3) -> void:
	global_position = posicao_jogador + offset_acima
	_ativo = true
	visible = true


func desativar() -> void:
	_ativo = false
	queue_free()


# ---------------------------------------------------------------- scanner

func _criar_anel() -> void:
	var malha := TorusMesh.new()
	malha.inner_radius = 0.94
	malha.outer_radius = 1.0

	_anel_mat = StandardMaterial3D.new()
	_anel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_anel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_anel_mat.albedo_color = Color(0.15, 0.8, 1.0, 0.0)
	_anel_mat.emission_enabled = true
	_anel_mat.emission = Color(0.15, 0.8, 1.0)

	_anel = MeshInstance3D.new()
	_anel.name = "PulsoScanner"
	_anel.mesh = malha
	_anel.material_override = _anel_mat
	_anel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_anel.top_level = true
	_anel.visible = false
	add_child(_anel)


func disparar_pulso() -> void:
	if _pulso < 1.0:
		return
	_pulso = 0.0
	_anel.visible = true
	_anel.scale = Vector3(0.05, 1.0, 0.05)
	_anel.global_position = _posicao_no_chao()


func _animar_pulso(delta: float) -> void:
	if _pulso >= 1.0:
		return
	_pulso = minf(_pulso + delta / maxf(duracao_pulso, 0.05), 1.0)
	var escala := lerpf(0.05, raio_scanner, _pulso)
	_anel.scale = Vector3(escala, 1.0, escala)
	_anel_mat.albedo_color.a = (1.0 - _pulso) * 0.85
	if _pulso >= 1.0:
		_anel.visible = false


func _posicao_no_chao() -> Vector3:
	var espaco := get_world_3d().direct_space_state
	var consulta := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3(0.0, -30.0, 0.0)
	)
	consulta.collide_with_areas = false
	# Ignora o proprio jogador, senao o anel para na cabeca dele.
	if _jogador is CollisionObject3D:
		consulta.exclude = [(_jogador as CollisionObject3D).get_rid()]
	var resultado := espaco.intersect_ray(consulta)
	if resultado.is_empty():
		return global_position
	return (resultado.get("position") as Vector3) + Vector3(0.0, 0.05, 0.0)
