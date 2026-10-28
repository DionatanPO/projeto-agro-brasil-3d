extends Node3D
## Clima: chuva + relâmpagos + céu chuvoso, alternado pela ação "chuva" (F1).
##
## - A chuva usa GPUParticles3D com emissão em caixa em volta do jogador, então
##   a renderização fica local e barata (não cobre o mapa inteiro).
## - O som (assets/audio/som_chuva.mp3) toca em loop com fade in/out.
## - Relâmpagos são flashes de uma DirectionalLight3D + brilho do fundo do céu.
## - O Sky3D/SkyDome recebe mais nuvens, escuridão e névoa enquanto chove.

@export_group("Chuva")
## Quantidade de gotas. 7000 dá chuva densa; reduza se cair o FPS.
@export var quantidade_gotas: int = 7000
## Raio (m) da área de chuva em volta do jogador.
@export var raio_chuva: float = 24.0
## Altura do emissor acima do jogador.
@export var altura_emissor: float = 10.0
## Velocidade de queda das gotas (m/s).
@export var velocidade_chuva: float = 20.0

@export_group("Som")
## Caminho do áudio de chuva.
@export var audio_chuva: String = "res://assets/audio/som_chuva.mp3"
## Volume (dB) com a chuva ligada.
@export var volume_chuva_db: float = -6.0

@export_group("Relâmpagos")
## Intervalo mínimo/máximo (s) entre relâmpagos.
@export var intervalo_min: float = 6.0
@export var intervalo_max: float = 14.0
## Energia do flash.
@export var energia_relampago: float = 5.0

@export_group("Clima")
## Velocidade (s) da transição do céu entre normal e chuvoso.
@export var tempo_transicao: float = 2.5

# --- Nós criados em runtime ---
var _particulas: GPUParticles3D
var _audio: AudioStreamPlayer
var _relampago: DirectionalLight3D
var _timer_raio: Timer

# --- Referências do mundo ---
var _sky3d: Node
var _skydome: Node
var _environment: Environment
var _sol: DirectionalLight3D

# --- Estado ---
var _chovendo: bool = false
var _tween_clima: Tween

# Valores originais (para voltar ao normal)
var _originais: Dictionary = {}


func _ready() -> void:
	_criar_particulas()
	_criar_audio()
	_criar_relampago()
	_criar_timer_raio()
	_capturar_ambiente()
	_mostrar_chuva(false, true)
	print("[Clima] Pronto. Pressione a tecla 'chuva' (F1) para alternar a chuva.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chuva"):
		alternar_chuva()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Mantém a área de chuva centrada no jogador (ou na câmera, sem jogador).
	if _particulas == null:
		return
	var alvo := _posicao_jogador()
	if alvo != Vector3.INF:
		global_position = alvo


## API pública ────────────────────────────────────────────────────────────────

func alternar_chuva() -> void:
	_mostrar_chuva(not _chovendo)


func esta_chovendo() -> bool:
	return _chovendo


## Interno ────────────────────────────────────────────────────────────────────

func _posicao_jogador() -> Vector3:
	var player := get_tree().get_first_node_in_group("jogador") as Node3D
	if player != null and is_instance_valid(player):
		return player.global_position
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3.INF


func _mostrar_chuva(ligar: bool, instantaneo: bool = false) -> void:
	_chovendo = ligar

	if _particulas != null:
		_particulas.emitting = ligar
		_particulas.visible = ligar

	# Som
	if _audio != null:
		if ligar:
			if not _audio.playing:
				_audio.play()
		if instantaneo:
			_audio.volume_db = volume_chuva_db if ligar else -80.0
			if not ligar:
				_audio.stop()
		else:
			_criar_tween_audio(ligar)

	# Relâmpagos
	if _timer_raio != null:
		if ligar:
			_agendar_proximo_raio()
		else:
			_timer_raio.stop()

	_aplicar_clima(ligar, instantaneo)


## Partículas ─────────────────────────────────────────────────────────────────

