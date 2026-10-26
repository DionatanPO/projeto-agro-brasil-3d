extends Node3D
class_name Agrobot

## Agrobot: drone companheiro que flutua acima da cabeca e segue o jogador.
## Q / LT dispara um pulso de scanner (um anel que se expande no chao).
##
## Tudo o que o agrobot precisa esta NESTE script + a cena agrobot.tscn.
## Nao existe mais script separado de scanner.

@export var velocidade_seguir: float = 25.0         # velocidade de perseguição (m/s) — alta = cola no jogador
@export var tempo_resposta: float = 0.05            # suavidade (s) — 0.05 = praticamente instantâneo, sem lag
@export var suavizar_modelo: bool = true            # suaviza só o modelo visual, não a raiz
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

# Referência ao modelo visual (para suavização opcional só no visual).
var _modelo: Node3D = null

# Estado do SmoothDamp para o modelo visual (se suavizar_modelo = true).
var _vel_modelo: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("agrobot")
	_jogador = get_tree().get_first_node_in_group("jogador")
	var mdl := find_child("Modelo")
	_modelo = mdl if mdl else find_child("*")  # pega primeiro filho visual
	if _jogador != null:
		global_position = _jogador.global_position + offset_acima
	_criar_anel()
	# Roda no physics tick junto com o jogador → zero lag de frame.
	set_physics_process(true)
	set_process(false)  # _process não usado para follow


func _physics_process(delta: float) -> void:
	if not _ativo:
		return
	if _jogador == null or not is_instance_valid(_jogador):
		_jogador = get_tree().get_first_node_in_group("jogador")
		if _jogador == null:
			return

	# Posição alvo = posição ATUAL do jogador (mesmo tick de física) + offset.
	var alvo := _jogador.global_position + offset_acima

	# Move a raiz (Node3D) direto para o alvo — sem lag, sem atraso.
	# Se quiser um toque de "flutuação" orgânica, ative suavizar_modelo
	# e o modelo visual fará o SmoothDamp; a raiz segue exato.
	if suavizar_modelo and _modelo != null:
		# Raiz cola no alvo; modelo visual suaviza com mola.
		global_position = alvo
		_suavizar_modelo_visual(delta)
	else:
		# Comportamento clássico: raiz segue com SmoothDamp rápido.
		# Omega alto = resposta quase instantânea.
		var omega := 2.0 / maxf(tempo_resposta, 0.01)
		var x := omega * delta
		var expo := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var dif := global_position - alvo
		# Reutiliza _vel_modelo como velocidade do SmoothDamp da raiz.
		_vel_modelo = (_vel_modelo + dif * omega * delta) * expo
		global_position = alvo + (dif + _vel_modelo * delta) * expo

	# Rotação: copia o yaw do MODELO do jogador + 180°.
	# O Modelo olha para onde o personagem anda; +PI faz o Agrobot
	# olhar para a mesma direção (paisagem), não para o jogador.
	var modelo_jogador := _jogador.get_node_or_null("Modelo") as Node3D
	if modelo_jogador != null:
		rotation.y = lerp_angle(rotation.y, modelo_jogador.rotation.y + PI, 1.0 - exp(-30.0 * delta))

	if Input.is_action_just_pressed("escanear"):
		disparar_pulso()

	_animar_pulso(delta)


func _suavizar_modelo_visual(delta: float) -> void:
	"""Suaviza só o modelo visual (offset local) com mola criticamente amortecida.
	A raiz do Agrobot fica exata na posição do jogador + offset; o modelo
	'flutua' levemente atrás, criando sensação de inércia/flutuação natural."""
	if _modelo == null:
		return
	# Alvo local = origem (0,0,0) pois a raiz já está no alvo mundial.
	var alvo_local := Vector3.ZERO
	var pos_atual := _modelo.position
	var omega := 2.0 / maxf(tempo_resposta, 0.01)
	var x := omega * delta
	var expo := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var dif := pos_atual - alvo_local
	_vel_modelo = (_vel_modelo + dif * omega * delta) * expo
	_modelo.position = alvo_local + (dif + _vel_modelo * delta) * expo
	# Snap quando praticamente parado.
	if pos_atual.length_squared() < 0.0001:
		_modelo.position = Vector3.ZERO
		_vel_modelo = Vector3.ZERO


## Chamado pela AreaEncomenda ao abrir a caixa.
func ativar(posicao_jogador: Vector3) -> void:
	global_position = posicao_jogador + offset_acima
	if _modelo != null:
		_modelo.position = Vector3.ZERO
	_vel_modelo = Vector3.ZERO
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
