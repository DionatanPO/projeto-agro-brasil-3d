extends CharacterBody3D
## Jogador em terceira pessoa: camera independente (mouse/stick direito),
## movimento relativo a camera, malha gira ate o movimento. Suporta teclado
## e controle (Xbox: stick esquerdo move, direito olha, A pula, X interage,
## Y diario, LB corre).

@export var velocidade_andar := 4.5
@export var velocidade_correr := 7.0
## Fator sobre a velocidade nativa do clip de andar (1.0 = nativa).
## Sobe corpo e animacao juntos, entao os pes continuam casando.
## 1.6 = ~2.03 m/s (passo largo do clip e fixo: acelerar mais que isso faz a
## passada do andar ficar mais rapida que a da corrida, que fica estranho).
@export var fator_andar := 1.6
## Rampa de velocidade (m/s^2): suaviza andar<->correr e saidas/paradas.
@export var aceleracao := 10.0
@export var desaceleracao := 14.0
@export var forca_pulo := 3.2
@export var sensibilidade_mouse := 0.003
@export var sensibilidade_stick := 2.8
## Segundos parado ate trocar o Idle normal pelo SadIdle (cabeca baixa).
@export var tempo_sad_idle := 3.0

## Passos sintetizados de grama/terra (passo_1..6.wav, gerados fora do jogo):
## entram em rodizio pra passada nao repetir sempre o mesmo som.
const PASSOS_ARQUIVOS := [
	"res://assets/audio/passo_1.wav",
	"res://assets/audio/passo_2.wav",
	"res://assets/audio/passo_3.wav",
	"res://assets/audio/passo_4.wav",
	"res://assets/audio/passo_5.wav",
	"res://assets/audio/passo_6.wav",
]

@export var bloqueado := false

## Estado interno da caminhada autônoma da cutscene.
var _em_cutscene_caminhando := false
var _destino_cutscene := Vector3.ZERO

## Controle do snap inicial ao chão (evita retentativa infinita).
var _tentativas_chao := 0
const MAX_TENTATIVAS_CHAO := 24

@onready var rig: Node3D = $CameraRig
@onready var bracos_camera: SpringArm3D = $CameraRig/BracosCamera
@onready var modelo: Node3D = $Modelo

@onready var SaveSystem := get_node("/root/SaveSystem")

var gravidade: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _angulo_vertical := -0.18
var animador: AnimationPlayer
var _animacao_atual := ""
var _tempo_parado := 0.0
var _audio_passos: AudioStreamPlayer3D
var _som_passo_andar: AudioStream
var _som_passo_corrida: AudioStream
var _som_pulo: AudioStream
## Passos de grama/terra carregados de fato (vazio = cai nos passo_andar/correr).
var _sons_passo: Array[AudioStream] = []
var _idx_passo := 0
var _tempo_entre_passos := 0.0
## Velocidade nativa dos clips Mixamo (m/s, medida do root motion do quadril
## antes de remove-lo). Serve para sincronizar a passada com o corpo e evitar
## o "deslizamento" (chao mais rapido que os pes).
var _nativa_andar := 0.0
var _nativa_correr := 0.0
## Antecipacao do pulo (s): paradinha freando o corpo antes de lancar.
const ANTECIPACAO_PULO := 0.18
const ANTECIPACAO_PULO_CORRIDA := 0.06
const ANTECIPACAO_PULO_ANDANDO := 0.10
const VELOCIDADE_MINIMA_ANDAR_PULO := 0.4
const VELOCIDADE_MINIMA_RUNNING_JUMP := 5.0
const FREIO_PULO := 60.0
## Ossos das pernas congelados no pulo + instante do agacho amostrado (s).
const PERNAS_PULO: Array[String] = ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftToe_End", "RightToe_End"]
const TEMPO_POSE_PULO := 0.8
var _pulo_preparando := 0.0
var _pulo_em_corrida := false
var _pulo_andando := false
## Tempos de crossfade (s) entre animacoes.
const BLEND_TERRA := 0.22
const BLEND_PULO_SAIDA := 0.1
const BLEND_POUSO := 0.25
## Intervalo do som do passo andando (s), tirado da propria animacao Walk:
## os clips Mixamo tem 2 apoios por ciclo, entao o passo sai a cada
## (duracao do ciclo / 2). Assim o som nunca sai fora do pe, em qualquer
## velocidade/fator. Calculado em _ready (cai em 0.48 s sem animacao).
var _intervalo_passo_andar := 0.48


