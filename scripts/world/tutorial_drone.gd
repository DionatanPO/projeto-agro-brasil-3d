extends Node3D
## TutorialDrone: laboratorio de teste fechado (sala retangular com paredes
## e teto) onde 10 portais luminosos flutuam em zigue-zague, alternando
## esquerda/direita e alto/baixo + timer de 90 s. O fim e so uma faixa
## iluminada no piso, sem arco. Entrada: janela com as teclas -> [Comecar]
## roda a CUTSCENE de abertura (camera propria passeando pelo laboratorio,
## legenda embaixo e "pular" em qualquer tecla/botao) -> liga o motor e
## inicia o timer. O cronometro so corre depois da cutscene.
## Esc abre pausa (Continuar / Sair). Fim: vitoria (tempo final) ou tempo
## esgotado (Tentar de novo / Voltar ao mapa). Na saida, o drone volta a
## posicao salva no mapa (o voo aqui nao contamina o save).

const CENA_MAPA := "res://world.tscn"
const CENA_LOADING := "res://scenes/ui/menus/loading.tscn"
const TEMPO_LIMITE := 90.0
const QTD_ARGOLAS := 10
const Z_ARGOLA_INI := -18.0
const Z_ARGOLA_FIM := -170.0
# Distancia extra entre o arco de chegada e a planta de pulverizacao,
# para nao ficarem coladas no final do percurso.
const DIST_PLANTA_APOS_CHEGADA := 45.0
const ALTURAS := [5.0, 10.5, 5.5, 12.0, 4.5, 9.0, 6.0, 11.0, 5.0, 8.0]
const POS_X := [0.0, -6.0, 6.0, -9.0, 9.0, -6.0, 6.0, -9.0, 9.0, 0.0]
const SPAWN := Vector3(0.0, 1.0, 8.0)
const RAIO_ARGOLA := 3.6

enum Estado { ENTRADA, INTRO, VOANDO, PAUSA, FIM }

## ---- Cutscene de abertura ------------------------------------------
## A camera da cutscene e criada em codigo e assume o lugar da camera do
## drone (make_current). Cada plano tem posicao e alvo no inicio e no fim:
## a camera desliza entre eles olhando para o alvo interpolado, com uma
## legenda embaixo e aviso de "pular" (qualquer tecla/botao/clique).
## O cronometro so comeca a correr quando a cutscene acaba.
const INTRO_CLAREAR := 0.7     # s: do preto para a imagem (comeco)
const INTRO_ESCURECER := 0.5   # s: para o preto antes de devolver o controle
const INTRO_VOLTA := 0.45      # s: do preto para a imagem, ja com o drone
## Planos: pos_ini, pos_fim, alvo_ini, alvo_fim, tempo (s) e legenda.
## Todos os pontos ficam DENTRO do laboratorio (x +-26, y ate 24, z de +20
## a -262), senao a camera olharia a sala por fora.
const CINEMATICA := [
	{
		"pos_ini": Vector3(0.0, 18.0, 16.0), "pos_fim": Vector3(0.0, 11.0, -2.0),
		"alvo_ini": Vector3(0.0, 6.0, -34.0), "alvo_fim": Vector3(0.0, 7.0, -70.0),
		"tempo": 2.8, "texto": "LABORATÓRIO DE VOO  •  DRONE AGRÍCOLA",
	},
	{
		"pos_ini": Vector3(0.0, 5.0, -8.0), "pos_fim": Vector3(0.0, 12.0, -62.0),
		"alvo_ini": Vector3(0.0, 5.0, -20.0), "alvo_fim": Vector3(0.0, 8.0, -110.0),
		"tempo": 3.0, "texto": "ATRAVESSE OS 10 PORTAIS, EM ORDEM, NO TEMPO",
	},
	{
		"pos_ini": Vector3(6.5, 3.8, -197.0), "pos_fim": Vector3(-1.5, 4.6, -208.0),
		"alvo_ini": Vector3(0.0, 1.5, -215.0), "alvo_fim": Vector3(0.0, 1.5, -215.0),
		"tempo": 2.6, "texto": "PULVERIZE A PLANTAÇÃO (F)",
	},
	{
		"pos_ini": Vector3(0.0, 7.0, -224.0), "pos_fim": Vector3(0.0, 10.0, -234.0),
		"alvo_ini": Vector3(0.0, 1.5, -240.0), "alvo_fim": Vector3(0.0, 2.5, -240.0),
		"tempo": 2.4, "texto": "E CRUZE A LINHA DE CHEGADA",
	},
	{
		"pos_ini": Vector3(0.0, 6.0, 20.0), "pos_fim": Vector3(0.0, 4.2, 14.5),
		"alvo_ini": Vector3(0.0, 2.5, 8.0), "alvo_fim": Vector3(0.0, 2.5, 6.0),
		"tempo": 2.2, "texto": "W/S e A/D VOAM  •  ESPAÇO SOBE, C DESCE",
	},
]

var _estado := Estado.ENTRADA
var _tempo := 0.0
var _indice := 0
var _aneis: Array[Dictionary] = []
var _marcador: MeshInstance3D
var _drone: CharacterBody3D
var _mat_futura: StandardMaterial3D
var _mat_atual: StandardMaterial3D
var _mat_feita: StandardMaterial3D
var _som_argola: AudioStreamPlayer
var _som_vitoria: AudioStreamPlayer
var _som_musica: AudioStreamPlayer

var _ui: CanvasLayer
var _scrim: ColorRect
var _hud_tempo: Label
var _hud_argolas: Label
var _jan_entrada: CenterContainer
var _jan_pausa: CenterContainer
var _jan_fim: CenterContainer
var _fim_titulo: Label
var _fim_texto: Label

# Cutscene de abertura (camera propria + legendas + fade + barras pretas).
var _camera_cine: Camera3D
var _hud_topo: HBoxContainer
var _intro_texto: Label
var _intro_dica: Label
var _intro_fade: ColorRect
var _intro_barras: Array[ColorRect] = []
var _intro_tempo := 0.0
var _intro_total := 0.0
var _intro_plano := -1

