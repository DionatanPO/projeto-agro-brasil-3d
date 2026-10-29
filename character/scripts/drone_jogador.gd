extends CharacterBody3D
## DroneJogador: drone agricola voador em terceira pessoa.
## Usa o corpo de drone_agricola.glb + 4 helices de elice_drone.glb
## posicionadas nos motores, girando em _process (sentidos alternados).
## Controles: WASD move (relativo a camera), Espaco sobe, C/Ctrl desce,
## Shift turbo, mouse olha (clique captura, Esc solta).

@export var velocidade_voo := 8.0
@export var velocidade_turbo := 16.0
@export var velocidade_vertical := 6.0
@export var aceleracao := 6.0
@export var altura_min := 0.0
@export var altura_max := 80.0
const FOG_ALTURA_INICIO := 25.0
const FOG_INICIO_MIN := 8.0
const FOG_FIM_MIN := 70.0
var _env: Environment
var _fog_ini_base := 20.0
var _fog_fim_base := 150.0
@export var helice_base := 20.0
@export var helice_cheia := 55.0
@export var sensibilidade_mouse := 0.003
@export var sensibilidade_stick := 2.8
@export var ligado := true
## Modo usado pela cena do tutorial: nao permite sair nem abrir outro tutorial.
@export var modo_tutorial := false
@export var fov_base := 70.0
@export var fov_turbo := 86.0
@export var tremor_max := 0.012
@export var vinheta_max := 0.45

var gravidade: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spool := 1.0

@onready var rig: Node3D = $CameraRig
@onready var cam: Camera3D = $CameraRig/Camera3D
@onready var modelo: Node3D = $Modelo
@onready var spray: GPUParticles3D = $Modelo/Pulverizador
@onready var SaveSystem := get_node_or_null("/root/SaveSystem")

var _helices: Array[Node3D] = []
var _dirs := [1.0, -1.0, -1.0, 1.0]
var _giro := 0.0
var _acelerador := 0.35
var _som: AudioStreamPlayer3D
var _angulo_vertical := -0.275
var _cam_base := Vector3(0.0, 1.9, 3.85)
var _vinheta_camada: CanvasLayer
var _vinheta: TextureRect
var _vento: AudioStreamPlayer3D
var _tremor_suave := 0.0

signal pulverizando(posicao: Vector3)

const HOME_DRONE := Vector3(69.664, 11.197, 192.916)  # agrupamento da fazenda
const RAIO_ESTACAO := 4.5

## Nível mínimo do jogador para poder pilotar o drone agrícola.
@export var nivel_necessario: int = 3

var _jogador: CharacterBody3D
var _jogador_perto := false
var _prompt: Label3D
var _xp_manager: Node
@onready var estacao: Area3D = $Estacao

const POSICOES := [
	Vector3(1.803, 3.05, 1.803),
	Vector3(1.803, 3.05, -1.803),
	Vector3(-1.803, 3.05, 1.803),
	Vector3(-1.803, 3.05, -1.803),
]


func _pode_usar_drone() -> bool:
	"""Só libera o drone quando o jogador atingir o nível necessário."""
	var xm: Variant = get_node_or_null("/root/XPManager")
	if xm == null:
		return false
	return int(xm.get_level()) >= nivel_necessario

