extends CharacterBody3D
## TratorJogador: trator dirigivel em terceira pessoa, reutilizavel.
## Instancie 'res://scenes/world/trator_jogador.tscn' em qualquer cenario ou
## no mundo que ele funciona sozinho (estacao de embarque embutida).
## Segue o padrao do drone (scripts/player/drone_jogador.gd + troca_drone.gd):
## perto a pe -> "E usa o trator"; dirigindo -> "E desce".
## Corpo = trator.glb; rodas = roda_trator.glb (dianteiras menores e estercam,
## traseiras maiores, todas giram conforme a velocidade).
## Audio: motor (som_trator.mp3 em loop) e buzina (buzina_trator.mp3) vem de
## arquivo; o beep de re continua sintetizado em codigo.

const HOME_TRATOR := Vector3(81.0, 11.0, 192.5)  # mesma posição do spawn no world.tscn
const RAIO_ESTACAO := 4.5

@export var velocidade_max := 9.0
@export var velocidade_re := 3.5
@export var aceleracao := 3.5
@export var freio := 7.0
@export var taxa_guinada := 1.6
@export var angulo_max_direcao := 0.55
@export var raio_roda_dianteira := 0.54
@export var raio_roda_traseira := 0.73
@export var roda_lift := 0.0  # Altura extra do body acima do chão ao spawnar (ajuste no Inspector até as rodas tocarem sem afundar)
@export var sensibilidade_mouse := 0.003
@export var sensibilidade_stick := 2.8

const BASE_RIG_Y := PI * 0.5

var gravidade: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var ativo := false

var _vel := 0.0
var _esterco := 0.0
var _gas := 0.0
var _jogador: CharacterBody3D
var _jogador_perto := false
var _prompt: Label3D
var _som_motor: AudioStreamPlayer3D
var _som_buzina: AudioStreamPlayer3D
var _som_re: AudioStreamPlayer3D
var _poeira_roda_te: GPUParticles3D
var _poeira_roda_td: GPUParticles3D
var _fuma_chamine: GPUParticles3D
var _tempo_beep := 0.0
var _angulo_vertical := -0.32

@onready var rig: Node3D = $CameraRig
@onready var bracos: SpringArm3D = $CameraRig/BracosCamera
@onready var cam: Camera3D = $CameraRig/BracosCamera/Camera3D
@onready var modelo: Node3D = $Modelo
@onready var pivo_esq: Node3D = $Modelo/PivoDianteiroEsq
@onready var pivo_dir: Node3D = $Modelo/PivoDianteiroDir
@onready var eixo_de: Node3D = $Modelo/PivoDianteiroEsq/EixoDE
@onready var eixo_dd: Node3D = $Modelo/PivoDianteiroDir/EixoDD
@onready var eixo_te: Node3D = $Modelo/EixoTE
@onready var eixo_td: Node3D = $Modelo/EixoTD
@onready var estacao: Area3D = $Estacao

@onready var SaveSystem := get_node("/root/SaveSystem")


