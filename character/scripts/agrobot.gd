extends Node3D
class_name Agrobot

## Agrobot: drone companheiro que flutua acima da cabeca e segue o jogador.
##
## Tudo o que o agrobot precisa esta NESTE script + a cena agrobot.tscn.

@export var velocidade_seguir: float = 25.0         # velocidade de perseguição (m/s) — alta = cola no jogador
@export var tempo_resposta: float = 0.05            # suavidade (s) — 0.05 = praticamente instantâneo, sem lag
@export var suavizar_modelo: bool = true            # suaviza só o modelo visual, não a raiz
## Altura em relacao a origem do jogador (a origem fica ~1 m acima do chao).
## 1.0 deixa o agrobot logo acima da cabeca.
@export var offset_acima: Vector3 = Vector3(0.0, 1.0, 0.0)

var _jogador: Node3D = null
var _ativo := true

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