func _ready() -> void:
	add_to_group("drone_jogador")
	_montar_estacao()
	for i in range(1, 5):
		_helices.append(modelo.get_node("Helice%02d" % i) as Node3D)
	cam.position = Vector3(0.0, 1.9, 3.85)
	cam.rotation = Vector3(_angulo_vertical, 0.0, 0.0)

	var cena_pos := position
	if not modo_tutorial and SaveSystem != null and SaveSystem.tem_save():
		var pos: Variant = SaveSystem.dados.get("posicao_drone")
		if pos is Array and (pos as Array).size() == 3:
			var px := float(pos[0])
			var py := float(pos[1])
			var pz := float(pos[2])
			if px > 50.0 and pz > 50.0 and py > 5.0:
				position = Vector3(px, py, pz)
			else:
				position = cena_pos
		else:
			position = cena_pos
	else:
		position = cena_pos

	print("DRONE SPAWN POS: ", position)

	modelo.rotation.y = PI * 0.5
	_som = AudioStreamPlayer3D.new()
	_som.name = "SomMotor"
	var trilha_zumbido := load("res://assets/audio/som_drone_loop.mp3") as AudioStream
	if trilha_zumbido == null:
		trilha_zumbido = _gerar_zumbido()
	elif trilha_zumbido is AudioStreamMP3:
		(trilha_zumbido as AudioStreamMP3).loop = true
	elif trilha_zumbido is AudioStreamWAV:
		(trilha_zumbido as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_som.stream = trilha_zumbido
	_som.volume_db = -30.0
	_som.max_distance = 80.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_som.bus = "Efeitos"
	add_child(_som)
	_construir_vinheta()
	_vento = AudioStreamPlayer3D.new()
	_vento.name = "SomVento"
	_vento.stream = _gerar_vento()
	_vento.volume_db = -48.0
	_vento.max_distance = 120.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_vento.bus = "Efeitos"
	add_child(_vento)

	cam.current = false
	ligado = false
	_spool = 0.0
	_jogador = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	# Só entra automaticamente se já tiver o nível exigido.
	if not modo_tutorial and SaveSystem != null and str(SaveSystem.dados.get("veiculo", "jogador")) == "drone" and _pode_usar_drone():
		_entrar(true)


func _montar_estacao() -> void:
	if estacao == null:
		estacao = Area3D.new()
		estacao.name = "Estacao"
		add_child(estacao)
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
	_prompt.position = Vector3(0, 2.5, 0)
	_prompt.font_size = 64
	_prompt.text = "Pressione E para pilotar o drone  •  T tutorial"
	_prompt.visible = false
	add_child(_prompt)
	estacao.body_entered.connect(_on_corpo_entrou)
	estacao.body_exited.connect(_on_corpo_saiu)


func _on_corpo_entrou(corpo: Node3D) -> void:
	if ligado or _jogador_perto:
		return
	if corpo.is_in_group("jogador"):
		_jogador = corpo as CharacterBody3D
		_jogador_perto = true
		if _pode_usar_drone():
			_prompt.text = "Pressione E para pilotar o drone  •  T tutorial"
		else:
			_prompt.text = "Drone bloqueado: nível %d necessário" % nivel_necessario
		_prompt.visible = true


func _on_corpo_saiu(corpo: Node3D) -> void:
	if corpo.is_in_group("jogador"):
		_jogador_perto = false
		_prompt.visible = false


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventScreenDrag and Dispositivo.movel() and ligado:
		var arrasto := evento as InputEventScreenDrag
		_olhar(
			-arrasto.relative.x * sensibilidade_mouse * 1.4,
			-arrasto.relative.y * sensibilidade_mouse * 1.4
		)
		return
	if evento is InputEventMouseMotion and not Dispositivo.movel() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and ligado:
		_olhar(-(evento as InputEventMouseMotion).relative.x * sensibilidade_mouse, -(evento as InputEventMouseMotion).relative.y * sensibilidade_mouse)
	if evento is InputEventMouseButton and (evento as InputEventMouseButton).pressed:
		if ligado and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if modo_tutorial:
		return
	if evento.is_action_pressed("tutorial_drone"):
		if not ligado and _jogador != null and _jogador.visible and global_position.distance_to(_jogador.global_position) < RAIO_ESTACAO + 2.0:
			get_viewport().set_input_as_handled()
			_abrir_tutorial()
		return
	if evento.is_action_pressed("interagir"):
		if ligado:
			_sair()
			get_viewport().set_input_as_handled()
		elif _jogador != null and _jogador.visible and global_position.distance_to(_jogador.global_position) < RAIO_ESTACAO + 2.0 and _pode_usar_drone():
			_entrar(false)
			get_viewport().set_input_as_handled()


## Abre o tutorial pelo atalho T, perto do drone e a pe.
## Guarda as posicoes atuais para o mapa continuar de onde parou.
func _abrir_tutorial() -> void:
	if SaveSystem != null:
		SaveSystem.dados["posicao_drone"] = [global_position.x, global_position.y, global_position.z]
		SaveSystem.salvar()
	get_tree().change_scene_to_file("res://scenes/world/tutorial_drone.tscn")


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
	ligado = true
	cam.current = true
	_prompt.visible = false
	_jogador_perto = false
	if _som and not _som.playing:
		_som.play()
	if _vento and not _vento.playing:
		_vento.play()
	if not silencioso and SaveSystem != null:
		SaveSystem.dados["veiculo"] = "drone"
		SaveSystem.salvar()
	# Registra descoberta para a missão 4 (pegar o drone)
	if is_instance_valid(Jogo):
		Jogo.registrar_descoberta("drone_agricola")


func _sair() -> void:
	if _jogador == null:
		_jogador = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if _jogador != null:
		_jogador.position = global_position + Vector3(1.5, 0.5, 0.0)
		_jogador.velocity = Vector3.ZERO
	_set_jogador(true)
	ligado = false
	velocity = Vector3.ZERO
	cam.current = false
	if _som and _som.playing:
		_som.stop()
	if _vento and _vento.playing:
		_vento.stop()
	if SaveSystem != null:
		SaveSystem.dados["veiculo"] = "jogador"
		SaveSystem.salvar()


func _avisar_pulverizacao(posicao: Vector3) -> void:
	"""Emite sinal para a área de plantio saber que o drone está pulverizando nesta posição."""
	pulverizando.emit(posicao)


func _physics_process(delta: float) -> void:
	if position.y < -50.0:
		position = HOME_DRONE
		velocity = Vector3.ZERO

	if not ligado:
		if not is_on_floor():
			velocity.y -= gravidade * delta
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		modelo.rotation.x = lerpf(modelo.rotation.x, 0.0, 1.0 - exp(-4.0 * delta))
		modelo.rotation.z = lerpf(modelo.rotation.z, 0.0, 1.0 - exp(-4.0 * delta))
		return
	var entrada := Vector2(
		Input.get_axis("mover_esq", "mover_dir"),
		Input.get_axis("mover_frente", "mover_tras")
	)
	var vertical := Input.get_axis("descer", "pular")
	var turbo := Input.is_action_pressed("correr")
	var vel_max := velocidade_turbo if turbo else velocidade_voo
	var base := rig.global_transform.basis
	var direcao: Vector3 = base * Vector3(entrada.x, 0.0, entrada.y)
	direcao.y = 0.0
	var alvo := Vector3.ZERO
	if direcao.length() > 0.01:
		alvo = direcao.normalized() * vel_max * minf(entrada.length(), 1.0)
	alvo.y = vertical * velocidade_vertical
	velocity = velocity.lerp(alvo, 1.0 - exp(-aceleracao * delta))
	move_and_slide()
	position.y = clampf(position.y, altura_min, altura_max)
	if Vector2(velocity.x, velocity.z).length() > 0.5:
		# Yaw no espaco local do corpo: o corpo pode nascer girado
		# (ex.: -90° no galpao); usar a velocidade global direto aqui
		# aponta o modelo 90° errado e faz ele "girar" ao voar.
		var dir_local: Vector3 = global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		var alvo_yaw := atan2(-dir_local.z, dir_local.x)
		modelo.rotation.y = lerp_angle(modelo.rotation.y, alvo_yaw, 1.0 - exp(-6.0 * delta))
	# A frente do modelo e +X: arfagem (pitch) e rotation.z, rolagem e rotation.x.
	modelo.rotation.z = lerpf(modelo.rotation.z, entrada.y * 0.15, 1.0 - exp(-6.0 * delta))
	modelo.rotation.x = lerpf(modelo.rotation.x, entrada.x * 0.15, 1.0 - exp(-6.0 * delta))
	SaveSystem.dados["posicao_drone"] = [position.x, position.y, position.z]


## Motor desligado: sem comando, gravidade puxa ate pousar e o modelo nivela.
func _descer_desligado(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-3.0 * delta))
	velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-3.0 * delta))
	velocity.y -= gravidade * delta
	move_and_slide()
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
	position.y = clampf(position.y, 0.0, altura_max)
	modelo.rotation.x = lerpf(modelo.rotation.x, 0.0, 1.0 - exp(-4.0 * delta))
	modelo.rotation.z = lerpf(modelo.rotation.z, 0.0, 1.0 - exp(-4.0 * delta))


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not modo_tutorial and not ligado and _jogador != null and is_instance_valid(_jogador) and _prompt != null:
		if _pode_usar_drone():
			_prompt.text = "Pressione E para pilotar o drone (%.1f m)  •  T tutorial" % global_position.distance_to(_jogador.global_position)
			if _jogador.visible:
				var perto := global_position.distance_to(_jogador.global_position) < RAIO_ESTACAO + 2.0
				if perto and not _jogador_perto:
					_on_corpo_entrou(_jogador)
				elif not perto and _jogador_perto and estacao != null and estacao.get_overlapping_bodies().is_empty():
					_jogador_perto = false
					_prompt.visible = false
		else:
			_prompt.text = "Drone bloqueado: nível %d necessário" % nivel_necessario
			if _jogador.visible:
				var perto := global_position.distance_to(_jogador.global_position) < RAIO_ESTACAO + 2.0
				if perto and not _jogador_perto:
					_jogador_perto = true
					_prompt.visible = true
				elif not perto and _jogador_perto:
					_jogador_perto = false
					_prompt.visible = false
	_olhar_stick(delta)
	spray.emitting = ligado and Input.is_action_pressed("pulverizar")
	_efeitos_velocidade(delta)
	_neblina_altura()
	var acelerador := clampf(0.35 + 0.65 * clampf(Vector2(velocity.x, velocity.z).length() / velocidade_turbo + velocity.y / velocidade_vertical, -1.0, 1.0), 0.0, 1.0)
	_acelerador = acelerador
	# Spool do motor: sobe/desce suave ao ligar/desligar.
	_spool = move_toward(_spool, 1.0 if ligado else 0.0, delta * 0.7)
	if ligado and not _som.playing:
		_som.play()
	elif not ligado and _spool <= 0.02 and _som.playing:
		_som.stop()
	if not ligado and _spool <= 0.02 and _vento.playing:
		_vento.stop()
	_giro = lerpf(_giro, _spool * lerpf(helice_base, helice_cheia, acelerador), 1.0 - exp(-3.0 * delta))
	for i in _helices.size():
		_helices[i].rotate_y(_dirs[i] * _giro * delta)
	if _som != null and _som.playing:
		var eff := _acelerador * _spool
		_som.pitch_scale = 0.5 + 0.7 * eff
		_som.volume_db = lerpf(-30.0, -8.0, eff)
	# Se está pulverizando, avisa a área de plantio (para missão 4)
	if ligado and spray.emitting:
		_avisar_pulverizacao(global_position)