func _ready() -> void:
	add_to_group("trator_jogador")
	_montar_estacao()
	_poeira_roda_te = _criar_poeira_roda("PoeiraRodaTE", Vector3(0.8, 0.15, 1.08))
	_poeira_roda_td = _criar_poeira_roda("PoeiraRodaTD", Vector3(0.8, 0.15, -1.08))
	_fuma_chamine = _criar_fumaca_chamine()
	_som_motor = AudioStreamPlayer3D.new()
	_som_motor.name = "SomMotor"
	# Motor do trator: arquivo real (assets/audio/som_trator.mp3) em loop continuo.
	# A "acelerada/freada" continua sendo simulada por pitch_scale + volume_db
	# no _physics_process. Se o arquivo faltar, volta pro diesel sintetizado.
	var trilha_motor := load("res://assets/audio/trator/som_trator.mp3") as AudioStream
	if trilha_motor == null:
		trilha_motor = _gerar_motor_diesel()
	elif trilha_motor is AudioStreamMP3:
		(trilha_motor as AudioStreamMP3).loop = true
	elif trilha_motor is AudioStreamWAV:
		(trilha_motor as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_som_motor.stream = trilha_motor
	_som_motor.max_distance = 60.0
	_som_motor.volume_db = -60.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_som_motor.bus = "Efeitos"
	add_child(_som_motor)
	_som_buzina = AudioStreamPlayer3D.new()
	_som_buzina.name = "SomBuzina"
	# Buzina: arquivo real (assets/audio/buzina_trator.mp3), toca uma vez por
	# aperto. Se o arquivo faltar, volta pro bip sintetizado.
	var trilha_buzina := load("res://assets/audio/trator/buzina_trator.mp3") as AudioStream
	if trilha_buzina == null:
		trilha_buzina = _gerar_buzina()
	elif trilha_buzina is AudioStreamMP3:
		(trilha_buzina as AudioStreamMP3).loop = false
	_som_buzina.stream = trilha_buzina
	# Um pouco acima do nivel do arquivo pra ficar no mesmo volume da buzina
	# sintetizada que ela substitui (o mp3 tem pico em -10.7 dBFS).
	_som_buzina.volume_db = 5.0
	_som_buzina.max_distance = 80.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_som_buzina.bus = "Efeitos"
	add_child(_som_buzina)
	_som_re = AudioStreamPlayer3D.new()
	_som_re.name = "SomRe"
	_som_re.stream = _gerar_beep_re()
	_som_re.max_distance = 40.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_som_re.bus = "Efeitos"
	add_child(_som_re)
	# FORÇA posição da cena no primeiro jogo - ignora save se Y inválido
	var cena_pos := position  # Posição definida no world.tscn (81.0, 11.0, 192.5)
	
	# Só carrega save se existir E Y > 5 (não no vazio)
	if SaveSystem.tem_save():
		var pos: Variant = SaveSystem.dados.get("posicao_trator")
		if pos is Array and (pos as Array).size() == 3:
			var saved_y := float(pos[1])
			if saved_y > 5.0:
				position = Vector3(float(pos[0]), saved_y, float(pos[2]))
			else:
				position = cena_pos
		else:
			position = cena_pos
	else:
		position = cena_pos
	
	print("TRATOR SPAWN POS: ", position)
	
	cam.current = false
	_jogador = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if str(SaveSystem.dados.get("veiculo", "jogador")) == "trator":
		_entrar(true)


func _verificar_queda_vazio() -> void:
	# Proteção: se cair abaixo de -50 (limbo), respawn no HOME
	if position.y < -50.0:
		print("TRATOR CAIU NO VAZIO -> RESPAWN")
		position = HOME_TRATOR
		velocity = Vector3.ZERO
		_vel = 0.0


func _montar_estacao() -> void:
	estacao.collision_layer = 0
	estacao.collision_mask = 1
	var col := CollisionShape3D.new()
	col.name = "Raio"
	var esf := SphereShape3D.new()
	esf.radius = RAIO_ESTACAO
	col.shape = esf
	estacao.add_child(col)
	_prompt = Label3D.new()
	_prompt.name = "Aviso"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.position = Vector3(0, 3.6, 0)
	_prompt.font_size = 64
	_prompt.text = "Pressione E para usar o trator"
	_prompt.visible = false
	add_child(_prompt)
	estacao.body_entered.connect(_on_corpo_entrou)
	estacao.body_exited.connect(_on_corpo_saiu)


func _on_corpo_entrou(corpo: Node3D) -> void:
	if ativo or _jogador_perto:
		return
	if corpo.is_in_group("jogador"):
		_jogador = corpo as CharacterBody3D
		_jogador_perto = true
		_prompt.text = "Pressione E para usar o trator"
		_prompt.visible = true


func _on_corpo_saiu(corpo: Node3D) -> void:
	if corpo.is_in_group("jogador"):
		_jogador_perto = false
		_prompt.visible = false


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventScreenDrag and ativo and Dispositivo.movel():
		var arrasto := evento as InputEventScreenDrag
		_olhar(
			-arrasto.relative.x * sensibilidade_mouse * 1.4,
			-arrasto.relative.y * sensibilidade_mouse * 1.4
		)
		return
	if evento is InputEventMouseMotion and ativo and not Dispositivo.movel() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_olhar(-(evento as InputEventMouseMotion).relative.x * sensibilidade_mouse, -(evento as InputEventMouseMotion).relative.y * sensibilidade_mouse)
	if evento is InputEventMouseButton and (evento as InputEventMouseButton).pressed:
		if ativo and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if evento.is_action_pressed("interagir"):
		if ativo:
			_sair()
			get_viewport().set_input_as_handled()
		elif _jogador != null and _jogador.visible and global_position.distance_to(_jogador.global_position) < RAIO_ESTACAO + 2.0:
			_entrar(false)
			get_viewport().set_input_as_handled()
	if ativo and evento.is_action_pressed("buzinar"):
		if not _som_buzina.playing:
			_som_buzina.play()


func _physics_process(delta: float) -> void:
	_verificar_queda_vazio()

	if ativo:
		_gas = Input.get_axis("mover_tras", "mover_frente")
		var comando_dir := Input.get_axis("mover_dir", "mover_esq")
		_esterco = lerpf(
			_esterco,
			comando_dir,
			1.0 - exp(-8.0 * delta)
		)

		var alvo := 0.0
		if _gas > 0.05:
			alvo = _gas * velocidade_max
		elif _gas < -0.05:
			alvo = _gas * velocidade_re

		var taxa := aceleracao if absf(alvo) > absf(_vel) else freio
		_vel = move_toward(_vel, alvo, taxa * delta)

		if absf(_vel) > 0.05:
			rotate_object_local(
				Vector3.UP,
				_esterco
				* taxa_guinada
				* clampf(absf(_vel) / 3.0, 0.0, 1.0)
				* signf(_vel)
				* delta
			)

		var frente_plana := -global_transform.basis.x
		var frente_chao := (
			frente_plana
			- Vector3.UP * frente_plana.dot(Vector3.UP)
		).normalized()

		velocity.x = frente_chao.x * _vel
		velocity.z = frente_chao.z * _vel

		SaveSystem.dados["posicao_trator"] = [
			position.x,
			position.y,
			position.z
		]
	else:
		_vel = move_toward(_vel, 0.0, freio * delta)
		_esterco = lerpf(_esterco, 0.0, 1.0 - exp(-6.0 * delta))
		velocity.x = move_toward(velocity.x, 0.0, freio * delta)
		velocity.z = move_toward(velocity.z, 0.0, freio * delta)
		_sincronizar_proximidade()

		# Para completamente quando inativo e no chão, para não deslizar em declives.
		if is_on_floor():
			velocity = Vector3.ZERO

	# Gravidade simples (igual ao jogador)
	if not is_on_floor():
		velocity.y -= gravidade * delta

	move_and_slide()

	var levantar_poeira := ativo and absf(_vel) > 1.0 and is_on_floor()

	if _poeira_roda_te:
		_poeira_roda_te.emitting = levantar_poeira

	if _poeira_roda_td:
		_poeira_roda_td.emitting = levantar_poeira


## Alinha o corpo e as rodas do trator com a inclinação real do relevo
func _adaptar_inclinacao_terreno(delta: float) -> void:
	if not is_on_floor():
		return

	var n := get_floor_normal()
	if n.length_squared() <= 0.01:
		return

	# Converte a normal do mundo para o espaço do trator
	var normal_local := global_transform.basis.inverse() * n

	# No trator: pitch em Z, roll em X
	var pitch_alvo := clampf(-normal_local.x, -0.80, 0.80)
	var roll_alvo := clampf(normal_local.z, -0.70, 0.70)

	var suavidade := 1.0 - exp(-14.0 * delta)
	if modelo != null:
		modelo.rotation.z = lerpf(modelo.rotation.z, pitch_alvo, suavidade)
		modelo.rotation.x = lerpf(modelo.rotation.x, roll_alvo, suavidade)


func _criar_poeira_roda(nome: String, posicao: Vector3) -> GPUParticles3D:
	var poeira := GPUParticles3D.new()
	poeira.name = nome
	poeira.position = posicao
	poeira.amount = 90
	poeira.lifetime = 0.9
	poeira.explosiveness = 0.0
	poeira.emitting = false
	poeira.visibility_aabb = AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 12.0, 40.0))

	var processo := ParticleProcessMaterial.new()
	processo.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	processo.emission_sphere_radius = 0.16
	processo.direction = Vector3(1.0, 0.25, 0.0)
	processo.spread = 35.0
	processo.initial_velocity_min = 0.4
	processo.initial_velocity_max = 1.5
	processo.gravity = Vector3(0.0, 0.45, 0.0)
	processo.damping_min = 0.25
	processo.damping_max = 0.55
	processo.scale_min = 0.65
	processo.scale_max = 1.35
	processo.color = Color(0.62, 0.48, 0.3, 0.62)
	var curva_alpha := Curve.new()
	curva_alpha.add_point(Vector2(0.0, 0.0))
	curva_alpha.add_point(Vector2(0.15, 1.0))
	curva_alpha.add_point(Vector2(1.0, 0.0))
	var textura_alpha := CurveTexture.new()
	textura_alpha.curve = curva_alpha
	processo.alpha_curve = textura_alpha
	poeira.process_material = processo

	var malha := SphereMesh.new()
	malha.radius = 0.12
	malha.height = 0.24
	var visual := StandardMaterial3D.new()
	visual.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	visual.albedo_color = Color(0.62, 0.48, 0.3, 0.5)
	malha.material = visual
	poeira.draw_pass_1 = malha
	modelo.add_child(poeira)
	return poeira