func _criar_particulas() -> void:
	_particulas = GPUParticles3D.new()
	_particulas.name = "ChuvaParticulas"
	_particulas.amount = quantidade_gotas
	_particulas.lifetime = 1.6
	_particulas.preprocess = 1.0
	_particulas.local_coords = false
	_particulas.emitting = false
	_particulas.visible = false
	_particulas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# AABB grande evita que o culling suma com a chuva quando a câmera se move.
	_particulas.visibility_aabb = AABB(
		Vector3(-raio_chuva - 10.0, -40.0, -raio_chuva - 10.0),
		Vector3(raio_chuva * 2.0 + 20.0, 80.0, raio_chuva * 2.0 + 20.0)
	)
	_particulas.position = Vector3(0, altura_emissor, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(raio_chuva, 1.0, raio_chuva)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 4.0
	mat.initial_velocity_min = velocidade_chuva * 0.85
	mat.initial_velocity_max = velocidade_chuva * 1.15
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.7
	mat.scale_max = 1.35
	mat.color = Color(0.72, 0.82, 0.95, 0.55)
	_particulas.process_material = mat

	# Gota = quad estreito e alto, sempre de frente para a câmera (billboard).
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.85)
	var gota := StandardMaterial3D.new()
	gota.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gota.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gota.albedo_color = Color(0.72, 0.82, 0.95, 0.5)
	gota.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gota.billboard_keep_scale = true
	gota.cull_mode = BaseMaterial3D.CULL_DISABLED
	gota.disable_receive_shadows = true
	quad.material = gota
	_particulas.draw_pass_1 = quad

	add_child(_particulas)


## Áudio ──────────────────────────────────────────────────────────────────────

func _criar_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "AudioChuva"
	_audio.volume_db = -80.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_audio.bus = "Efeitos"
	if ResourceLoader.exists(audio_chuva):
		var stream := load(audio_chuva)
		if stream != null:
			# Garante loop mesmo que o import não tenha sido configurado para repetir.
			if stream is AudioStreamMP3:
				(stream as AudioStreamMP3).loop = true
			elif stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			_audio.stream = stream
	else:
		push_warning("[Clima] áudio de chuva não encontrado: " + audio_chuva)
	add_child(_audio)


func _criar_tween_audio(ligar: bool) -> void:
	var t := create_tween()
	if ligar:
		t.tween_property(_audio, "volume_db", volume_chuva_db, tempo_transicao)
	else:
		t.tween_property(_audio, "volume_db", -80.0, tempo_transicao)
		t.tween_callback(_audio.stop)


## Relâmpagos ─────────────────────────────────────────────────────────────────

func _criar_relampago() -> void:
	_relampago = DirectionalLight3D.new()
	_relampago.name = "Relampago"
	_relampago.light_color = Color(0.82, 0.88, 1.0)
	_relampago.light_energy = 0.0
	_relampago.shadow_enabled = false
	_relampago.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	add_child(_relampago)


func _criar_timer_raio() -> void:
	_timer_raio = Timer.new()
	_timer_raio.name = "TimerRelampago"
	_timer_raio.one_shot = true
	_timer_raio.timeout.connect(_on_raio_timeout)
	add_child(_timer_raio)


func _agendar_proximo_raio() -> void:
	_timer_raio.wait_time = randf_range(intervalo_min, intervalo_max)
	_timer_raio.start()


func _on_raio_timeout() -> void:
	if not _chovendo:
		return
	_flash_relampago()
	_agendar_proximo_raio()


func _flash_relampago() -> void:
	# Sequência de dois clarões curtos, como um raio real.
	var t := create_tween()
	t.tween_property(_relampago, "light_energy", energia_relampago, 0.04)
	t.tween_property(_relampago, "light_energy", energia_relampago * 0.15, 0.08)
	t.tween_property(_relampago, "light_energy", energia_relampago * 0.8, 0.05)
	t.tween_property(_relampago, "light_energy", 0.0, 0.28)

	# Brilho extra no fundo do céu junto com o flash.
	if _environment != null:
		var bg := float(_originais.get("bg_energy", 1.0))
		var tf := create_tween()
		tf.tween_property(_environment, "background_energy_multiplier", bg + 1.5, 0.04)
		tf.tween_property(_environment, "background_energy_multiplier", bg, 0.35)


## Clima / céu ────────────────────────────────────────────────────────────────