func _olhar(dx: float, dy: float) -> void:
	rig.rotate_y(dx)
	_angulo_vertical = clampf(_angulo_vertical + dy, -1.1, 0.5)
	cam.rotation.x = _angulo_vertical


func _olhar_stick(delta: float) -> void:
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if joy.length() < 0.2:
		return
	_olhar(-joy.x * sensibilidade_stick * delta, -joy.y * sensibilidade_stick * delta * 0.75)


## Sintetiza 1 s de zumbido de motor (loop perfeito: todas as
## frequencias sao inteiras em Hz) e devolve como WAV em 16 bits.
func _gerar_zumbido() -> AudioStreamWAV:
	var taxa := 22050
	var n := taxa
	var dados := PackedByteArray()
	dados.resize(n * 2)
	# Passa-altas duplo (12 dB/oitava) em ~280 Hz: corta o grave do motor.
	var rc := 1.0 / (TAU * 280.0)
	var dt := 1.0 / float(taxa)
	var a := rc / (rc + dt)
	var y1_ant := 0.0
	var x_ant := 0.0
	var y2_ant := 0.0
	var y1_ant2 := 0.0
	for i in n:
		var t := float(i) / float(taxa)
		# Fundamental 78 -> 104 Hz; presenca aguda em 2-4 kHz.
		var base := 0.20 * _serra(104.0, t) + 0.28 * _serra(208.0, t) + 0.24 * _serra(312.0, t) + 0.14 * _serra(2080.0, t) + 0.10 * _serra(3120.0, t) + 0.06 * _serra(4160.0, t)
		var pas := 0.70 + 0.30 * sin(TAU * 29.0 * t)
		var ar := 0.025 * (sin(TAU * 1567.0 * t) + 0.6 * sin(TAU * 2093.0 * t))
		var x := clampf(base * pas * 0.8 + ar, -1.0, 1.0)
		var y1 := a * (y1_ant + x - x_ant)
		var y2 := a * (y2_ant + y1 - y1_ant2)
		y1_ant = y1
		x_ant = x
		y2_ant = y2
		y1_ant2 = y1
		dados.encode_s16(i * 2, int(clampf(y2 * 1.5, -1.0, 1.0) * 32760.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = taxa
	wav.stereo = false
	wav.data = dados
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _serra(freq: float, t: float) -> float:
	return fmod(freq * t, 1.0) * 2.0 - 1.0


## Vinheta de velocidade: overlay radial escuro nas bordas, alpha 0 parado.
func _construir_vinheta() -> void:
	_vinheta_camada = CanvasLayer.new()
	_vinheta_camada.name = "VinhetaRapidez"
	_vinheta_camada.layer = 1
	add_child(_vinheta_camada)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 1))
	grad.add_point(0.55, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_vinheta = TextureRect.new()
	_vinheta.name = "Vinheta"
	_vinheta.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vinheta.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vinheta.stretch_mode = TextureRect.STRETCH_SCALE
	_vinheta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vinheta.texture = tex
	_vinheta.modulate.a = 0.0
	_vinheta_camada.add_child(_vinheta)
	_vinheta_camada.visible = false


## Tier 1 de sensacao de velocidade: FOV + vinheta + tremor + vento.
func _efeitos_velocidade(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var fator := clampf(planar / velocidade_turbo, 0.0, 1.0)
	var ativo := ligado and cam.current
	# 1) FOV abre com a velocidade.
	var alvo_fov := lerpf(fov_base, fov_turbo, fator) if ativo else fov_base
	cam.fov = lerpf(cam.fov, alvo_fov, 1.0 - exp(-3.0 * delta))
	# 2) Vinheta nas bordas (some escondida: custo zero parada).
	var v := smoothstep(0.25, 1.0, fator) if ativo else 0.0
	_vinheta_camada.visible = v > 0.02
	_vinheta.modulate.a = v * vinheta_max
	# 3) Tremor quase imperceptivel, so no turbo (entra/sai suave).
	var turbo := ativo and Input.is_action_pressed("correr")
	_tremor_suave = move_toward(_tremor_suave, 1.0 if turbo else 0.0, delta * 2.5)
	var amp := tremor_max * _tremor_suave
	var t := Time.get_ticks_msec() / 1000.0
	cam.position = _cam_base + Vector3(sin(t * 39.7) * amp, sin(t * 33.1 + 1.3) * amp, 0.0)
	# 4) Vento: volume e pitch seguem a velocidade.
	if ativo and not _vento.playing:
		_vento.play()
	if ativo:
		# Vento: atenuado para não ficar ensurdecedor na velocidade máxima.
		var alvo_db := lerpf(-54.0, -38.0, fator)
		_vento.volume_db = lerpf(_vento.volume_db, alvo_db, 1.0 - exp(-5.0 * delta))
		_vento.pitch_scale = lerpf(0.85, 1.15, fator)


## Ruido branco filtrado (1 s em loop com crossfade) para o vento.
func _gerar_vento() -> AudioStreamWAV:
	var taxa := 22050
	var n := taxa
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var dados := PackedFloat32Array()
	dados.resize(n)
	var y := 0.0
	var a := 0.08
	for i in n:
		var x := rng.randf_range(-1.0, 1.0)
		y += a * (x - y)
		dados[i] = y * 3.0
	var m := 2205
	for i in m:
		var t := float(i) / float(m)
		dados[n - m + i] = lerpf(dados[n - m + i], dados[i], t)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(dados[i], -1.0, 1.0) * 32760.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = taxa
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


## Neblina de altitude: so com a camera do drone ativa, o solo esmaece
## perto da altura maxima (rampa suave a partir de FOG_ALTURA_INICIO).
## Ao sair do drone, restaura a base. Custo: 2 uniforms por frame.
func _neblina_altura() -> void:
	if cam == null or not cam.current:
		_restaurar_neblina()
		return
	if not _neblina_ref():
		return
	var f := clampf((position.y - FOG_ALTURA_INICIO) / maxf(altura_max - FOG_ALTURA_INICIO, 0.01), 0.0, 1.0)
	f = f * f
	_env.fog_depth_begin = lerpf(_fog_ini_base, FOG_INICIO_MIN, f)
	_env.fog_depth_end = lerpf(_fog_fim_base, FOG_FIM_MIN, f)


func _neblina_ref() -> bool:
	if _env != null and is_instance_valid(_env):
		return true
	var ceu := get_tree().current_scene.get_node_or_null("MundoCeu") as WorldEnvironment
	if ceu == null or ceu.environment == null:
		return false
	_env = ceu.environment
	_fog_ini_base = _env.fog_depth_begin
	_fog_fim_base = _env.fog_depth_end
	return true


func _restaurar_neblina() -> void:
	if _env == null or not is_instance_valid(_env):
		return
	_env.fog_depth_begin = _fog_ini_base
	_env.fog_depth_end = _fog_fim_base