func _ready() -> void:
	add_to_group("jogador")
	# Spawn alto e raycast para achar chão do terreno (agrupamento da fazenda)
	var spawn_pos := Vector3(76.456, 50.0, 192.678)
	position = spawn_pos
	
	# Só carrega save se existir E Y > 5 (não no vazio)
	if SaveSystem.tem_save():
		var pos: Variant = SaveSystem.dados.get("posicao_jogador")
		if pos is Array and (pos as Array).size() == 3:
			var saved_y := float(pos[1])
			if saved_y > 5.0:
				position = Vector3(float(pos[0]), saved_y, float(pos[2]))
	
	# Raycast deferred - física pronta
	call_deferred("_snap_to_ground")
	
	animador = modelo.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _snap_to_ground() -> void:
	var space_state = get_world_3d().direct_space_state
	# Usa todas as layers: no Forest o Terrain3D pode estar em uma layer
	# diferente da usada no mapa do AgroBrasil.
	# Comeca acima do jogador e ignora o proprio corpo: se ele ja tiver caido
	# ate o chao antes deste deferred rodar, o raio nao pode acertar a si mesmo.
	var origem := position + Vector3(0, 2.0, 0)
	var query = PhysicsRayQueryParameters3D.create(origem, origem + Vector3(0, -150, 0), 0xFFFFFFFF)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	if result:
		var ground_y: float = result.position.y
		position = Vector3(position.x, ground_y + 1.0, position.z)
		print("SPAWN -> GROUND Y: ", ground_y, " | FINAL: ", position)
	elif _tentativas_chao < MAX_TENTATIVAS_CHAO:
		_tentativas_chao += 1
		call_deferred("_snap_to_ground")
		return
	else:
		# Sem chao apos varias tentativas: mantem a posicao e deixa a
		# gravidade assentar o jogador, evitando um loop infinito de raycast.
		print("AVISO: chao nao encontrado apos ", MAX_TENTATIVAS_CHAO, " tentativas; mantendo spawn em ", position)
	_finalizar_spawn()


func _finalizar_spawn() -> void:
	pass
	if animador != null:
		_importar_animacoes_personagem()
		# Calibra o andar pela animacao: o corpo anda na velocidade nativa do
		# clip vezes o fator_andar (corpo e animacao sobem juntos, pes casam).
		# A corrida nao mexe (ja estava certa).
		if _nativa_andar > 0.01:
			velocidade_andar = _nativa_andar * fator_andar
			print("ANDAR_NATIVO=", _nativa_andar, " ANDAR_AJUSTADO=", velocidade_andar)
		_atualizar_animacao("Idle")
		_intervalo_passo_andar = _intervalo_passo_do_clip("Walk", fator_andar)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	_configurar_sons_passos()
	
	# Cutscene de introdução do mundo (só na primeira vez)
	if not SaveSystem.dados.get("intro_mundo_vista", false):
		_instanciar_intro_cutscene()


func forcar_idle_cutscene() -> void:
	if _tem_animacao("Idle"):
		_atualizar_animacao("Idle")
		if animador != null:
			animador.play("Idle")
	elif _tem_animacao("SadIdle"):
		_atualizar_animacao("SadIdle")

