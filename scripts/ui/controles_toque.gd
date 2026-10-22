extends CanvasLayer
## Controles de toque para celular/tablet.
##
## - Joystick virtual (movimento analogico) na esquerda.
## - Botoes de acao na direita.
## - Arrastar o dedo fora dos controles gira a camera (tratado nos scripts
##   do jogador via InputEventScreenDrag).
##
## Os controles so aparecem quando a deteccao indica celular/tablet ou quando
## o jogador escolhe "Sempre" em Configuracoes > Controles.
## Toda a entrada e enviada pelo InputMap (InputEventAction), entao os scripts
## de gameplay existentes nao precisam saber que existe toque.

const MODO_AUTO := "auto"
const MODO_SEMPRE := "sempre"
const MODO_NUNCA := "nunca"

const RAIO_JOYSTICK := 85.0
const ZONA_MORTA := 0.18
const DURACAO_TOQUE := 0.09

const COR_BASE := Color(0.05, 0.07, 0.06, 0.34)
const COR_BORDA := Color(1, 1, 1, 0.35)
const COR_ACCENT := Color("#39c47a")
const COR_ACCENT_PRESS := Color("#2e9e63")

## Acoes que ficam "seguradas" enquanto o dedo esta no botao.
const ACOES_SEGURAR := ["pular", "descer", "correr", "interagir", "pulverizar"]


var _raiz: Control
var _joystick: Control
var _knob: Panel
var _botoes: HBoxContainer
var _zonas: Array[Dictionary] = []
var _acoes_ativas: Dictionary = {}
var _toques: Dictionary = {}
var _joy_indice := -1
var _reafirmar: Dictionary = {}


func _ready() -> void:
	layer = 90
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Precisa rodar antes dos scripts do jogador no frame de fisica, para que
	# Input.is_action_just_pressed() enxergue o toque como uma tecla de verdade.
	process_physics_priority = -10000
	_montar()
	_aplicar_visibilidade()


func _physics_process(_delta: float) -> void:
	if _reafirmar.is_empty():
		return
	for acao in _reafirmar.keys():
		Input.action_press(str(acao), float(_reafirmar[acao]))
	_reafirmar.clear()


func _process(_delta: float) -> void:
	_aplicar_visibilidade()


func _exit_tree() -> void:
	_soltar_tudo()


# ------------------------------------------------------------------- montagem

func _montar() -> void:
	_raiz = Control.new()
	_raiz.name = "Raiz"
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_montar_joystick()
	_montar_botoes()
	_reposicionar.call_deferred()
	get_viewport().size_changed.connect(_reposicionar)


## Reaplica as ancoras depois que o layout estabilizou (e ao girar a tela).
func _reposicionar() -> void:
	if _raiz == null:
		return
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _joystick != null:
		_posicionar_joystick()
	if _botoes != null:
		_botoes.set_anchors_and_offsets_preset(
			Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 26
		)
	_centralizar_knob()


func _montar_joystick() -> void:
	var lado := RAIO_JOYSTICK * 2.0
	_joystick = Control.new()
	_joystick.name = "Joystick"
	_joystick.custom_minimum_size = Vector2(lado, lado)
	_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_joystick)
	_posicionar_joystick()

	var base := Panel.new()
	base.name = "Base"
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick.add_child(base)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_theme_stylebox_override(
		"panel", _estilo_redondo(COR_BASE, COR_BORDA, 2, int(RAIO_JOYSTICK))
	)

	_knob = Panel.new()
	_knob.name = "Knob"
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.size = Vector2(64, 64)
	_knob.add_theme_stylebox_override(
		"panel", _estilo_redondo(Color(COR_ACCENT, 0.9), Color(1, 1, 1, 0.6), 2, 32)
	)
	_joystick.add_child(_knob)


## O preset MINSIZE nao serve para um Control simples (minimo interno = 0),
## entao as ancoras do joystick sao calculadas na mao.
func _posicionar_joystick() -> void:
	if _joystick == null:
		return
	var lado := RAIO_JOYSTICK * 2.0
	_joystick.anchor_left = 0.0
	_joystick.anchor_top = 1.0
	_joystick.anchor_right = 0.0
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 26.0
	_joystick.offset_right = 26.0 + lado
	_joystick.offset_top = -26.0 - lado
	_joystick.offset_bottom = -26.0


