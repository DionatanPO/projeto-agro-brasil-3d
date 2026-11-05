## VisibilityOptimizer: desliga objetos estáticos quando saem da tela,
## economizando processamento de renderização em dispositivos móveis.
##
## Uso: adicione como filho de um MeshInstance3D (ou outro nó estático).
## Quando o nó pai sair da tela, ele é desligado (set_process(false) +
## set_visible(false)). Quando voltar à tela, é reativado.
class_name VisibilityOptimizer

extends Node3D

@export var desativar_fora_da_tela: bool = true
@export var distancia_maxima_visibilidade: float = 300.0  # desliga mesmo se na tela mas muito longe
@export var apenas_desativar_render: bool = true  # se true, só desliga render; se false, queue_free ao sair

var _notificador: VisibleOnScreenNotifier3D
var _pai: Node3D
var _esta_visivel := true
var _posicao_inicial: Vector3

func _ready() -> void:
	_pai = get_parent() as Node3D
	if _pai == null:
		queue_free()
		return

	_posicao_inicial = _pai.global_position

	# Cria o notificador de visibilidade
	_notificador = VisibleOnScreenNotifier3D.new()
	_notificador.screen_entered.connect(_on_entrou_tela)
	_notificador.screen_exited.connect(_on_saiu_tela)
	add_child(_notificador)

	# Estado inicial: visível
	_esta_visivel = true

func _process(_delta: float) -> void:
	if not desativar_fora_da_tela:
		return

	# Se há distância máxima configurada, desliga objetos muito distantes da câmera
	if distancia_maxima_visibilidade > 0.0:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var dist := _pai.global_position.distance_to(camera.global_position)
			if dist > distancia_maxima_visibilidade and _esta_visivel:
				_desativar()
			elif dist <= distancia_maxima_visibilidade and not _esta_visivel:
				_ativar()

func _on_entrou_tela() -> void:
	_ativar()

func _on_saiu_tela() -> void:
	if desativar_fora_da_tela:
		_desativar()

func _ativar() -> void:
	_esta_visivel = true
	if _pai != null:
		_pai.set_visible(true)
		_pai.set_process(true)
		_pai.set_physics_process(true)

func _desativar() -> void:
	_esta_visivel = false
	if _pai != null:
		_pai.set_visible(false)
		_pai.set_process(false)
		_pai.set_physics_process(false)