func _instanciar_intro_cutscene() -> void:
	if SaveSystem.dados.get("intro_mundo_vista", false):
		return
	var cena := preload("res://scenes/world/intro_cutscene.tscn")
	var inst := cena.instantiate()
	get_tree().root.add_child(inst)
	# Garante pose de idle (parado) durante a cutscene
	_atualizar_animacao("Idle")
	# A cutscene se auto-gerencia: bloqueia o jogador, roda a câmera,
	# mostra legendas, e ao final devolve o controle e se remove.


## Intervalo entre sons de passo tirado da propria animacao (s). Os clips
## Mixamo tem 2 apoios por ciclo, entao o passo sai a cada (duracao / 2).
## A duracao cai com o speed_scale, entao o som acompanha os pes sozinho.
func _intervalo_passo_do_clip(nome: String, escala: float) -> float:
	if animador == null or not animador.has_animation(nome):
		return 0.48
	var duracao := animador.get_animation(nome).length / maxf(escala, 0.05)
	return duracao * 0.5


func _configurar_sons_passos() -> void:
	# Passos de grama/terra primeiro (passo_1..6.wav), em rodizio. Se algum
	# arquivo faltar, sobra vazio e os antigos (passo_andar.wav /
	# passo_correr.wav) voltam a ser usados.
	for caminho in PASSOS_ARQUIVOS:
		if ResourceLoader.exists(caminho):
			var corte := load(caminho) as AudioStream
			if corte != null:
				_sons_passo.append(corte)
	_som_passo_andar = load("res://assets/audio/passo_andar.wav") as AudioStream
	_som_passo_corrida = load("res://assets/audio/passo_correr.wav") as AudioStream
	_som_pulo = load("res://assets/audio/passo_pulo.wav") as AudioStream
	_audio_passos = AudioStreamPlayer3D.new()
	_audio_passos.name = "AudioPassos"
	_audio_passos.max_distance = 22.0
	_audio_passos.unit_size = 5.0
	_audio_passos.volume_db = -30.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_audio_passos.bus = "Efeitos"
	add_child(_audio_passos)


func _tocar_som_passo(correndo: bool) -> void:
	if _audio_passos == null:
		return
	if not _sons_passo.is_empty():
		# Uma pisada por passo, sempre na ordem: soa natural e nao repete.
		_audio_passos.stream = _sons_passo[_idx_passo]
		_idx_passo = (_idx_passo + 1) % _sons_passo.size()
		# Correndo usa a mesma familia de som, so um pouco mais aguda.
		_audio_passos.pitch_scale = 1.15 if correndo else 1.0
	else:
		_audio_passos.stream = _som_passo_corrida if correndo else _som_passo_andar
		_audio_passos.pitch_scale = 1.0
	if _audio_passos.stream != null:
		_audio_passos.play()


func _tocar_som_pulo() -> void:
	if _audio_passos == null or _som_pulo == null:
		return
	_audio_passos.stream = _som_pulo
	_audio_passos.pitch_scale = 1.0
	_audio_passos.play()