var _milharal: MultiMeshInstance3D
var _mat_pulverizacao: StandardMaterial3D
var _area_planta: Area3D
var _planta_pulverizada := false
var _progresso_pulverizacao := 0.0
var _lbl_pulverizar: Label
var _barra_pulverizar: ProgressBar
var _chegada_area: Area3D
var _chegada_liberada := false


func _ready() -> void:
	_montar_mundo()
	_criar_sons()
	_montar_ui()
	_configurar_musica()
	_drone = $DroneJogador as CharacterBody3D
	_drone.set("modo_tutorial", true)
	# Guarda a posicao do mapa para devolver na saida.
	if not SaveSystem.dados.has("posicao_drone_backup"):
		SaveSystem.dados["posicao_drone_backup"] = SaveSystem.dados.get("posicao_drone", [69.664, 11.197, 192.916])
	_drone.position = SPAWN
	_drone.velocity = Vector3.ZERO
	_drone.set("ligado", false)
	# Mostra o laboratorio atras da janela de entrada.
	var cam_drone := _drone.get("cam") as Camera3D
	if cam_drone != null:
		cam_drone.current = true
	_jan_entrada.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(evento: InputEvent) -> void:
	# Cutscene de abertura: qualquer tecla, botao ou clique pula para o fim
	# (uma folga de 0.4 s evita que o clique do [Comecar] ja pule tudo).
	if _estado == Estado.INTRO:
		if _intro_tempo >= 0.4 and _evento_pula(evento):
			_pular_intro()
			get_viewport().set_input_as_handled()
		return
	if evento.is_action_pressed("ui_cancel"):
		if _estado == Estado.VOANDO:
			pausar()
		elif _estado == Estado.PAUSA:
			continuar()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _estado == Estado.INTRO:
		_processar_intro(delta)
		return
	if _estado != Estado.VOANDO:
		return
	_tempo += delta
	_hud_tempo.text = _formatar_tempo(maxi(0, int(ceil(TEMPO_LIMITE - _tempo))))
	if _tempo >= TEMPO_LIMITE:
		_perder()
		return
	var t := Time.get_ticks_msec() / 1000.0
	for i in _aneis.size():
		var malha: MeshInstance3D = _aneis[i]["no"]
		if i == _indice:
			var s := 1.0 + 0.06 * sin(t * 5.0)
			malha.scale = Vector3(s, s, s)
		else:
			malha.scale = Vector3.ONE
	if _marcador != null and _indice < _aneis.size():
		var centro: Vector3 = _aneis[_indice]["centro"]
		_marcador.position = centro + Vector3(0.0, 5.6 + 0.4 * sin(t * 3.0), 0.0)

	# Ultima etapa: aguarda pulverizacao da planta apos todas as argolas.
	if _indice >= QTD_ARGOLAS and not _planta_pulverizada:
		if _drone != null and _area_planta != null:
			var distancia := _drone.position.distance_to(_area_planta.global_position)
			if distancia < 8.0:
				# Mostra instrucao de proximidade
				if _lbl_pulverizar != null:
					_lbl_pulverizar.visible = true
					if Input.is_action_pressed("pulverizar"):
						_lbl_pulverizar.text = "Pulverizando... %d%%" % int(_progresso_pulverizacao * 100)
						_lbl_pulverizar.add_theme_color_override("font_color", Color(0, 1, 0))
						# Efeito visual gradual: o milharal ganha um verde mais claro
						_progresso_pulverizacao = minf(_progresso_pulverizacao + delta * 0.5, 1.0)
						_atualizar_visual_pulverizacao()
						if _progresso_pulverizacao >= 1.0:
							_planta_pulverizada = true
							_chegada_liberada = true
							if _lbl_pulverizar != null:
								_lbl_pulverizar.text = "Plantação pulverizada! Voe até a linha de chegada."
								_lbl_pulverizar.add_theme_color_override("font_color", Color(0, 1, 0))
							if _barra_pulverizar != null:
								_barra_pulverizar.visible = false
							_som_vitoria.play()
							# Nao finaliza ainda: so apos atravessar a linha de chegada.
					else:
						_lbl_pulverizar.text = "Aproxime e aperte F para pulverizar"
						_lbl_pulverizar.add_theme_color_override("font_color", Color(1, 1, 0))
				if _barra_pulverizar != null:
					_barra_pulverizar.value = _progresso_pulverizacao
			elif Input.is_action_pressed("pulverizar"):
				# Sem label, ainda assim pulveriza
				_progresso_pulverizacao = minf(_progresso_pulverizacao + delta * 0.5, 1.0)
				_atualizar_visual_pulverizacao()
				if _progresso_pulverizacao >= 1.0:
					_planta_pulverizada = true
					_chegada_liberada = true
					if _barra_pulverizar != null:
						_barra_pulverizar.visible = false
					_som_vitoria.play()
					# Nao finaliza ainda: so apos atravessar a linha de chegada.
				if _barra_pulverizar != null:
					_barra_pulverizar.value = _progresso_pulverizacao
			else:
				# Longe da planta, esconde instrucao
				if _lbl_pulverizar != null:
					_lbl_pulverizar.visible = false

	# apos pulverizar a planta, o drone deve voar ate a linha de chegada
	elif _planta_pulverizada and _chegada_liberada:
		if _drone != null and _chegada_area != null:
			var distancia_chegada := _drone.position.distance_to(_chegada_area.global_position)
			if distancia_chegada < 12.0:
				if _lbl_pulverizar != null:
					_lbl_pulverizar.visible = true
					_lbl_pulverizar.text = "Atravesse a linha de chegada para finalizar!"
					_lbl_pulverizar.add_theme_color_override("font_color", Color(0, 1, 0))
			else:
				if _lbl_pulverizar != null:
					_lbl_pulverizar.visible = true
					_lbl_pulverizar.text = "Voe ate a linha de chegada (CHEGADA)"
					_lbl_pulverizar.add_theme_color_override("font_color", Color(1, 1, 0))


# ------------------------------------------------------------------
# Fluxo (metodos publicos para botoes e teste).

func comecar() -> void:
	if _estado != Estado.ENTRADA:
		return
	_jan_entrada.visible = false
	_scrim.visible = false
	_iniciar_intro()