func _criar_fumaca_chamine() -> GPUParticles3D:
	var fumaca := GPUParticles3D.new()
	fumaca.name = "FumacaChamine"
	# Frente do trator (eixo -X), logo acima do capo. Lado direito = -Z.
	fumaca.position = Vector3(-0.65, 2.50, -0.50)
	fumaca.amount = 32
	fumaca.lifetime = 0.6
	fumaca.explosiveness = 0.0
	fumaca.emitting = false
	fumaca.local_coords = false
	fumaca.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 9.0, 8.0))

	var processo := ParticleProcessMaterial.new()
	processo.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	processo.emission_sphere_radius = 0.03
	processo.direction = Vector3(0.0, 1.0, 0.0)
	processo.spread = 4.0
	processo.initial_velocity_min = 0.35
	processo.initial_velocity_max = 0.8
	processo.gravity = Vector3(0.0, 0.35, 0.0)
	processo.damping_min = 0.05
	processo.damping_max = 0.2
	processo.scale_min = 0.8
	processo.scale_max = 1.2
	var curva_scale := Curve.new()
	curva_scale.add_point(Vector2(0.0, 1.5))
	curva_scale.add_point(Vector2(1.0, 0.1))
	var textura_scale := CurveTexture.new()
	textura_scale.curve = curva_scale
	processo.scale_curve = textura_scale
	processo.color = Color(0.48, 0.47, 0.45, 1.0)
	var curva_alpha := Curve.new()
	curva_alpha.add_point(Vector2(0.0, 0.0))
	curva_alpha.add_point(Vector2(0.1, 0.02))
	curva_alpha.add_point(Vector2(1.0, 0.0))
	var textura_alpha := CurveTexture.new()
	textura_alpha.curve = curva_alpha
	processo.alpha_curve = textura_alpha
	fumaca.process_material = processo

	var malha := SphereMesh.new()
	malha.radius = 0.055
	malha.height = 0.11
	var visual := StandardMaterial3D.new()
	visual.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	visual.albedo_color = Color(0.48, 0.47, 0.45, 1.0)
	malha.material = visual
	fumaca.draw_pass_1 = malha
	modelo.add_child(fumaca)
	return fumaca