## Junta as clips Mixamo (cada FBX tem 1 anim "mixamo_com") no AnimationPlayer
## do modelo base (idle.fbx): SadIdle <- idle.fbx (cabeca baixa),
## Idle <- stop.fbx (parado normal), Walk <- andando.fbx,
## Run <- correndo.fbx, Jump <- Jump_stop.fbx,
## WalkJump <- pulando.fbx, RunJump <- running_jump.fbx. Os esqueletos sao identicos
## (65 bones mixamorig_*), entao as tracks "Skeleton3D:..." sao reutilizaveis.
func _importar_animacoes_personagem() -> void:
	if animador == null:
		return
	var lib: AnimationLibrary = animador.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		animador.add_animation_library("", lib)
	if animador.has_animation("mixamo_com") and not animador.has_animation("SadIdle"):
		var base_anim: Animation = animador.get_animation("mixamo_com")
		var sad: Animation = base_anim.duplicate()
		_remover_root_motion(sad)
		lib.add_animation("SadIdle", sad)
	if animador.has_animation("mixamo_com"):
		lib.remove_animation("mixamo_com")
	var mapa := {
		"Idle": "res://assets/models/personagem/stop.fbx",
		"Walk": "res://assets/models/personagem/andando.fbx",
		"Run": "res://assets/models/personagem/correndo.fbx",
		"Jump": "res://assets/models/personagem/Jump_stop.fbx",
		"WalkJump": "res://assets/models/personagem/pulando.fbx",
		"RunJump": "res://assets/models/personagem/running_jump.fbx",
	}
	for nome in mapa.keys():
		if animador.has_animation(nome):
			continue
		var caminho: String = mapa[nome]
		if not ResourceLoader.exists(caminho):
			push_warning("[Jogador] Animacao ausente: %s" % caminho)
			continue
		var ps: PackedScene = load(caminho) as PackedScene
		if ps == null:
			push_warning("[Jogador] Falha ao carregar: %s" % caminho)
			continue
		var inst: Node = ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var nome_clip := "mixamo_com"
		if ap != null and not ap.has_animation(nome_clip):
			var lista := ap.get_animation_list()
			if lista.size() > 0:
				nome_clip = String(lista[0])
		if ap != null and ap.has_animation(nome_clip):
			var clip: Animation = ap.get_animation(nome_clip).duplicate()
			if nome == "Walk":
				_nativa_andar = _velocidade_nativa(clip)
			elif nome == "Run":
				_nativa_correr = _velocidade_nativa(clip)
			_remover_root_motion(clip)
			lib.add_animation(nome, clip)
		else:
			push_warning("[Jogador] Sem animacao em: %s" % caminho)
		inst.queue_free()


## Mede a velocidade "nativa" do clip (m/s): deslocamento horizontal do quadril
## dividido pela duracao. O Walk/Run do Mixamo avancam para frente; esse valor
## e a velocidade em que a passada casa com o deslocamento em 1.0x.
func _velocidade_nativa(clip: Animation) -> float:
	if clip.length <= 0.0:
		return 0.0
	for i in clip.get_track_count():
		if not ("Hips" in String(clip.track_get_path(i))):
			continue
		if clip.track_get_key_count(i) < 2:
			continue
		if typeof(clip.track_get_key_value(i, 0)) != TYPE_VECTOR3:
			continue
		var p0: Vector3 = clip.track_get_key_value(i, 0)
		var p1: Vector3 = clip.track_get_key_value(i, clip.track_get_key_count(i) - 1)
		return Vector2(p1.x - p0.x, p1.z - p0.z).length() / clip.length
	return 0.0


## Remove o "root motion" do Mixamo: a track de POSICAO do quadril desloca o
## corpo inteiro (deriva para frente no Walk/Run, flutua no Jump). O movimento
## real vem do CharacterBody (velocity), entao o quadril fica congelado na
## pose de descanso e so a rotacao dele anima. Pernas/bracos seguem normais.
func _remover_root_motion(clip: Animation) -> void:
	for i in range(clip.get_track_count() - 1, -1, -1):
		if not ("Hips" in String(clip.track_get_path(i))):
			continue
		if clip.track_get_key_count(i) == 0:
			continue
		# Tracks de POSICAO/ESCALA guardam Vector3; a de ROTACAO guarda
		# Quaternion e deve ser mantida (inclinacao do tronco etc).
		if typeof(clip.track_get_key_value(i, 0)) == TYPE_VECTOR3:
			clip.remove_track(i)