func _montar_botoes() -> void:
	var linha := HBoxContainer.new()
	linha.name = "Botoes"
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linha.add_theme_constant_override("separation", 14)
	_raiz.add_child(linha)
	linha.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 26
	)
	_botoes = linha

	var col_esq := VBoxContainer.new()
	col_esq.name = "ColunaEsquerda"
	col_esq.alignment = BoxContainer.ALIGNMENT_END
	col_esq.add_theme_constant_override("separation", 12)
	col_esq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linha.add_child(col_esq)

	var col_dir := VBoxContainer.new()
	col_dir.name = "ColunaDireita"
	col_dir.alignment = BoxContainer.ALIGNMENT_END
	col_dir.add_theme_constant_override("separation", 12)
	col_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linha.add_child(col_dir)

	# Coluna esquerda: acoes secundarias (segurar).
	_criar_botao(col_esq, "SPRAY", "pulverizar", 64)
	_criar_botao(col_esq, "CORRER", "correr", 64)
	_criar_botao(col_esq, "DESCER", "descer", 64)

	# Coluna direita: atalhos pequenos em cima, acoes principais embaixo.
	var topo := HBoxContainer.new()
	topo.name = "Atalhos"
	topo.add_theme_constant_override("separation", 10)
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_dir.add_child(topo)
	_criar_botao(topo, "DIARIO", "diario", 54)
	_criar_botao(topo, "MOTOR", "ligar_motor", 54)

	_criar_botao(col_dir, "ACAO", "interagir", 78)
	_criar_botao(col_dir, "PULAR", "pular", 78)

	# Garante o alinhamento a direita das colunas.
	for coluna in [col_esq, col_dir]:
		for filho in coluna.get_children():
			if filho is Control:
				(filho as Control).size_flags_horizontal = Control.SIZE_SHRINK_END


func _criar_botao(
	pai: Control, texto: String, acao: String, tamanho: int
) -> void:
	var botao := Button.new()
	botao.name = "Botao" + texto.capitalize().replace(" ", "")
	botao.text = texto
	botao.focus_mode = Control.FOCUS_NONE
	botao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	botao.custom_minimum_size = Vector2(tamanho, tamanho)
	botao.size_flags_horizontal = Control.SIZE_SHRINK_END
	botao.add_theme_font_size_override("font_size", 12 if tamanho < 70 else 14)
	botao.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	botao.add_theme_color_override("font_hover_color", Color.WHITE)
	botao.add_theme_color_override("font_pressed_color", Color.WHITE)

	var raio := int(tamanho * 0.5)
	var normal := _estilo_redondo(COR_BASE, COR_BORDA, 2, raio)
	var pressionado := _estilo_redondo(
		Color(COR_ACCENT_PRESS, 0.92), Color(1, 1, 1, 0.7), 2, raio
	)
	botao.add_theme_stylebox_override("normal", normal)
	botao.add_theme_stylebox_override("hover", normal)
	botao.add_theme_stylebox_override("pressed", pressionado)
	botao.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pai.add_child(botao)

	_zonas.append({
		"no": botao,
		"acao": acao,
		"segurar": ACOES_SEGURAR.has(acao),
	})


func _estilo_redondo(fundo: Color, borda: Color, largura: int, raio: int) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = fundo
	estilo.border_color = borda
	estilo.set_border_width_all(largura)
	estilo.set_corner_radius_all(raio)
	return estilo


# ------------------------------------------------------------- mostrar/ocultar

func _aplicar_visibilidade() -> void:
	var mostrar := _deve_mostrar() and not get_tree().paused
	if visible == mostrar:
		return
	visible = mostrar
	if not mostrar:
		_soltar_tudo()


func _deve_mostrar() -> bool:
	match str(SaveSystem.dados.get("controles_toque", MODO_AUTO)):
		MODO_SEMPRE:
			return true
		MODO_NUNCA:
			return false
		_:
			return Dispositivo.movel()


# ------------------------------------------------------------------- entrada

func _input(evento: InputEvent) -> void:
	if not visible:
		return

	if evento is InputEventScreenTouch:
		var toque := evento as InputEventScreenTouch
		if toque.pressed:
			_inicio_toque(toque.index, toque.position)
		else:
			_fim_toque(toque.index)
		return

	if evento is InputEventScreenDrag:
		var arrasto := evento as InputEventScreenDrag
		_mover_toque(arrasto.index, arrasto.position)


func _inicio_toque(indice: int, posicao: Vector2) -> void:
	if _joy_indice == -1 and _joystick.get_global_rect().has_point(posicao):
		_joy_indice = indice
		_toques[indice] = "joystick"
		_atualizar_joystick(posicao)
		get_viewport().set_input_as_handled()
		return

	for zona in _zonas:
		if _toques.values().has(zona):
			continue
		var controle: Button = zona["no"]
		if controle.get_global_rect().has_point(posicao):
			_toques[indice] = zona
			_pressionar(zona)
			get_viewport().set_input_as_handled()
			return