# ------------------------------------------------------------------
# Cutscene de abertura: camera propria passeando pelo laboratorio com
# legendas; o drone fica desligado e congelado ate a cena terminar.

func _iniciar_intro() -> void:
	_estado = Estado.INTRO
	_intro_tempo = 0.0
	_intro_plano = -1
	_intro_total = 0.0
	for plano in CINEMATICA:
		_intro_total += float(plano["tempo"])
	if _hud_topo != null:
		_hud_topo.visible = false
	_drone.set("ligado", false)
	_congelar_drone(true)
	for barra in _intro_barras:
		barra.visible = true
	_intro_texto.text = ""
	_intro_texto.visible = true
	_intro_dica.visible = true
	_intro_fade.visible = true
	_intro_fade.color.a = 1.0
	# Camera da cutscene assume o lugar da camera do drone.
	_camera_cine = Camera3D.new()
	_camera_cine.name = "CameraCinematografica"
	_camera_cine.fov = 68.0
	_camera_cine.far = 400.0
	add_child(_camera_cine)
	_camera_cine.global_position = CINEMATICA[0]["pos_ini"]
	_camera_cine.make_current()
	if _som_musica != null and not _som_musica.playing:
		_som_musica.play()


func _processar_intro(delta: float) -> void:
	_intro_tempo += delta
	# Reta final: escurece e so entao devolve o controle ao jogador.
	if _intro_tempo >= _intro_total:
		_intro_fade.color.a = clampf((_intro_tempo - _intro_total) / INTRO_ESCURECER, 0.0, 1.0)
		if _intro_fade.color.a >= 1.0:
			_devolver_controle()
		return
	# Fade de abertura: sai do preto nos primeiros INTRO_CLAREAR segundos.
	_intro_fade.color.a = clampf(1.0 - _intro_tempo / INTRO_CLAREAR, 0.0, 1.0)
	# Localiza o plano atual e o progresso dentro dele (0..1).
	var acumulado := 0.0
	for i in CINEMATICA.size():
		var plano: Dictionary = CINEMATICA[i]
		var tempo := float(plano["tempo"])
		if _intro_tempo < acumulado + tempo:
			_aplicar_plano(plano, (_intro_tempo - acumulado) / tempo, i)
			return
		acumulado += tempo


func _aplicar_plano(plano: Dictionary, t: float, i: int) -> void:
	if _camera_cine == null:
		return
	# smoothstep deixa o movimento mais "cinema" (acelera e freia).
	var e := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var pos := (plano["pos_ini"] as Vector3).lerp(plano["pos_fim"] as Vector3, e)
	var alvo := (plano["alvo_ini"] as Vector3).lerp(plano["alvo_fim"] as Vector3, e)
	if pos.distance_to(alvo) > 0.5:
		_camera_cine.global_position = pos
		_camera_cine.look_at(alvo, Vector3.UP)
	if _intro_plano != i:
		_intro_plano = i
		_intro_texto.text = str(plano["texto"])


## Pular a cutscene: cai direto na transicao final (escurecer + devolver).
func _pular_intro() -> void:
	_intro_tempo = _intro_total


func _devolver_controle() -> void:
	_estado = Estado.VOANDO
	_intro_tempo = 0.0
	if _camera_cine != null:
		_camera_cine.queue_free()
		_camera_cine = null
	var cam_drone := _drone.get("cam") as Camera3D
	if cam_drone != null:
		cam_drone.make_current()
	if _hud_topo != null:
		_hud_topo.visible = true
	for barra in _intro_barras:
		barra.visible = false
	_intro_texto.visible = false
	_intro_dica.visible = false
	_hud_tempo.text = _formatar_tempo(int(TEMPO_LIMITE))
	_drone.set("ligado", true)
	_congelar_drone(false)
	# A vista do drone ja esta na tela por baixo do preto, que sobe suave.
	var tw := create_tween()
	tw.tween_property(_intro_fade, "color:a", 0.0, INTRO_VOLTA)
	tw.tween_callback(Callable(_intro_fade, "hide"))


## Qualquer tecla, botao de controle, clique ou toque pula a cutscene.
func _evento_pula(evento: InputEvent) -> bool:
	if evento is InputEventKey:
		return (evento as InputEventKey).pressed and not (evento as InputEventKey).echo
	if evento is InputEventMouseButton:
		return (evento as InputEventMouseButton).pressed
	if evento is InputEventJoypadButton:
		return (evento as InputEventJoypadButton).pressed
	if evento is InputEventScreenTouch:
		return (evento as InputEventScreenTouch).pressed
	return false


func pausar() -> void:
	if _estado != Estado.VOANDO:
		return
	_estado = Estado.PAUSA
	_congelar_drone(true)
	_jan_pausa.visible = true
	_scrim.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func continuar() -> void:
	if _estado != Estado.PAUSA:
		return
	_jan_pausa.visible = false
	_scrim.visible = false
	_congelar_drone(false)
	_estado = Estado.VOANDO


func tentar_de_novo() -> void:
	_jan_fim.visible = false
	_scrim.visible = false
	_tempo = 0.0
	_indice = 0
	_planta_pulverizada = false
	_chegada_liberada = false
	_chegada_area = null
	_progresso_pulverizacao = 0.0
	_atualizar_visual_pulverizacao()
	if _lbl_pulverizar != null:
		_lbl_pulverizar.visible = false
	if _barra_pulverizar != null:
		_barra_pulverizar.visible = false
		_barra_pulverizar.value = 0.0
	for i in _aneis.size():
		var malha: MeshInstance3D = _aneis[i]["no"]
		malha.material_override = _mat_atual if i == 0 else _mat_futura
		malha.scale = Vector3.ONE
	_hud_argolas.text = "Portais 0/%d" % QTD_ARGOLAS
	_hud_tempo.text = _formatar_tempo(int(TEMPO_LIMITE))
	_drone.position = SPAWN
	_drone.velocity = Vector3.ZERO
	_drone.set("ligado", true)
	_congelar_drone(false)
	_estado = Estado.VOANDO


var _saindo_tutorial := false


