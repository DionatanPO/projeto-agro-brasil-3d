extends Node3D
## Cutscene cinematográfica de introdução do mundo (~22s).
## "Jogo de câmeras": vários shots com cortes entre pontos do cenário
## (parque solar, parque eólico, fazenda) e descida final até o jogador.
## Só roda na primeira vez que o jogador inicia um "Novo Jogo".

class_name IntroCutscene

@onready var camera: Camera3D = $CutsceneCamera
@onready var bars: CanvasLayer = $CinematicBars
@onready var top_bar: ColorRect = $CinematicBars/TopBar
@onready var bottom_bar: ColorRect = $CinematicBars/BottomBar
@onready var fade: ColorRect = $CinematicBars/FadeRect
# Legendas desabilitadas a pedido do usuário.
@onready var skip_hint: Label = $CinematicBars/SkipHint

const FADE_IN := 1.5
const FADE_OUT := 1.2

# Shots: cada um tem duração, posição inicial/final, alvo inicial/final e legenda.
# Primeiros shots: câmera baixa, horizontal, pegando o horizonte.
# Shots finais: visão mais de cima, descendo até o jogador.
const SHOTS := [
	{
		"dur": 6.0,
		"pos0": Vector3(230.0, 42.0, 180.0),
		"pos1": Vector3(200.0, 38.0, 195.0),
		"tgt0": Vector3(150.0, 12.0, 215.0),
		"tgt1": Vector3(135.0, 11.0, 220.0),
	},
	{
		"dur": 5.0,
		"pos0": Vector3(175.0, 42.0, 245.0),
		"pos1": Vector3(145.0, 38.0, 230.0),
		"tgt0": Vector3(124.0, 11.0, 227.0),
		"tgt1": Vector3(110.0, 11.0, 215.0),
	},
	{
		"dur": 4.5,
		"pos0": Vector3(100.0, 40.0, 215.0),
		"pos1": Vector3(82.0, 30.0, 205.0),
		"tgt0": Vector3(80.0, 11.0, 200.0),
		"tgt1": Vector3(76.456, 11.0, 195.0),
	},
	{
		"dur": 4.0,
		"pos0": Vector3(76.456, 30.0, 198.0),
		"pos1": Vector3(76.456, 16.0, 194.0),
		"tgt0": Vector3(76.456, 11.0, 195.0),
		"tgt1": Vector3(76.456, 11.5, 192.678),
	},
]

var DURACAO_TOTAL := 0.0

var _tempo := 0.0
var _pulado := false
var _player: CharacterBody3D
var _player_cam: Camera3D
var _hud: CanvasLayer
var _musica_intro: AudioStreamPlayer

# Estado do shot atual
var _shot_index := 0
var _shot_time := 0.0

func _ready() -> void:
	for s in SHOTS:
		DURACAO_TOTAL += s.dur
	DURACAO_TOTAL += 1.5 # hold final

	if SaveSystem.dados.get("intro_mundo_vista", false):
		queue_free()
		return

	camera.fov = 72.0
	camera.far = 900.0

	# UI inicial
	bars.visible = false
	top_bar.visible = false
	bottom_bar.visible = false
	fade.visible = false
	skip_hint.visible = false

	_player = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if _player != null:
		_player_cam = _player.get("cam") as Camera3D
		_player.set("bloqueado", true)
		_player.set("process_mode", Node.PROCESS_MODE_INHERIT)
		# Garante pose de idle (parado) durante a cutscene
		if _player.has_method("forcar_idle_cutscene"):
			_player.call("forcar_idle_cutscene")
		elif _player.has_method("_atualizar_animacao"):
			_player.call("_atualizar_animacao", "Idle")
	else:
		print("[IntroCutscene] player NAO encontrado")
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud == null and get_tree().current_scene != null:
		_hud = get_tree().current_scene.find_child("HUD", true, false) as CanvasLayer
	if _hud != null:
		_hud.visible = false

	# Som de drone removido da cutscene (apenas música de fundo)

	# Música de intro: toca uma vez, continua após a cutscene
	var musica := load("res://assets/audio/musicas/musica_menu_principal.mp3") as AudioStream
	if musica != null:
		_musica_intro = AudioStreamPlayer.new()
		_musica_intro.stream = musica
		_musica_intro.volume_db = -10.0
		if musica is AudioStreamMP3:
			(musica as AudioStreamMP3).loop = false
		elif musica is AudioStreamWAV:
			(musica as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		if AudioServer.get_bus_index("Musica") >= 0:
			_musica_intro.bus = "Musica"
		elif AudioServer.get_bus_index("Master") >= 0:
			_musica_intro.bus = "Master"
		# Adiciona ao root para persistir após a cutscene ser removida
		get_tree().root.add_child(_musica_intro)

	_iniciar()


func _iniciar() -> void:
	_tempo = 0.0
	_pulado = false
	_shot_index = 0
	_shot_time = 0.0
	var s0 = SHOTS[0]
	camera.global_position = s0.pos0
	camera.look_at(s0.tgt0, Vector3.UP)
	camera.make_current()

	bars.visible = true
	top_bar.visible = true
	bottom_bar.visible = true
	fade.visible = true
	fade.color.a = 1.0
	skip_hint.visible = true

	if _musica_intro != null:
		_musica_intro.play()

	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, FADE_IN)
	tw.set_parallel(true)


func _process(delta: float) -> void:
	if _pulado:
		return

	_tempo += delta

	# Permite skip apenas apos 1s (evita pular pelo clique do menu)
	if _tempo > 1.0 and Input.is_anything_pressed():
		_pular()
		return

	# Avança shot
	if _shot_index < SHOTS.size():
		var s: Dictionary = SHOTS[_shot_index]
		_shot_time += delta
		var t := clampf(_shot_time / float(s.dur), 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t) # smoothstep
		camera.global_position = (s.pos0 as Vector3).lerp(s.pos1 as Vector3, eased)
		var alvo: Vector3 = (s.tgt0 as Vector3).lerp(s.tgt1 as Vector3, eased)
		if camera.global_position.distance_to(alvo) > 0.1:
			camera.look_at(alvo, Vector3.UP)

		if _shot_time >= s.dur:
			_shot_index += 1
			_shot_time = 0.0
			if _shot_index < SHOTS.size():
				# Transição curta (fade) + snap para o próximo shot
				var ns: Dictionary = SHOTS[_shot_index]
				var tw2 := create_tween()
				tw2.tween_property(fade, "color:a", 1.0, 0.18)
				tw2.tween_callback(func():
					camera.global_position = ns.pos0
					camera.look_at(ns.tgt0, Vector3.UP)
				)
				tw2.tween_property(fade, "color:a", 0.0, 0.18)
	else:
		# hold final
		pass

	# Fade out no final
	if _tempo >= DURACAO_TOTAL - FADE_OUT:
		fade.color.a = clampf((_tempo - (DURACAO_TOTAL - FADE_OUT)) / FADE_OUT, 0.0, 1.0)

	if _tempo >= DURACAO_TOTAL:
		_finalizar()


func _pular() -> void:
	_pulado = true
	_tempo = DURACAO_TOTAL
	_finalizar()


func _finalizar() -> void:
	if _player != null:
		_player.set("bloqueado", false)
		_player.set("process_mode", Node.PROCESS_MODE_INHERIT)
		if _player_cam != null:
			_player_cam.make_current()
	if _hud != null:
		_hud.visible = true

	if SaveSystem != null:
		SaveSystem.dados["intro_mundo_vista"] = true
		SaveSystem.salvar()

	queue_free()