## Redundancia por distancia: mostra o prompt mesmo se o sinal da Area falhar.
func _sincronizar_proximidade() -> void:
	if ativo:
		return
	if _jogador == null or not is_instance_valid(_jogador):
		_jogador = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if _jogador == null or not _jogador.visible:
		_prompt.visible = false
		return
	if _jogador_perto:
		return
	if global_position.distance_to(_jogador.global_position) < RAIO_ESTACAO + 2.0:
		_on_corpo_entrou(_jogador)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not ativo and _jogador != null and is_instance_valid(_jogador):
		_prompt.text = "Pressione E para usar o trator (%.1f m)" % global_position.distance_to(_jogador.global_position)
		if _jogador.visible:
			var perto := global_position.distance_to(_jogador.global_position) < RAIO_ESTACAO + 2.0
			if perto and not _jogador_perto:
				_on_corpo_entrou(_jogador)
			elif not perto and _jogador_perto and estacao.get_overlapping_bodies().is_empty():
				_jogador_perto = false
				_prompt.visible = false
	if not ativo:
		return
	_olhar_stick(delta)
	# Direcao: dianteiras estercam, todas giram conforme a velocidade.
	pivo_esq.rotation.y = _esterco * angulo_max_direcao
	pivo_dir.rotation.y = _esterco * angulo_max_direcao
	var rot_diant := - (_vel / raio_roda_dianteira) * delta
	var rot_tras := - (_vel / raio_roda_traseira) * delta
	eixo_de.rotate_z(rot_diant)
	eixo_dd.rotate_z(rot_diant)
	eixo_te.rotate_z(rot_tras)
	eixo_td.rotate_z(rot_tras)
	# Motor diesel acompanha o esforco.
	var eff := clampf(absf(_vel) / velocidade_max * 0.7 + absf(_gas) * 0.3, 0.0, 1.0)
	if not _som_motor.playing:
		_som_motor.play()
	_som_motor.pitch_scale = 0.75 + 0.9 * eff
	_som_motor.volume_db = lerpf(-18.0, -6.0, eff)
	# Beep de marcha a re.
	if _vel < -0.5:
		_tempo_beep -= delta
		if _tempo_beep <= 0.0:
			_som_re.play()
			_tempo_beep = 0.7
	else:
		_tempo_beep = 0.0