## Congela as pernas do pulo na pose de agacho: o clip do Mixamo alterna as
## pernas (parece "andar no ar"). Amostra a rotacao de cada osso da perna no
## instante do agacho e troca as tracks por pose estatica. Bracos/tronco
## continuam animados.
func _congelar_pernas_no_pulo(clip: Animation) -> void:
	for i in range(clip.get_track_count() - 1, -1, -1):
		var caminho := String(clip.track_get_path(i))
		var e_perna := false
		for osso in PERNAS_PULO:
			if caminho.ends_with(osso):
				e_perna = true
				break
		if not e_perna:
			continue
		if clip.track_get_key_count(i) == 0:
			continue
		if typeof(clip.track_get_key_value(i, 0)) != TYPE_QUATERNION:
			continue
		var pose: Quaternion = clip.rotation_track_interpolate(i, TEMPO_POSE_PULO)
		while clip.track_get_key_count(i) > 0:
			clip.track_remove_key(i, 0)
		clip.track_insert_key(i, 0.0, pose)


func _unhandled_input(evento: InputEvent) -> void:
	if bloqueado:
		return
	if evento is InputEventScreenDrag and Dispositivo.movel():
		var arrasto := evento as InputEventScreenDrag
		_olhar(
			-arrasto.relative.x * sensibilidade_mouse * 1.4,
			-arrasto.relative.y * sensibilidade_mouse * 1.4
		)
		return
	if evento is InputEventMouseMotion and not Dispositivo.movel() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_olhar(-(evento as InputEventMouseMotion).relative.x * sensibilidade_mouse, -(evento as InputEventMouseMotion).relative.y * sensibilidade_mouse)
	if evento is InputEventMouseButton and (evento as InputEventMouseButton).pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if bloqueado:
		# Modo caminhada autônoma da cutscene: move o personagem em direção ao destino.
		if _em_cutscene_caminhando and _destino_cutscene != Vector3.ZERO:
			var diff := _destino_cutscene - global_position
			diff.y = 0.0
			if diff.length() < 0.25:
				# Chegou: congela na posição final e vai para Idle.
				global_position.x = _destino_cutscene.x
				global_position.z = _destino_cutscene.z
				velocity = Vector3.ZERO
				move_and_slide()
				_em_cutscene_caminhando = false
				_atualizar_animacao("Idle")
				if animador != null:
					animador.speed_scale = 1.0
				return
			var dir := diff.normalized()
			velocity.x = dir.x * velocidade_andar
			velocity.z = dir.z * velocidade_andar
			if not is_on_floor():
				velocity.y -= gravidade * delta
			move_and_slide()
			# Gira o modelo para a direção da caminhada
			var alvo_yaw := atan2(-dir.x, -dir.z)
			modelo.rotation.y = lerp_angle(modelo.rotation.y, alvo_yaw, 1.0 - exp(-10.0 * delta))
			_atualizar_animacao("Walk")
			if animador != null:
				animador.speed_scale = fator_andar
			# Som dos passos
			_tempo_entre_passos += delta
			if _tempo_entre_passos >= _intervalo_passo_andar:
				_tocar_som_passo(false)
				_tempo_entre_passos = 0.0
			return
		# Parado e bloqueado: apenas aplica gravidade e toca Idle.
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravidade * delta
		move_and_slide()
		if animador != null and is_on_floor():
			_atualizar_animacao("Idle")
		return

	var no_chao := is_on_floor()
	if not no_chao:
		velocity.y -= gravidade * delta
		_pulo_preparando = 0.0
	if Input.is_action_just_pressed("pular") and no_chao and _pulo_preparando <= 0.0:
		var velocidade_horizontal := Vector2(velocity.x, velocity.z).length()
		_pulo_em_corrida = velocidade_horizontal >= VELOCIDADE_MINIMA_RUNNING_JUMP
		_pulo_andando = velocidade_horizontal >= VELOCIDADE_MINIMA_ANDAR_PULO and not _pulo_em_corrida
		if _pulo_em_corrida:
			_pulo_preparando = ANTECIPACAO_PULO_CORRIDA
		elif _pulo_andando:
			_pulo_preparando = ANTECIPACAO_PULO_ANDANDO
		else:
			_pulo_preparando = ANTECIPACAO_PULO
	if _pulo_preparando > 0.0 and no_chao:
		_pulo_preparando -= delta
		# Nos saltos andando/correndo, preserva o embalo.
		# No salto parado, freia o corpo durante a antecipacao.
		if not _pulo_em_corrida and not _pulo_andando:
			velocity.x = move_toward(velocity.x, 0.0, FREIO_PULO * delta)
			velocity.z = move_toward(velocity.z, 0.0, FREIO_PULO * delta)
		velocity.y = 0.0
		if _pulo_preparando <= 0.0:
			velocity.y = forca_pulo
			_tocar_som_pulo()
	var entrada := Vector2(
		Input.get_axis("mover_esq", "mover_dir"),
		Input.get_axis("mover_frente", "mover_tras")
	)
	var vel := velocidade_correr if Input.is_action_pressed("correr") else velocidade_andar
	var base := rig.global_transform.basis
	var direcao: Vector3 = base * Vector3(entrada.x, 0.0, entrada.y)
	direcao.y = 0.0
	if direcao.length() > 0.01:
		direcao = direcao.normalized()
		var alvo_yaw := atan2(-direcao.x, -direcao.z)
		modelo.rotation.y = lerp_angle(modelo.rotation.y, alvo_yaw, 1.0 - exp(-10.0 * delta))
	if _pulo_preparando <= 0.0:
		# Rampa em vez de corte seco: o corpo acelera/freia ate o alvo,
		# entao andar<->correr (e soltar o stick) fica suave.
		var alvo_x := direcao.x * vel
		var alvo_z := direcao.z * vel
		var taxa := aceleracao
		if Vector2(alvo_x, alvo_z).length() < Vector2(velocity.x, velocity.z).length():
			taxa = desaceleracao
		velocity.x = move_toward(velocity.x, alvo_x, taxa * delta)
		velocity.z = move_toward(velocity.z, alvo_z, taxa * delta)
	move_and_slide()
	no_chao = is_on_floor()
	var em_movimento := entrada.length() > 0.01
	# Animacao segue a velocidade REAL do corpo (com histerese), nao o botao:
	# troca no meio da rampa, sem piscar na borda.
	var rapidez := Vector2(velocity.x, velocity.z).length()
	var meio := (velocidade_andar + velocidade_correr) * 0.5
	var animacao_movimento := "Walk"
	if rapidez > meio:
		animacao_movimento = "Run"
	elif _animacao_atual == "Run" and rapidez > velocidade_andar + 0.4:
		animacao_movimento = "Run"
	var correndo_anim := animacao_movimento == "Run"
	if no_chao and em_movimento:
		# Intervalo do passo vem da animacao (2 apoios por ciclo), entao o som
		# casa com os pes. A corrida ja estava sincronizada: nao mexe.
		var intervalo_passo := 0.31 if correndo_anim else _intervalo_passo_andar
		_tempo_entre_passos += delta
		if _tempo_entre_passos >= intervalo_passo:
			_tocar_som_passo(correndo_anim)
			_tempo_entre_passos = 0.0
	else:
		_tempo_entre_passos = 0.0
	if no_chao and not em_movimento:
		_tempo_parado += delta
	else:
		_tempo_parado = 0.0
	var animacao_alvo := "RunJump" if _pulo_em_corrida else ("WalkJump" if _pulo_andando else "Jump")
	if no_chao and _pulo_preparando <= 0.0:
		if em_movimento:
			animacao_alvo = animacao_movimento
		elif _tempo_parado >= tempo_sad_idle and _tem_animacao("SadIdle"):
			animacao_alvo = "SadIdle"
		else:
			animacao_alvo = "Idle"
	_atualizar_animacao(animacao_alvo)
	# Animacao acompanha o fator: corpo e pernas na mesma proporcao.
	if animador != null:
		animador.speed_scale = fator_andar if animacao_alvo == "Walk" else 1.0
	SaveSystem.dados["posicao_jogador"] = [position.x, position.y, position.z]


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_olhar_stick(delta)