func _fim_toque(indice: int) -> void:
	if indice == _joy_indice:
		_joy_indice = -1
		_reiniciar_joystick()
		_toques.erase(indice)
		get_viewport().set_input_as_handled()
		return

	if _toques.has(indice):
		var zona: Dictionary = _toques[indice]
		_toques.erase(indice)
		_soltar_zona(zona)
		get_viewport().set_input_as_handled()


func _mover_toque(indice: int, posicao: Vector2) -> void:
	if indice == _joy_indice:
		_atualizar_joystick(posicao)
		get_viewport().set_input_as_handled()


# -------------------------------------------------------------------- joystick

func _atualizar_joystick(posicao: Vector2) -> void:
	var centro := _joystick.get_global_rect().get_center()
	var delta := posicao - centro

	var limite := _joystick.size.x * 0.5 - _knob.size.x * 0.5
	if limite <= 1.0:
		limite = RAIO_JOYSTICK * 0.6
	if delta.length() > limite:
		delta = delta.normalized() * limite

	_knob.position = (_joystick.size - _knob.size) * 0.5 + delta

	var vetor := delta / limite
	if vetor.length() < ZONA_MORTA:
		vetor = Vector2.ZERO
	_aplicar_vetor(vetor)


func _reiniciar_joystick() -> void:
	_centralizar_knob()
	_aplicar_vetor(Vector2.ZERO)


func _centralizar_knob() -> void:
	if _joystick != null and _knob != null:
		_knob.position = (_joystick.size - _knob.size) * 0.5


## Converte o vetor do joystick (x direita, y baixo) nas acoes do jogo.
func _aplicar_vetor(vetor: Vector2) -> void:
	_definir_acao("mover_dir", maxf(0.0, vetor.x))
	_definir_acao("mover_esq", maxf(0.0, -vetor.x))
	_definir_acao("mover_tras", maxf(0.0, vetor.y))
	_definir_acao("mover_frente", maxf(0.0, -vetor.y))


# --------------------------------------------------------------------- acoes

func _pressionar(zona: Dictionary) -> void:
	var botao: Button = zona["no"]
	botao.modulate = Color(1.45, 1.45, 1.45, 1.0)

	if bool(zona["segurar"]):
		_definir_acao(str(zona["acao"]), 1.0)
	else:
		_pulsar(str(zona["acao"]))


func _soltar_zona(zona: Dictionary) -> void:
	var botao: Button = zona["no"]
	botao.modulate = Color.WHITE
	if bool(zona["segurar"]):
		_remover_acao(str(zona["acao"]))


func _definir_acao(acao: String, forca: float) -> void:
	if forca > 0.0:
		_enviar_acao(acao, true, forca)
		_acoes_ativas[acao] = true
	elif _acoes_ativas.has(acao):
		_remover_acao(acao)


func _remover_acao(acao: String) -> void:
	if not _acoes_ativas.has(acao):
		return
	_enviar_acao(acao, false, 0.0)
	_acoes_ativas.erase(acao)


## Toque curto: pressiona e solta logo em seguida (para is_action_just_pressed).
func _pulsar(acao: String) -> void:
	_enviar_acao(acao, true, 1.0)
	_acoes_ativas[acao] = true
	_remover_acao_depois(acao)


func _remover_acao_depois(acao: String) -> void:
	await get_tree().create_timer(DURACAO_TOQUE, true).timeout
	_remover_acao(acao)


## Envia um InputEventAction de verdade: alem de atualizar Input.is_action_*,
## tambem chega em _unhandled_input (varios scripts usam evento.is_action_pressed).
func _enviar_acao(acao: String, pressionada: bool, forca: float) -> void:
	var evento := InputEventAction.new()
	evento.action = acao
	evento.pressed = pressionada
	evento.strength = forca
	Input.parse_input_event(evento)
	if pressionada:
		# Reaplica no proximo frame de fisica (ver _physics_process).
		_reafirmar[acao] = forca
	else:
		_reafirmar.erase(acao)
		Input.action_release(acao)


func _soltar_tudo() -> void:
	for acao in _acoes_ativas.keys():
		_enviar_acao(str(acao), false, 0.0)
	_acoes_ativas.clear()
	_toques.clear()
	_joy_indice = -1
	for zona in _zonas:
		var botao: Button = zona["no"]
		botao.modulate = Color.WHITE
	_centralizar_knob()