func _olhar(dx: float, dy: float) -> void:
	rig.rotate_y(dx)
	_angulo_vertical = clampf(_angulo_vertical + dy, -1.1, 0.5)
	bracos.rotation.x = _angulo_vertical


func _olhar_stick(delta: float) -> void:
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if joy.length() < 0.2:
		return
	_olhar(-joy.x * sensibilidade_stick * delta, -joy.y * sensibilidade_stick * delta * 0.75)


func _set_jogador(ativo_jogador: bool) -> void:
	if _jogador == null:
		_jogador = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if _jogador == null:
		return
	_jogador.set_physics_process(ativo_jogador)
	_jogador.set_process_unhandled_input(ativo_jogador)
	_jogador.visible = ativo_jogador
	var cam_j := _jogador.get_node_or_null("CameraRig/BracosCamera/Camera3D") as Camera3D
	if cam_j != null:
		cam_j.current = ativo_jogador
	var col := _jogador.get_node_or_null("Colisao") as CollisionShape3D
	if col != null:
		(col as CollisionShape3D).set_deferred("disabled", not ativo_jogador)


func _entrar(silencioso: bool) -> void:
	_set_jogador(false)
	ativo = true
	if _fuma_chamine:
		_fuma_chamine.emitting = true
	rig.rotation.y = BASE_RIG_Y
	cam.current = true
	_prompt.visible = false
	_jogador_perto = false
	if not silencioso:
		SaveSystem.dados["veiculo"] = "trator"
		SaveSystem.salvar()


func _sair() -> void:
	if _jogador == null:
		_jogador = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if _jogador != null:
		_jogador.position = global_position + global_transform.basis.z * 2.8 + Vector3(0, 1.0, 0)
		_jogador.velocity = Vector3.ZERO
	_set_jogador(true)
	ativo = false
	if _fuma_chamine:
		_fuma_chamine.emitting = false
	_vel = 0.0
	cam.current = false
	if _som_motor.playing:
		_som_motor.stop()
	SaveSystem.dados["veiculo"] = "jogador"
	SaveSystem.salvar()


## Diesel 4 tempos: serra grave 55 Hz + harmonicos, pulsacao de 13 Hz e
## ruido de escape. Loop perfeito de 1 s (frequencias inteiras em Hz).
func _gerar_motor_diesel() -> AudioStreamWAV:
	var taxa := 22050
	var n := taxa
	var dados := PackedByteArray()
	dados.resize(n * 2)
	for i in n:
		var t := float(i) / float(taxa)
		var base := 0.34 * _serra(55.0, t) + 0.24 * _serra(110.0, t) + 0.14 * _serra(165.0, t) + 0.10 * _serra(220.0, t)
		var pulso := 0.65 + 0.35 * sin(TAU * 26.0 * t)
		var ar := 0.05 * (sin(TAU * 1244.0 * t) + 0.5 * sin(TAU * 1866.0 * t))
		var x := clampf(base * pulso * 0.7 + ar, -1.0, 1.0)
		dados.encode_s16(i * 2, int(x * 32760.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = taxa
	wav.stereo = false
	wav.data = dados
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


## Buzina: bip curto e agudo (0.25 s, serras em 880 + 1174 Hz).
func _gerar_buzina() -> AudioStreamWAV:
	var taxa := 22050
	var n := int(taxa * 0.25)
	var dados := PackedByteArray()
	dados.resize(n * 2)
	for i in n:
		var f := float(i) / float(n)
		var t := float(i) / float(taxa)
		var env := minf(f * 12.0, 1.0) * minf((1.0 - f) * 8.0, 1.0)
		var x := (0.4 * _serra(880.0, t) + 0.4 * _serra(1174.0, t)) * env * 0.6
		dados.encode_s16(i * 2, int(clampf(x, -1.0, 1.0) * 32760.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = taxa
	wav.stereo = false
	wav.data = dados
	return wav


## Beep de re: seno 880 Hz com 0.25 s e bordas suavizadas.
func _gerar_beep_re() -> AudioStreamWAV:
	var taxa := 22050
	var n := int(taxa * 0.25)
	var dados := PackedByteArray()
	dados.resize(n * 2)
	for i in n:
		var f := float(i) / float(n)
		var env := minf(f * 10.0, 1.0) * minf((1.0 - f) * 10.0, 1.0)
		var x := sin(TAU * 880.0 * float(i) / float(taxa)) * env * 0.5
		dados.encode_s16(i * 2, int(x * 32760.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = taxa
	wav.stereo = false
	wav.data = dados
	return wav


func _serra(freq: float, t: float) -> float:
	return fmod(freq * t, 1.0) * 2.0 - 1.0