func _olhar(dx: float, dy: float) -> void:
	rig.rotate_y(dx)
	_angulo_vertical = clampf(_angulo_vertical + dy, -1.2, 0.6)
	bracos_camera.rotation.x = _angulo_vertical


func _olhar_stick(delta: float) -> void:
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if joy.length() < 0.2:
		return
	_olhar(-joy.x * sensibilidade_stick * delta, -joy.y * sensibilidade_stick * delta * 0.75)


func _tem_animacao(nome: String) -> bool:
	return animador != null and animador.has_animation(nome)


func _atualizar_animacao(nome: String) -> void:
	if animador == null:
		return
	# Match exato primeiro: evita "SadIdle" capturar o pedido de "Idle".
	var chave := ""
	if animador.has_animation(nome):
		chave = nome
	else:
		for candidata in animador.get_animation_list():
			if String(candidata).to_lower().ends_with(nome.to_lower()):
				chave = candidata
				break
	if chave == "":
		return
	var animacao := animador.get_animation(chave)
	if nome == "Walk" or nome == "Run":
		animacao.loop_mode = Animation.LOOP_LINEAR
	elif nome == "Idle" or nome == "SadIdle":
		# Ping-pong no parado: vai e volta sem "salto" de emenda do loop.
		animacao.loop_mode = Animation.LOOP_PINGPONG
	else:
		animacao.loop_mode = Animation.LOOP_NONE
	var trocar := _animacao_atual != chave
	var repetir_pulo := (nome == "Jump" or nome == "WalkJump" or nome == "RunJump") and not animador.is_playing()
	if trocar or repetir_pulo:
		var blend := BLEND_TERRA
		if nome == "Jump" or nome == "WalkJump" or nome == "RunJump":
			blend = BLEND_PULO_SAIDA
		elif _animacao_atual == "Jump" or _animacao_atual == "WalkJump" or _animacao_atual == "RunJump":
			blend = BLEND_POUSO
		# Alternar Walk<->Run preserva a fase da passada em vez de
		# recomecar o ciclo (evita o "solavanco" ao segurar o correr).
		var manter_fase := (chave == "Walk" or chave == "Run") and (_animacao_atual == "Walk" or _animacao_atual == "Run")
		var fase := 0.0
		if manter_fase and animador.is_playing():
			var antiga := animador.get_animation(_animacao_atual)
			if antiga != null and antiga.length > 0.0 and animacao.length > 0.0:
				fase = fposmod(animador.get_current_animation_position() / antiga.length, 1.0)
		animador.play(chave, blend)
		if manter_fase:
			animador.seek(fase * animacao.length, true)
		_animacao_atual = chave


## Inicia a caminhada autônoma da cutscene em direção ao destino.
## O movimento real acontece em _physics_process para evitar corrida com o bloqueio.
func caminhar_cutscene(_delta: float, destino: Vector3) -> bool:
	if not _em_cutscene_caminhando:
		_em_cutscene_caminhando = true
		_destino_cutscene = destino
		_tempo_entre_passos = 0.0
	# Retorna se já chegou (o _physics_process vai limpar o estado).
	return not _em_cutscene_caminhando


## Para o personagem na pose de descanso no ponto final da cutscene.
func parar_cutscene(destino_final: Vector3 = Vector3.ZERO) -> void:
	_em_cutscene_caminhando = false
	_destino_cutscene = Vector3.ZERO
	if destino_final != Vector3.ZERO:
		global_position.x = destino_final.x
		global_position.z = destino_final.z
	velocity = Vector3.ZERO
	move_and_slide()
	_atualizar_animacao("Idle")
	if animador != null:
		animador.speed_scale = 1.0

