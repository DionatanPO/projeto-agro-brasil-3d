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
## Margem interna onde o clamp suave começa a agir (evita tremor na borda).
@export var margem_suave: float = 1.5
## Força do retorno suave (0..1 por frame de física). 0.5 = resposta rápida sem overshoot.
@export var forca_retorno: float = 0.5
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

	# Limites duros (nunca ultrapassa).
	var xmin := limite_min.x
	var xmax := limite_max.x
	var zmin := limite_min.y
	var zmax := limite_max.y

	# Clamp suave na margem interna + clamp duro nos limites absolutos.
	var new_x := p.x
	var new_z := p.z
	var mudou := false

	# Clamp duro primeiro (se já passou do limite absoluto).
	if p.x < xmin:
		new_x = xmin
		mudou = true
	elif p.x > xmax:
		new_x = xmax
		mudou = true
	# Clamp suave na margem interna.
	elif p.x < xmin + margem_suave:
		new_x = lerpf(p.x, xmin + margem_suave, forca_retorno)
		mudou = true
	elif p.x > xmax - margem_suave:
		new_x = lerpf(p.x, xmax - margem_suave, forca_retorno)
		mudou = true

	if p.z < zmin:
		new_z = zmin
		mudou = true
	elif p.z > zmax:
		new_z = zmax
		mudou = true
	elif p.z < zmin + margem_suave:
		new_z = lerpf(p.z, zmin + margem_suave, forca_retorno)
		mudou = true
	elif p.z > zmax - margem_suave:
		new_z = lerpf(p.z, zmax - margem_suave, forca_retorno)
		mudou = true

	if not mudou:
		return

	a.global_position = Vector3(new_x, p.y, new_z)
	var v := a.velocity
	if new_x != p.x:
		v.x = 0.0
	if new_z != p.z:
		v.z = 0.0
	a.velocity = v

	# Veículos: zera o motor para não ficar empurrando a borda.
	if a.get("_vel") != null:
		a.set("_vel", 0.0)
	if a.get("_gas") != null:
		a.set("_gas", 0.0)