func sair_tutorial() -> void:
	if _saindo_tutorial:
		return
	_saindo_tutorial = true
	SaveSystem.dados["posicao_drone"] = SaveSystem.dados.get("posicao_drone_backup", [69.664, 11.197, 192.916])
	SaveSystem.dados.erase("posicao_drone_backup")
	SaveSystem.salvar()

	Loading.proxima_cena = CENA_MAPA
	Loading.titulo_carga = "Retornando à fazenda..."

	if _intro_fade != null:
		_intro_fade.visible = true
		_intro_fade.modulate.a = 0.0
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_intro_fade, "modulate:a", 1.0, 0.45)
		tw.tween_callback(func() -> void:
			get_tree().change_scene_to_file(CENA_LOADING)
		)
	else:
		get_tree().change_scene_to_file(CENA_LOADING)


# ------------------------------------------------------------------
# Regras.

func _ao_atravessar(corpo: Node3D, i: int) -> void:
	if _estado != Estado.VOANDO:
		return
	if i != _indice:
		return
	if not corpo.is_in_group("drone_jogador"):
		return
	var malha: MeshInstance3D = _aneis[i]["no"]
	malha.material_override = _mat_feita
	malha.scale = Vector3.ONE
	_indice += 1
	_hud_argolas.text = "Portais %d/%d" % [mini(_indice, QTD_ARGOLAS), QTD_ARGOLAS]
	if _indice >= QTD_ARGOLAS:
		if _som_vitoria != null:
			_som_vitoria.play()
		_exigir_pulverizacao()
	else:
		if _som_argola != null:
			_som_argola.play()
		var prox: MeshInstance3D = _aneis[_indice]["no"]
		prox.material_override = _mat_atual


func _ao_atravessar_chegada(corpo: Node3D) -> void:
	if _estado != Estado.VOANDO:
		return
	if not _chegada_liberada:
		return
	if not corpo.is_in_group("drone_jogador"):
		return
	# So finaliza apos pulverizar a planta e atravessar a linha de chegada.
	_vencer()


