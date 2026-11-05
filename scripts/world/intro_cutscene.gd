extends Node3D
## Intro cinematográfica local: uma órbita curta ao redor do jogador, sem visitar
## regiões distantes que possam estar descarregadas pelo WorldStreamer.

class_name IntroCutscene

@onready var camera: Camera3D = $CutsceneCamera
@onready var bars: CanvasLayer = $CinematicBars
@onready var top_bar: ColorRect = $CinematicBars/TopBar
@onready var bottom_bar: ColorRect = $CinematicBars/BottomBar
@onready var fade: ColorRect = $CinematicBars/FadeRect
@onready var skip_hint: Label = $CinematicBars/SkipHint

const DURACAO := 10.0
const TEMPO_ORBITA := 8.2
const FADE_IN := 0.8
const RAIO_ORBITA_INICIAL := 6.0
const ALTURA_ORBITA_INICIAL := 3.4
const ALTURA_FOCO := 1.35
const DISTANCIA_FOCO_FINAL := 5.0

var _tempo := 0.0
var _angulo_inicial := 0.0
var _raio_final := 3.0
var _altura_final := 1.8
var _direcao_final := Vector3.FORWARD
var _player: CharacterBody3D
var _player_cam: Camera3D
var _hud: CanvasLayer
var _musica_intro: AudioStreamPlayer
var _fade_tween: Tween
var _finalizando := false


func _ready() -> void:
	if SaveSystem.dados.get("intro_mundo_vista", false):
		queue_free()
		return

	_player = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if _player == null:
		push_warning("[IntroCutscene] Jogador não encontrado; intro cancelada.")
		queue_free()
		return

	# Não existe propriedade 'cam' no script do jogador; usa o caminho real da cena.
	_player_cam = _player.get_node_or_null("CameraRig/BracosCamera/Camera3D") as Camera3D
	if _player_cam == null:
		push_warning("[IntroCutscene] Câmera do jogador não encontrada; intro cancelada.")
		queue_free()
		return

	var offset_camera := _player_cam.global_position - _player.global_position
	var offset_horizontal := Vector2(offset_camera.x, offset_camera.z)
	_raio_final = maxf(offset_horizontal.length(), 0.1)
	_altura_final = offset_camera.y
	if offset_horizontal.length_squared() > 0.001:
		_angulo_inicial = atan2(offset_horizontal.y, offset_horizontal.x)
	_direcao_final = -_player_cam.global_basis.z.normalized()

	_player.set("bloqueado", true)
	_player.set("process_mode", Node.PROCESS_MODE_INHERIT)
	if _player.has_method("forcar_idle_cutscene"):
		_player.call("forcar_idle_cutscene")
	elif _player.has_method("_atualizar_animacao"):
		_player.call("_atualizar_animacao", "Idle")

	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud == null and get_tree().current_scene != null:
		_hud = get_tree().current_scene.find_child("HUD", true, false) as CanvasLayer
	if _hud != null:
		_hud.visible = false

	camera.fov = 58.0
	camera.far = 90.0
	_iniciar_musica()
	_iniciar()


func _iniciar_musica() -> void:
	var musica := load("res://assets/audio/musicas/First_Light_on_the_Rows.mp3") as AudioStream
	if musica == null:
		return

	_musica_intro = AudioStreamPlayer.new()
	_musica_intro.name = "MusicaIntro"
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
	get_tree().root.add_child(_musica_intro)
	_musica_intro.play()


func _iniciar() -> void:
	_tempo = 0.0
	bars.visible = true
	top_bar.visible = true
	bottom_bar.visible = true
	fade.visible = true
	fade.color = Color.BLACK
	skip_hint.visible = true

	_atualizar_camera(0.0)
	camera.make_current()

	# Único fade da sequência: abre a imagem no começo.
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "color:a", 0.0, FADE_IN)
	_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _finalizando:
		return

	_tempo += delta
	if _tempo > FADE_IN and Input.is_anything_pressed():
		_finalizar()
		return

	var progresso := clampf(_tempo / DURACAO, 0.0, 1.0)
	_atualizar_camera(progresso)
	if progresso >= 1.0:
		_finalizar()


func _atualizar_camera(progresso: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_player_cam):
		return

	var alvo_personagem := _player.global_position + Vector3(0.0, ALTURA_FOCO, 0.0)
	var fim_orbita := TEMPO_ORBITA / DURACAO
	var posicao_desejada: Vector3
	var alvo_camera: Vector3

	if progresso <= fim_orbita:
		var t_orbita := clampf(progresso / fim_orbita, 0.0, 1.0)
		var suave := t_orbita * t_orbita * (3.0 - 2.0 * t_orbita)
		var angulo := _angulo_inicial + TAU * suave
		var raio := lerpf(RAIO_ORBITA_INICIAL, _raio_final, suave)
		var altura := lerpf(ALTURA_ORBITA_INICIAL, _altura_final, suave)
		posicao_desejada = _player.global_position + Vector3(
			cos(angulo) * raio,
			altura,
			sin(angulo) * raio
		)
		alvo_camera = alvo_personagem
	else:
		# Aproxima a direção de olhar para coincidir com a câmera de gameplay.
		var t_entrega := clampf((progresso - fim_orbita) / (1.0 - fim_orbita), 0.0, 1.0)
		var suave_entrega := t_entrega * t_entrega * (3.0 - 2.0 * t_entrega)
		posicao_desejada = _player_cam.global_position
		alvo_camera = alvo_personagem.lerp(
			_player_cam.global_position + _direcao_final * DISTANCIA_FOCO_FINAL,
			suave_entrega
		)

	camera.global_position = _evitar_obstaculo(alvo_personagem, posicao_desejada)
	if camera.global_position.distance_to(alvo_camera) > 0.1:
		camera.look_at(alvo_camera, Vector3.UP)


func _evitar_obstaculo(alvo: Vector3, desejada: Vector3) -> Vector3:
	var mundo := get_world_3d()
	if mundo == null:
		return desejada

	var consulta := PhysicsRayQueryParameters3D.create(alvo, desejada, 0xFFFFFFFF)
	consulta.collide_with_areas = false
	if is_instance_valid(_player):
		consulta.exclude = [_player.get_rid()]

	var acerto := mundo.direct_space_state.intersect_ray(consulta)
	if acerto.is_empty():
		return desejada
	return acerto.position + acerto.normal * 0.35


func _finalizar() -> void:
	if _finalizando:
		return
	_finalizando = true

	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()

	# Entrega a câmera sem corte: as duas ficam no mesmo transform no handoff.
	if is_instance_valid(_player_cam):
		camera.global_transform = _player_cam.global_transform
		_player_cam.make_current()

	if is_instance_valid(_player):
		_player.set("bloqueado", false)
		_player.set("process_mode", Node.PROCESS_MODE_INHERIT)
	if is_instance_valid(_hud):
		_hud.visible = true

	if SaveSystem != null:
		SaveSystem.dados["intro_mundo_vista"] = true

	if is_instance_valid(DialogueManager) and DialogueManager.has_method("on_intro_finished"):
		DialogueManager.on_intro_finished()

	# Remove as tarjas junto com esta cena; não há fade/segunda entrada no final.
	queue_free()
