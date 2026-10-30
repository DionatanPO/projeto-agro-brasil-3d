extends Node3D
## Limite invisível do mapa para tudo que o jogador controla.
##
## As paredes RioParede* do world.tscn são caixas de 4 m de altura em y=8..12:
## o drone passa por cima e o jogador/trator podem subir a encosta e escapar.
## Aqui o limite é aplicado por script, independente da altura, e vale para
## jogador a pé, trator e drone.

## Canto mínimo do mapa (x, z). O terreno (Terrain3D) vai de 0 a 256; estas
## bordas ficam 2 m para dentro para nunca encostar na beirada do relevo.
@export var limite_min := Vector2(2.0, 2.0)
## Canto máximo do mapa (x, z).
@export var limite_max := Vector2(254.0, 254.0)
## Distância mantida das paredes, para o alvo não raspar nelas.
@export var folga: float = 0.0
## Abaixo desta altura o alvo é considerado no limbo e volta ao último chão.
@export var altura_limbo: float = -30.0
## Grupos dos nós que devem permanecer dentro do mapa.
@export var grupos: PackedStringArray = ["jogador", "trator_jogador", "drone_jogador"]

var _alvos: Array[CharacterBody3D] = []
var _ultimo_chao: Dictionary = {}


func _ready() -> void:
	_atualizar_alvos()


func _atualizar_alvos() -> void:
	_alvos.clear()
	for g in grupos:
		for n in get_tree().get_nodes_in_group(g):
			if n is CharacterBody3D and not _alvos.has(n):
				_alvos.append(n)


func _physics_process(_delta: float) -> void:
	for a in _alvos:
		if not is_instance_valid(a):
			_atualizar_alvos()
			return
		_conter(a)


func _conter(a: CharacterBody3D) -> void:
	var p := a.global_position

	# Rede de segurança: se cair no vazio (abaixo de tudo), volta ao último
	# ponto em que estava apoiado no chão.
	if p.y < altura_limbo:
		var volta: Vector3 = _ultimo_chao.get(a, Vector3(128.0, 40.0, 128.0))
		a.global_position = volta
		a.velocity = Vector3.ZERO
		return
	if a.is_on_floor():
		_ultimo_chao[a] = p

	var xmin := limite_min.x + folga
	var xmax := limite_max.x - folga
	var zmin := limite_min.y + folga
	var zmax := limite_max.y - folga
	var x := clampf(p.x, xmin, xmax)
	var z := clampf(p.z, zmin, zmax)
	var bateu_x := not is_equal_approx(x, p.x)
	var bateu_z := not is_equal_approx(z, p.z)
	if not (bateu_x or bateu_z):
		return

	a.global_position = Vector3(x, p.y, z)
	var v := a.velocity
	if bateu_x:
		v.x = 0.0
	if bateu_z:
		v.z = 0.0
	a.velocity = v

	# Veículos: zera o motor para não ficar empurrando a borda.
	if a.get("_vel") != null:
		a.set("_vel", 0.0)
	if a.get("_gas") != null:
		a.set("_gas", 0.0)