func _vencer() -> void:
	_estado = Estado.FIM
	SaveSystem.dados["tutorial_drone_concluido"] = true
	SaveSystem.dados["tutorial_drone_visto"] = true
	SaveSystem.salvar()
	_congelar_drone(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fim_titulo.text = "Tutorial concluido!"
	_fim_texto.text = "Voce cruzou os %d portais em %s." % [QTD_ARGOLAS, _formatar_tempo(int(_tempo))]
	_jan_fim.visible = true
	_scrim.visible = true


func _perder() -> void:
	_estado = Estado.FIM
	_congelar_drone(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fim_titulo.text = "Tempo esgotado!"
	_fim_texto.text = "Voce cruzou %d de %d portais. Tente de novo." % [mini(_indice, QTD_ARGOLAS), QTD_ARGOLAS]
	_jan_fim.visible = true
	_scrim.visible = true


func _congelar_drone(congelar: bool) -> void:
	if _drone == null:
		return
	_drone.set_physics_process(not congelar)
	_drone.set_process_unhandled_input(not congelar)
	if congelar:
		_drone.velocity = Vector3.ZERO


func _formatar_tempo(seg: int) -> String:
	return "%02d:%02d" % [floori(seg / 60.0), seg % 60]


# ------------------------------------------------------------------
# Cenario procedural.

func _montar_mundo() -> void:
	_mat_futura = _mat_argola(Color(0.55, 0.42, 0.10), Color(1.0, 0.75, 0.15), 0.4)
	_mat_atual = _mat_argola(Color(0.05, 0.45, 0.55), Color(0.2, 0.95, 1.0), 1.6)
	_mat_feita = _mat_argola(Color(0.08, 0.45, 0.12), Color(0.25, 1.0, 0.35), 1.2)
	_ambiente_lab()
	_laboratorio()
	for i in QTD_ARGOLAS:
		var z := lerpf(Z_ARGOLA_INI, Z_ARGOLA_FIM, float(i) / float(QTD_ARGOLAS - 1))
		_argola(i, Vector3(POS_X[i % POS_X.size()], ALTURAS[i % ALTURAS.size()], z))
	_arco_chegada()
	_montar_planta()
	_marcador = MeshInstance3D.new()
	var es := SphereMesh.new()
	es.radius = 0.5
	es.height = 1.0
	_marcador.mesh = es
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(1, 1, 1)
	mmat.emission_enabled = true
	mmat.emission = Color(0.4, 1.0, 1.0)
	mmat.emission_energy_multiplier = 2.0
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marcador.material_override = mmat
	_marcador.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marcador)


func _mat_argola(albedo: Color, emissao: Color, energia: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emissao
	m.emission_energy_multiplier = energia
	return m


## Sons de confirmacao 100% procedurais (sem arquivo externo).
## Argola normal: bipe duplo curto (880 -> 1318 Hz).
## Ultima argola: jingle de vitoria (660 -> 880 -> 1320 Hz).
func _criar_sons() -> void:
	_som_argola = AudioStreamPlayer.new()
	_som_argola.name = "SomArgola"
	_som_argola.stream = _gerar_sequencia([[880.0, 0.12], [1318.5, 0.20]])
	_som_argola.volume_db = -6.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_som_argola.bus = "Efeitos"
	add_child(_som_argola)
	_som_vitoria = AudioStreamPlayer.new()
	_som_vitoria.name = "SomVitoria"
	_som_vitoria.stream = _gerar_sequencia([[659.3, 0.14], [880.0, 0.14], [1318.5, 0.30]])
	_som_vitoria.volume_db = -4.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_som_vitoria.bus = "Efeitos"
	add_child(_som_vitoria)


## Gera um WAV com notas senoidais em sequencia.
## notas: Array de [frequencia_hz, duracao_seg]. Aplica fade in/out
## curto em cada nota para evitar estalos.
func _gerar_sequencia(notas: Array) -> AudioStreamWAV:
	var taxa := 22050
	var dados := PackedByteArray()
	for nota in notas:
		var freq := float(nota[0])
		var dur := float(nota[1])
		var n := int(taxa * dur)
		var inicio := dados.size()
		dados.resize(inicio + n * 2)
		var fade := mini(400, int(n / 4.0))
		for i in n:
			var t := float(i) / float(taxa)
			var env := 1.0
			if i < fade:
				env = float(i) / float(fade)
			elif i >= n - fade:
				env = float(n - 1 - i) / float(fade)
			# Fundamental + harmonico suave para soar como "confirmacao".
			var s := 0.7 * sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t)
			dados.encode_s16(inicio + i * 2, int(clampf(s * env * 0.6, -1.0, 1.0) * 32760.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = taxa
	wav.stereo = false
	wav.data = dados
	return wav


func _configurar_musica() -> void:
	_som_musica = AudioStreamPlayer.new()
	_som_musica.name = "SomMusica"
	_som_musica.stream = load("res://assets/audio/musicas/Engineered_Ascent.mp3")
	_som_musica.finished.connect(_reiniciar_musica)
	if AudioServer.get_bus_index("Musica") >= 0:
		_som_musica.bus = "Musica"
	# Volume control now handled by AudioConfig bus volume
	_som_musica.volume_db = 0.0  # No additional attenuation from player
	add_child(_som_musica)


func _reiniciar_musica() -> void:
	_som_musica.seek(0)
	_som_musica.play()


## Ambiente interno do laboratorio: fundo neutro e luz uniforme, sem ceu
## nem neblina (sala fechada nao tem horizonte).
func _ambiente_lab() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.16, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Sem sombra: parede e teto nao podem deixar o interior escuro.
	var luz_solar := DirectionalLight3D.new()
	luz_solar.rotation = Vector3(-0.9, -0.6, 0.0)
	luz_solar.light_color = Color(0.95, 0.97, 1.0)
	luz_solar.light_energy = 0.5
	luz_solar.shadow_enabled = false
	add_child(luz_solar)


## Sala retangular fechada (piso + 4 paredes + teto) com cara de laboratorio
## limpo: MESMA cor lisa no piso, paredes e teto (sem textura nenhuma) e
## tubos de luz no teto.
func _laboratorio() -> void:
	var raiz := Node3D.new()
	raiz.name = "Laboratorio"
	add_child(raiz)
	var x_lado := 26.0
	var z_ini := 20.0
	var z_fim := -262.0
	var comp := z_ini - z_fim
	var z_centro := (z_ini + z_fim) * 0.5
	var altura := 24.0

	# Laboratorio limpo: piso, paredes e teto na MESMA cor lisa (sem textura).
	var mat_lab := _mat_liso(Color(0.62, 0.65, 0.70))

	# Piso: topo em -0.2, no mesmo nivel do plano de colisao do chao.
	_caixa(raiz, "Piso", Vector3(x_lado * 2.0, 0.4, comp), Vector3(0, -0.4, z_centro), mat_lab)
	_caixa(raiz, "ParedeEsq", Vector3(0.6, altura, comp), Vector3(-x_lado - 0.3, altura * 0.5 - 0.2, z_centro), mat_lab)
	_caixa(raiz, "ParedeDir", Vector3(0.6, altura, comp), Vector3(x_lado + 0.3, altura * 0.5 - 0.2, z_centro), mat_lab)
	_caixa(raiz, "ParedeFrente", Vector3(x_lado * 2.0 + 1.2, altura, 0.6), Vector3(0, altura * 0.5 - 0.2, z_ini + 0.3), mat_lab)
	_caixa(raiz, "ParedeFundo", Vector3(x_lado * 2.0 + 1.2, altura, 0.6), Vector3(0, altura * 0.5 - 0.2, z_fim - 0.3), mat_lab)
	_caixa(raiz, "Teto", Vector3(x_lado * 2.0 + 1.2, 0.6, comp + 1.2), Vector3(0, altura + 0.3, z_centro), mat_lab)

	# Sem faixa de cor nas paredes: o laboratorio e todo da MESMA cor.
	# (Se quiser um acento de volta, e so reinserir o bloco de "faixa".)

	# Tubos fluorescentes no teto.
	var tubo := StandardMaterial3D.new()
	tubo.albedo_color = Color(0.95, 0.97, 1.0)
	tubo.emission_enabled = true
	tubo.emission = Color(0.95, 0.97, 1.0)
	tubo.emission_energy_multiplier = 2.0
	for x_tubo in [-15.0, 0.0, 15.0]:
		_caixa(raiz, "TuboLuz", Vector3(1.0, 0.12, comp - 20.0), Vector3(x_tubo, altura - 0.5, z_centro), tubo)
	# Luzes suaves espalhadas pelo corredor (bem espacadas para o teto e as
	# paredes ficarem iluminados por igual, sem cantos escuros).
	for z_luz in range(10, -262, -40):
		var luz := OmniLight3D.new()
		luz.light_color = Color(0.9, 0.94, 1.0)
		luz.light_energy = 0.6
		luz.omni_range = 70.0
		luz.position = Vector3(0, altura - 3.0, float(z_luz))
		raiz.add_child(luz)

	# Marca de largada pintada no piso + linha inicial clara.
	var marca := StandardMaterial3D.new()
	marca.albedo_color = Color(0.8, 0.83, 0.87)
	marca.roughness = 0.8
	_caixa(raiz, "MarcaLargada", Vector3(11.0, 0.06, 8.0), Vector3(0, -0.17, 8.0), marca)
	var linha := StandardMaterial3D.new()
	linha.albedo_color = Color(0.9, 0.93, 0.96)
	linha.emission_enabled = true
	linha.emission = Color(0.8, 0.9, 1.0)
	linha.emission_energy_multiplier = 0.8
	_caixa(raiz, "LinhaInicial", Vector3(14.0, 0.08, 0.4), Vector3(0, -0.16, 12.0), linha)

	# Colisao extra do piso.
	var corpo := StaticBody3D.new()
	corpo.name = "ColisaoPiso"
	raiz.add_child(corpo)
	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(x_lado * 2.0, 0.4, comp)
	col.shape = forma
	col.position = Vector3(0, -0.4, z_centro)
	corpo.add_child(col)


## Material liso do laboratorio: cor unica, sem textura nenhuma.
func _mat_liso(cor: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.roughness = 0.7
	return m


func _caixa(pai: Node3D, nome: String, tamanho: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nome
	var caixa := BoxMesh.new()
	caixa.size = tamanho
	mi.mesh = caixa
	mi.material_override = mat
	mi.position = pos
	pai.add_child(mi)
	return mi


## Portal do percurso: um ANEL redondo e luminoso, virado para o sentido do
## voo (o drone passa POR DENTRO dele). Recebe a cor de estado (atual /
## proxima / concluida) e pulsa para guiar o drone. Sem haste.
func _argola(i: int, centro: Vector3) -> void:
	var raiz := Node3D.new()
	raiz.name = "Portal%d" % (i + 1)
	raiz.position = centro
	add_child(raiz)
	var anel := MeshInstance3D.new()
	anel.name = "Anel"
	var toro := TorusMesh.new()
	toro.inner_radius = 3.4   # vao por onde o drone passa
	toro.outer_radius = 4.2   # espessura do aro
	toro.rings = 48
	toro.ring_segments = 12
	anel.mesh = toro
	# O torus nasce deitado no plano XZ; girar 90 graus poe o furo virado
	# para +-Z, que e o sentido do voo (o drone atravessa por dentro).
	anel.rotation.x = PI * 0.5
	anel.material_override = _mat_atual if i == 0 else _mat_futura
	raiz.add_child(anel)
	var area := Area3D.new()
	area.name = "Alvo"
	var col := CollisionShape3D.new()
	var esf := SphereShape3D.new()
	esf.radius = RAIO_ARGOLA
	col.shape = esf
	area.add_child(col)
	raiz.add_child(area)
	area.body_entered.connect(_ao_atravessar.bind(i))
	_aneis.append({"no": anel, "area": area, "centro": centro})


## Chegada: so uma faixa luminosa no piso + luz acesa acima dela.
## Sem estrutura de arco nem xadrez: o brilho marca onde parar.
## A Area3D de deteccao continua igual (so finaliza apos pulverizar).
func _arco_chegada() -> void:
	var raiz := Node3D.new()
	raiz.name = "Chegada"
	# A linha de chegada fica APOS a planta de pulverizacao.
	raiz.position = Vector3(0, 0, Z_ARGOLA_FIM - DIST_PLANTA_APOS_CHEGADA - 25.0)
	add_child(raiz)
	# Faixa clara no piso.
	var mat_faixa := StandardMaterial3D.new()
	mat_faixa.albedo_color = Color(0.9, 0.92, 0.95)
	mat_faixa.roughness = 0.5
	mat_faixa.emission_enabled = true
	mat_faixa.emission = Color(0.85, 0.95, 1.0)
	mat_faixa.emission_energy_multiplier = 1.2
	_caixa(raiz, "Faixa", Vector3(14, 0.06, 2.2), Vector3(0, -0.15, 0), mat_faixa)
	# Luz acesa sobre a area da chegada.
	var luz := OmniLight3D.new()
	luz.name = "LuzChegada"
	luz.light_color = Color(0.85, 0.95, 1.0)
	luz.light_energy = 1.6
	luz.omni_range = 16.0
	luz.position = Vector3(0, 4.0, 0)
	raiz.add_child(luz)
	var rotulo := Label3D.new()
	rotulo.text = "CHEGADA"
	rotulo.font_size = 128
	rotulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	rotulo.position = Vector3(0, 6.0, 0)
	raiz.add_child(rotulo)

	# Area de deteccao da linha de chegada (so funciona apos pulverizar a planta)
	var area := Area3D.new()
	area.name = "AlvoChegada"
	var col := CollisionShape3D.new()
	var esf := SphereShape3D.new()
	esf.radius = 12.0
	col.shape = esf
	area.add_child(col)
	raiz.add_child(area)
	area.body_entered.connect(_ao_atravessar_chegada)
	_chegada_area = area


func _montar_planta() -> void:
	# Plantacao no ponto de chegada, apos a ultima argola: um canteiro de
	# laboratorio com fileiras de milho (Corn_2) em cima. O drone deve
	# pulverizar para concluir o tutorial.
	var raiz := Node3D.new()
	raiz.name = "Planta"
	raiz.position = Vector3(0, 0, Z_ARGOLA_FIM - DIST_PLANTA_APOS_CHEGADA)
	add_child(raiz)

	# Canteiro de concreto com terra por cima (espécime do lab).
	var mat_canteiro := StandardMaterial3D.new()
	mat_canteiro.albedo_color = Color(0.42, 0.44, 0.48)
	mat_canteiro.roughness = 0.9
	_caixa(raiz, "Canteiro", Vector3(7, 1.0, 7), Vector3(0, 0.3, 0), mat_canteiro)
	var mat_terra := StandardMaterial3D.new()
	mat_terra.albedo_color = Color(0.25, 0.17, 0.11)
	mat_terra.roughness = 1.0
	_caixa(raiz, "Terra", Vector3(6.2, 0.2, 6.2), Vector3(0, 0.85, 0), mat_terra)

	# Fileiras de milho em cima da terra (topo da terra = y 0.95).
	_montar_milharal(raiz, 0.95)

	# Area de deteccao de pulverizacao
	_area_planta = Area3D.new()
	_area_planta.name = "AreaPulverizacao"
	var col := CollisionShape3D.new()
	var esf := SphereShape3D.new()
	esf.radius = 6.0
	col.shape = esf
	_area_planta.add_child(col)
	raiz.add_child(_area_planta)


## Milharal do canteiro: fileiras de Corn_2 no mesmo estilo da plantacao do
## mapa (giro e escala aleatorios com semente fixa). Tudo num MultiMesh
## (1 draw call) e com um material_overlay que "molha"/clareia conforme a
## pulverizacao avanca.
func _montar_milharal(pai: Node3D, base_y: float) -> void:
	var dados := _extrair_malha(preload("res://assets/models/Corn_2.fbx"))
	if dados.is_empty():
		push_error("TutorialDrone: malha do milho (Corn_2) nao encontrada.")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var lista: Array[Transform3D] = []
	# 7 colunas x 5 fileiras dentro dos 6,2 x 6,2 m de terra (bem cheio,
	# como um milharal de verdade).
	for fileira in 5:
		for coluna in 7:
			var x := -2.85 + coluna * 0.95 + rng.randf_range(-0.14, 0.14)
			var z := -2.3 + fileira * 1.15 + rng.randf_range(-0.14, 0.14)
			var s := rng.randf_range(1.0, 1.45)
			var base := Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s)),
				Vector3(x, base_y, z)
			)
			lista.append(base * (dados["transform"] as Transform3D))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dados["mesh"]
	mm.instance_count = lista.size()
	for i in lista.size():
		mm.set_instance_transform(i, lista[i])
	_milharal = MultiMeshInstance3D.new()
	_milharal.name = "Milharal"
	_milharal.multimesh = mm
	_milharal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat_pulverizacao = StandardMaterial3D.new()
	_mat_pulverizacao.albedo_color = Color(0.62, 1.0, 0.62, 0.0)
	_mat_pulverizacao.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_pulverizacao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_pulverizacao.cull_mode = BaseMaterial3D.CULL_DISABLED
	_milharal.material_overlay = _mat_pulverizacao
	pai.add_child(_milharal)


## Extrai a primeira malha de um .fbx (mesmo truque da plantacao do mapa).
func _extrair_malha(pack: PackedScene) -> Dictionary:
	var tmp := (pack as PackedScene).instantiate() as Node
	var achados := tmp.find_children("*", "MeshInstance3D", true, false)
	var dados := {}
	if achados.size() > 0:
		var instancia := achados[0] as MeshInstance3D
		dados = {"mesh": instancia.mesh, "transform": instancia.transform}
	tmp.free()
	return dados


## Realce verde do milharal: 0 = seco, 1 = recem-pulverizado.
func _atualizar_visual_pulverizacao() -> void:
	if _mat_pulverizacao == null:
		return
	_mat_pulverizacao.albedo_color.a = 0.45 * clampf(_progresso_pulverizacao, 0.0, 1.0)


func _exigir_pulverizacao() -> void:
	# Mostra instrucao na tela para pulverizar a planta.
	if _lbl_pulverizar == null:
		_lbl_pulverizar = Label.new()
		_lbl_pulverizar.name = "InstrucaoPulverizar"
		_lbl_pulverizar.text = "Pulverize a plantação! (F)"
		_lbl_pulverizar.add_theme_font_size_override("font_size", 18)
		_lbl_pulverizar.add_theme_color_override("font_color", Color(1, 1, 0))
		_lbl_pulverizar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl_pulverizar.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_lbl_pulverizar.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_lbl_pulverizar.position = Vector2(0, 100)
		_ui.add_child(_lbl_pulverizar)
	_lbl_pulverizar.visible = true

	# Barrinha de progresso da pulverizacao
	if _barra_pulverizar == null:
		_barra_pulverizar = ProgressBar.new()
		_barra_pulverizar.name = "BarraPulverizacao"
		_barra_pulverizar.min_value = 0.0
		_barra_pulverizar.max_value = 1.0
		_barra_pulverizar.value = 0.0
		_barra_pulverizar.custom_minimum_size = Vector2(300, 24)
		_barra_pulverizar.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_barra_pulverizar.position = Vector2(0, 140)
		_ui.add_child(_barra_pulverizar)
	_barra_pulverizar.visible = true
	_barra_pulverizar.value = _progresso_pulverizacao

func _montar_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UITutorial"
	_ui.layer = 5
	add_child(_ui)
	# Fundo escurecido igual ao do Diario (Tab) / Dialogo do HUD.
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(0.04, 0.07, 0.05, 0.76)
	_ui.add_child(_scrim)
	# Pílulas do topo (tempo + argolas) no padrão AgroUITheme.
	_hud_topo = HBoxContainer.new()
	_hud_topo.name = "Topo"
	_hud_topo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud_topo.position = Vector2(-170, 12)
	_hud_topo.custom_minimum_size = Vector2(340, 0)
	_hud_topo.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_topo.add_theme_constant_override("separation", 10)
	_ui.add_child(_hud_topo)
	_hud_tempo = Label.new()
	_hud_tempo.name = "Tempo"
	var pil_tempo := _pildora_hud(_hud_tempo, 30)
	_hud_topo.add_child(pil_tempo)
	_hud_argolas = Label.new()
	_hud_argolas.name = "Argolas"
	var pil_argolas := _pildora_hud(_hud_argolas, 15)
	_hud_topo.add_child(pil_argolas)
	_hud_argolas.text = "Portais 0/%d" % QTD_ARGOLAS
	_hud_tempo.text = _formatar_tempo(int(TEMPO_LIMITE))
	_jan_entrada = _janela("Tutorial do Drone", "TREINAMENTO  •  DRONE AGRICOLA")
	_jan_entrada.name = "JanEntrada"
	(_jan_entrada.get_node("Painel/Inset/Conteudo/Texto") as Label).text = _texto_controles()
	(_jan_entrada.get_node("Painel/Inset/Conteudo/Comecar") as Button).pressed.connect(comecar)
	_jan_pausa = _janela("Pausado", "PAUSADO")
	_jan_pausa.name = "JanPausa"
	(_jan_pausa.get_node("Painel/Inset/Conteudo/Texto") as Label).text = "Respire! O cronometro esta parado."
	(_jan_pausa.get_node("Painel/Inset/Conteudo/Comecar") as Button).text = "Continuar"
	(_jan_pausa.get_node("Painel/Inset/Conteudo/Comecar") as Button).pressed.connect(continuar)
	var sair2 := Button.new()
	sair2.name = "SairTutorial"
	sair2.text = "Sair do tutorial"
	sair2.custom_minimum_size = Vector2(0, 48)
	sair2.pressed.connect(sair_tutorial)
	(_jan_pausa.get_node("Painel/Inset/Conteudo") as VBoxContainer).add_child(sair2)
	AgroUITheme.style_secondary_button(sair2)
	_jan_fim = _janela("Fim", "RESULTADO")
	_jan_fim.name = "JanFim"
	_fim_titulo = (_jan_fim.get_node("Painel/Inset/Conteudo/Titulo") as Label)
	_fim_texto = (_jan_fim.get_node("Painel/Inset/Conteudo/Texto") as Label)
	(_jan_fim.get_node("Painel/Inset/Conteudo/Comecar") as Button).text = "Tentar de novo"
	(_jan_fim.get_node("Painel/Inset/Conteudo/Comecar") as Button).pressed.connect(tentar_de_novo)
	var voltar := Button.new()
	voltar.name = "VoltarMapa"
	voltar.text = "Voltar ao mapa"
	voltar.custom_minimum_size = Vector2(0, 48)
	voltar.pressed.connect(sair_tutorial)
	(_jan_fim.get_node("Painel/Inset/Conteudo") as VBoxContainer).add_child(voltar)
	AgroUITheme.style_secondary_button(voltar)
	_montar_ui_cutscene()


## Elementos da cutscene de abertura, desenhados por cima das janelas:
## barras pretas de cinema, legenda branca sobre a barra de baixo e aviso
## de "pular" sobre a barra de cima. O fade preto entra POR ÚLTIMO para
## cobrir todo o resto.
func _montar_ui_cutscene() -> void:
	var barra_topo := ColorRect.new()
	barra_topo.name = "BarraCineTopo"
	barra_topo.color = Color(0, 0, 0, 1)
	barra_topo.anchor_right = 1.0
	barra_topo.anchor_bottom = 0.11
	barra_topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barra_topo.visible = false
	_ui.add_child(barra_topo)
	_intro_barras.append(barra_topo)

	var barra_baixo := ColorRect.new()
	barra_baixo.name = "BarraCineBaixo"
	barra_baixo.color = Color(0, 0, 0, 1)
	barra_baixo.anchor_top = 0.89
	barra_baixo.anchor_right = 1.0
	barra_baixo.anchor_bottom = 1.0
	barra_baixo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barra_baixo.visible = false
	_ui.add_child(barra_baixo)
	_intro_barras.append(barra_baixo)

	# Legenda: fonte branca direto sobre a barra preta de baixo (sem pílula).
	_intro_texto = Label.new()
	_intro_texto.name = "LegendaCine"
	_intro_texto.text = ""
	_intro_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_texto.add_theme_font_size_override("font_size", 22)
	_intro_texto.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_intro_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_texto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_texto.anchor_top = 0.89
	_intro_texto.anchor_right = 1.0
	_intro_texto.anchor_bottom = 1.0
	_intro_texto.offset_left = 40.0
	_intro_texto.offset_right = -40.0
	_intro_texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_texto.visible = false
	_ui.add_child(_intro_texto)

	# Aviso de como pular, alinhado à direita sobre a barra preta de cima.
	_intro_dica = Label.new()
	_intro_dica.name = "DicaCine"
	_intro_dica.text = "Pular: qualquer tecla, botão ou clique"
	_intro_dica.add_theme_font_size_override("font_size", 13)
	_intro_dica.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	_intro_dica.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_intro_dica.add_theme_constant_override("outline_size", 5)
	_intro_dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_intro_dica.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_intro_dica.offset_top = 20.0
	_intro_dica.offset_bottom = 44.0
	_intro_dica.offset_right = -26.0
	_intro_dica.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_dica.visible = false
	_ui.add_child(_intro_dica)

	_intro_fade = ColorRect.new()
	_intro_fade.name = "FadeCine"
	_intro_fade.color = Color(0, 0, 0, 1)
	_intro_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_fade.visible = false
	_ui.add_child(_intro_fade)


## Pílula do HUD (tempo / argolas): PanelContainer branco do AgroUITheme.
func _pildora_hud(rotulo: Label, fonte: int) -> PanelContainer:
	var pil := PanelContainer.new()
	AgroUITheme.style_panel(pil)
	rotulo.add_theme_font_size_override("font_size", fonte)
	rotulo.add_theme_color_override("font_color", AgroUITheme.INK)
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pil.add_child(rotulo)
	return pil


func _texto_controles() -> String:
	return "Atravesse os %d portais em ordem antes do tempo acabar!\n\nW / S — frente e re   •   A / D — lados\nEspaco — subir   •   C — descer\nShift — turbo   •   L — liga/desliga o motor\nMouse — olhar (clique captura a mira)" % QTD_ARGOLAS


## Janela no mesmo padrao do Diario/Dialogo do HUD:
## Scrim + PanelContainer do AgroUITheme, selo pequeno, titulo e
## botao principal verde (secundarios saem brancos via style_*).
func _janela(titulo: String, selo: String) -> CenterContainer:
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.visible = false
	_ui.add_child(centro)
	AgroUITheme.apply_to(centro)
	var painel := PanelContainer.new()
	painel.name = "Painel"
	painel.custom_minimum_size = Vector2(420, 0)
	AgroUITheme.style_panel(painel)
	centro.add_child(painel)
	var margem := MarginContainer.new()
	margem.name = "Inset"
	margem.add_theme_constant_override("margin_left", 20)
	margem.add_theme_constant_override("margin_right", 20)
	margem.add_theme_constant_override("margin_top", 17)
	margem.add_theme_constant_override("margin_bottom", 17)
	painel.add_child(margem)
	var coluna := VBoxContainer.new()
	coluna.name = "Conteudo"
	coluna.add_theme_constant_override("separation", 10)
	margem.add_child(coluna)
	var selo_lbl := Label.new()
	selo_lbl.name = "Selo"
	selo_lbl.text = selo
	selo_lbl.add_theme_font_size_override("font_size", 11)
	selo_lbl.add_theme_color_override("font_color", AgroUITheme.MUTED_INK)
	selo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(selo_lbl)
	var tit := Label.new()
	tit.name = "Titulo"
	tit.text = titulo
	tit.add_theme_font_size_override("font_size", 20)
	tit.add_theme_color_override("font_color", AgroUITheme.INK)
	tit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(tit)
	var texto := Label.new()
	texto.name = "Texto"
	texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texto.add_theme_font_size_override("font_size", 13)
	texto.add_theme_color_override("font_color", AgroUITheme.INK)
	texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(texto)
	var btn := Button.new()
	btn.name = "Comecar"
	btn.text = "Comecar"
	btn.custom_minimum_size = Vector2(0, 54)
	coluna.add_child(btn)
	AgroUITheme.style_primary_button(btn)
	return centro