func _capturar_ambiente() -> void:
	var cena := get_tree().current_scene
	if cena == null:
		return
	_sky3d = cena.get_node_or_null("Sky3D")
	if _sky3d != null:
		_environment = _sky3d.get("environment") as Environment
		_sol = _sky3d.get_node_or_null("SunLight") as DirectionalLight3D
		var dome := _sky3d.get_node_or_null("SkyDome")
		if dome != null:
			_skydome = dome

	# Guarda valores originais para restaurar depois.
	_originais.clear()
	if _environment != null:
		_originais["fog_density_env"] = _environment.fog_density
		_originais["ambient_energy"] = _environment.ambient_light_energy
		_originais["bg_energy"] = _environment.background_energy_multiplier
		_originais["adj_enabled"] = _environment.adjustment_enabled
		_originais["adj_brightness"] = _environment.adjustment_brightness
		_originais["adj_saturation"] = _environment.adjustment_saturation
		_originais["adj_contrast"] = _environment.adjustment_contrast
	if _sol != null:
		_originais["sol_energy"] = _sol.light_energy
	if _skydome != null:
		for prop in ["cumulus_coverage", "cumulus_intensity", "cumulus_thickness",
				"cirrus_coverage", "atm_darkness", "fog_density"]:
			var valor: Variant = _skydome.get(prop)
			if valor != null:
				_originais[prop] = valor


func _aplicar_clima(chuvoso: bool, instantaneo: bool) -> void:
	if _tween_clima != null and _tween_clima.is_valid():
		_tween_clima.kill()

	if instantaneo or not is_inside_tree():
		if chuvoso:
			_aplicar_valores_chuvosos(1.0)
		else:
			_aplicar_valores_chuvosos(0.0)
		return

	# 0 = tempo bom, 1 = chuva forte. Um valor "mestre" anima todos os parâmetros.
	var alvo := 1.0 if chuvoso else 0.0
	var inicial := 0.0 if chuvoso else 1.0
	_tween_clima = create_tween()
	_tween_clima.tween_method(Callable(self, "_aplicar_valores_chuvosos"),
		inicial, alvo, tempo_transicao)


## Aplica um fator 0..1 (0 = tempo bom, 1 = chuva forte) nos parâmetros do céu.
func _aplicar_valores_chuvosos(t: float) -> void:
	if _environment != null:
		var fog_env: float = float(_originais.get("fog_density_env", 0.0035))
		_environment.fog_density = lerpf(fog_env, maxf(fog_env, 0.025), t)
		var amb: float = float(_originais.get("ambient_energy", 1.0))
		_environment.ambient_light_energy = lerpf(amb, amb * 0.42, t)
		var bg: float = float(_originais.get("bg_energy", 1.0))
		_environment.background_energy_multiplier = lerpf(bg, bg * 0.52, t)

		# Céu nublado: leve dessaturação e escurecimento, sem exagerar.
		_environment.adjustment_enabled = bool(_originais.get("adj_enabled", false)) or t > 0.001
		var brilho: float = float(_originais.get("adj_brightness", 1.0))
		_environment.adjustment_brightness = lerpf(brilho, 0.82, t)
		var sat: float = float(_originais.get("adj_saturation", 1.0))
		_environment.adjustment_saturation = lerpf(sat, 0.85, t)
		var cont: float = float(_originais.get("adj_contrast", 1.0))
		_environment.adjustment_contrast = lerpf(cont, 1.02, t)

	if _sol != null:
		var sol: float = float(_originais.get("sol_energy", 1.8))
		_sol.light_energy = lerpf(sol, sol * 0.2, t)

	if _skydome != null:
		var cov: float = float(_originais.get("cumulus_coverage", 0.55))
		_skydome.set("cumulus_coverage", lerpf(cov, 0.99, t))
		var cint: float = float(_originais.get("cumulus_intensity", 0.6))
		_skydome.set("cumulus_intensity", lerpf(cint, 1.1, t))
		var cth: float = float(_originais.get("cumulus_thickness", 0.0243))
		_skydome.set("cumulus_thickness", lerpf(cth, 0.065, t))
		var circ: float = float(_originais.get("cirrus_coverage", 0.5))
		_skydome.set("cirrus_coverage", lerpf(circ, 0.95, t))
		var dark: float = float(_originais.get("atm_darkness", 0.5))
		_skydome.set("atm_darkness", lerpf(dark, 0.87, t))
		var fog_dome: float = float(_originais.get("fog_density", 0.0007))
		_skydome.set("fog_density", lerpf(fog_dome, maxf(fog_dome, 0.025), t))
