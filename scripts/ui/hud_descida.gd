extends CanvasLayer
## HUD da descida do Pico da Nebulosa: distancia, velocidade, tempo,
## contagem inicial, pausa e tela de chegada.

signal pausa_alternada(pausado: bool)
signal pediu_reiniciar
signal pediu_sair

const VERDE := Color(0.22, 0.92, 0.48)
const VERDE_ESCURO := Color(0.10, 0.62, 0.30)
const TINTA := Color(0.95, 0.98, 0.96)
const APAGADO := Color(0.68, 0.80, 0.72, 0.80)

var _pausado := false
var _fim := false
var _anéis := 0

var _distancia: Label
var _velocidade: Label
var _tempo: Label
var _recorde: Label
var _barra_vel: ProgressBar
var _progresso: ProgressBar
var _contagem: Label
var _flash: ColorRect
var _label_anel: Label
var _painel_pausa: Control
var _painel_fim: PanelContainer
var _fim_stats: Label
var _fim_xp: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_construir()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _construir() -> void:
	var raiz := Control.new()
	raiz.name = "Raiz"
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(raiz)

	# Barra de progresso ate a meta (linha fina no topo).
	_progresso = ProgressBar.new()
	_progresso.name = "Progresso"
	_progresso.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_progresso.offset_left = 18.0
	_progresso.offset_right = -18.0
	_progresso.offset_top = 14.0
	_progresso.offset_bottom = 20.0
	_progresso.show_percentage = false
	_progresso.max_value = 100.0
	_progresso.add_theme_stylebox_override("background", _caixa(Color(0.0, 0.0, 0.0, 0.42), 3))
	_progresso.add_theme_stylebox_override("fill", _caixa(VERDE, 3))
	raiz.add_child(_progresso)

	# Painel do titulo (canto superior esquerdo).
	var painel_titulo := PanelContainer.new()
	painel_titulo.name = "Titulo"
	painel_titulo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	painel_titulo.offset_left = 26.0
	painel_titulo.offset_top = 40.0
	painel_titulo.offset_right = 306.0
	painel_titulo.offset_bottom = 152.0
	painel_titulo.add_theme_stylebox_override("panel", _painel_estilo())
	raiz.add_child(painel_titulo)
	var col_titulo := VBoxContainer.new()
	col_titulo.add_theme_constant_override("separation", -2)
	painel_titulo.add_child(col_titulo)
	col_titulo.add_child(_rotulo("PICO DA NEBULOSA", 12, VERDE))
	col_titulo.add_child(_rotulo("DESCIDA DE SKATE", 22, TINTA))
	col_titulo.add_child(_rotulo("Desça até a base sem perder o embalo.", 11, APAGADO))

	# Distancia (canto superior direito).
	var painel_dist := PanelContainer.new()
	painel_dist.name = "Distancia"
	painel_dist.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	painel_dist.offset_left = -250.0
	painel_dist.offset_top = 40.0
	painel_dist.offset_right = -26.0
	painel_dist.offset_bottom = 150.0
	painel_dist.add_theme_stylebox_override("panel", _painel_estilo())
	raiz.add_child(painel_dist)
	var col_dist := VBoxContainer.new()
	col_dist.alignment = BoxContainer.ALIGNMENT_END
	col_dist.add_theme_constant_override("separation", -4)
	painel_dist.add_child(col_dist)
	var rot_dist := _rotulo("DISTÂNCIA", 11, APAGADO)
	rot_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col_dist.add_child(rot_dist)
	_distancia = _rotulo("0 m", 40, TINTA)
	_distancia.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col_dist.add_child(_distancia)
	_recorde = _rotulo("Recorde: 0 m", 11, VERDE)
	_recorde.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col_dist.add_child(_recorde)

	# Tempo (logo abaixo do titulo).
	_tempo = _rotulo("00:00.0", 16, TINTA)
	_tempo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tempo.offset_left = 28.0
	_tempo.offset_top = 160.0
	_tempo.offset_right = 260.0
	_tempo.offset_bottom = 188.0
	raiz.add_child(_tempo)

	# Anéis passados (logo abaixo do tempo).
	_label_anel = _rotulo("Anéis: 0", 14, VERDE)
	_label_anel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label_anel.offset_left = 28.0
	_label_anel.offset_top = 188.0
	_label_anel.offset_right = 260.0
	_label_anel.offset_bottom = 212.0
	_label_anel.visible = false
	raiz.add_child(_label_anel)

	# Velocidade (canto inferior direito).
	var painel_vel := PanelContainer.new()
	painel_vel.name = "Velocidade"
	painel_vel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	painel_vel.offset_left = -246.0
	painel_vel.offset_top = -112.0
	painel_vel.offset_right = -26.0
	painel_vel.offset_bottom = -28.0
	painel_vel.add_theme_stylebox_override("panel", _painel_estilo())
	raiz.add_child(painel_vel)
	var col_vel := VBoxContainer.new()
	col_vel.add_theme_constant_override("separation", 2)
	painel_vel.add_child(col_vel)
	var topo_vel := HBoxContainer.new()
	col_vel.add_child(topo_vel)
	var rot_vel := _rotulo("VELOCIDADE", 11, APAGADO)
	rot_vel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo_vel.add_child(rot_vel)
	_velocidade = _rotulo("0 km/h", 20, TINTA)
	_velocidade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	topo_vel.add_child(_velocidade)
	_barra_vel = ProgressBar.new()
	_barra_vel.max_value = 120.0
	_barra_vel.value = 0.0
	_barra_vel.show_percentage = false
	_barra_vel.custom_minimum_size = Vector2(0.0, 8.0)
	_barra_vel.add_theme_stylebox_override("background", _caixa(Color(0.0, 0.0, 0.0, 0.45), 4))
	_barra_vel.add_theme_stylebox_override("fill", _caixa(VERDE, 4))
	col_vel.add_child(_barra_vel)

	# Dicas de controle (canto inferior esquerdo).
	var dicas := _rotulo("A / D  ou  ← →  desviar     •     ESPAÇO  pular     •     Y  câmera     •     ESC  pausa", 13, Color(1, 1, 1, 0.88))
	dicas.name = "Dicas"
	dicas.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dicas.offset_left = 28.0
	dicas.offset_top = -44.0
	dicas.offset_right = 780.0
	dicas.offset_bottom = -18.0
	dicas.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	dicas.add_theme_constant_override("shadow_offset_x", 1)
	dicas.add_theme_constant_override("shadow_offset_y", 2)
	raiz.add_child(dicas)

	# Contagem regressiva central.
	_contagem = _rotulo("", 120, Color(1, 1, 1, 1))
	_contagem.name = "Contagem"
	_contagem.set_anchors_preset(Control.PRESET_FULL_RECT)
	_contagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contagem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_contagem.add_theme_color_override("font_outline_color", Color(0.02, 0.10, 0.05, 0.95))
	_contagem.add_theme_constant_override("outline_size", 18)
	_contagem.visible = false
	raiz.add_child(_contagem)

	# Flash vermelho ao bater.
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.18, 0.12, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(_flash)

	_construir_pausa(raiz)
	_construir_fim(raiz)


func _construir_pausa(raiz: Control) -> void:
	_painel_pausa = Control.new()
	_painel_pausa.name = "Pausa"
	_painel_pausa.set_anchors_preset(Control.PRESET_FULL_RECT)
	_painel_pausa.visible = false
	raiz.add_child(_painel_pausa)
	var fundo := ColorRect.new()
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.color = Color(0.0, 0.02, 0.01, 0.58)
	_painel_pausa.add_child(fundo)
	var painel := PanelContainer.new()
	painel.set_anchors_preset(Control.PRESET_CENTER)
	painel.offset_left = -235.0
	painel.offset_top = -168.0
	painel.offset_right = 235.0
	painel.offset_bottom = 168.0
	painel.add_theme_stylebox_override("panel", _painel_estilo())
	_painel_pausa.add_child(painel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	painel.add_child(col)
	col.add_child(_rotulo("PAUSA", 34, TINTA))
	var sub := _rotulo("A montanha espera por você.", 13, APAGADO)
	col.add_child(sub)
	var espaco := Control.new()
	espaco.custom_minimum_size = Vector2(0.0, 10.0)
	col.add_child(espaco)
	col.add_child(_botao("Continuar descendo", true, func() -> void: _alternar_pausa()))
	col.add_child(_botao("Recomeçar descida", false, func() -> void: pediu_reiniciar.emit()))
	col.add_child(_botao("Voltar ao mapa", false, func() -> void: pediu_sair.emit()))


func _construir_fim(raiz: Control) -> void:
	_painel_fim = PanelContainer.new()
	_painel_fim.name = "Fim"
	_painel_fim.set_anchors_preset(Control.PRESET_CENTER)
	_painel_fim.offset_left = -280.0
	_painel_fim.offset_top = -210.0
	_painel_fim.offset_right = 280.0
	_painel_fim.offset_bottom = 210.0
	_painel_fim.add_theme_stylebox_override("panel", _painel_estilo(true))
	_painel_fim.visible = false
	raiz.add_child(_painel_fim)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_painel_fim.add_child(col)
	col.add_child(_rotulo("CHEGOU AO FIM!", 34, VERDE))
	col.add_child(_rotulo("Base do Pico da Nebulosa", 14, APAGADO))
	_fim_stats = _rotulo("", 16, TINTA)
	col.add_child(_fim_stats)
	_fim_xp = _rotulo("", 18, VERDE)
	col.add_child(_fim_xp)
	var espaco := Control.new()
	espaco.custom_minimum_size = Vector2(0.0, 8.0)
	col.add_child(espaco)
	col.add_child(_botao("Descer de novo", true, func() -> void: pediu_reiniciar.emit()))
	col.add_child(_botao("Voltar ao mapa", false, func() -> void: pediu_sair.emit()))


# ---------------------------------------------------------------- widgets
func _rotulo(texto: String, tamanho: int, cor: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tamanho)
	l.add_theme_color_override("font_color", cor)
	return l


func _botao(texto: String, primario: bool, acao: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(0.0, 44.0)
	b.focus_mode = Control.FOCUS_NONE
	if primario:
		b.add_theme_stylebox_override("normal", _botao_estilo(VERDE_ESCURO, VERDE))
		b.add_theme_stylebox_override("hover", _botao_estilo(Color(0.16, 0.78, 0.38), VERDE))
		b.add_theme_stylebox_override("pressed", _botao_estilo(Color(0.08, 0.50, 0.24), VERDE))
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	else:
		b.add_theme_stylebox_override("normal", _botao_estilo(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.16)))
		b.add_theme_stylebox_override("hover", _botao_estilo(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.32)))
		b.add_theme_stylebox_override("pressed", _botao_estilo(Color(1, 1, 1, 0.20), Color(1, 1, 1, 0.40)))
		b.add_theme_color_override("font_color", TINTA)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(acao)
	return b


func _caixa(cor: Color, raio: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.set_corner_radius_all(raio)
	return s


func _painel_estilo(destaque: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.06, 0.04, 0.62) if not destaque else Color(0.02, 0.06, 0.04, 0.90)
	s.set_corner_radius_all(12)
	s.set_border_width_all(1)
	s.border_color = Color(0.22, 0.92, 0.48, 0.30) if not destaque else Color(0.22, 0.92, 0.48, 0.65)
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 12.0
	s.content_margin_bottom = 12.0
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	s.shadow_size = 10
	return s


func _botao_estilo(fundo: Color, borda: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fundo
	s.set_corner_radius_all(9)
	s.set_border_width_all(1)
	s.border_color = borda
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 9.0
	s.content_margin_bottom = 9.0
	return s


# ---------------------------------------------------------------- api
func atualizar(distancia: float, kmh: float, segundos: float, progresso: float) -> void:
	_distancia.text = "%d m" % int(distancia)
	_velocidade.text = "%d km/h" % int(round(kmh))
	_tempo.text = _formatar_tempo(segundos)
	_barra_vel.value = clampf(kmh, 0.0, 120.0)
	_progresso.value = clampf(progresso, 0.0, 1.0) * 100.0


func definir_recorde(metros: int) -> void:
	_recorde.text = "Recorde: %d m" % metros


func mostrar_contagem(texto: String) -> void:
	_contagem.text = texto
	_contagem.visible = true
	_contagem.modulate.a = 0.0
	_contagem.pivot_offset = _contagem.size * 0.5
	_contagem.scale = Vector2(1.45, 1.45)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_contagem, "modulate:a", 1.0, 0.12)
	tw.tween_property(_contagem, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func esconder_contagem() -> void:
	_contagem.visible = false


func flash_dano() -> void:
	_flash.color.a = 0.34
	create_tween().tween_property(_flash, "color:a", 0.0, 0.38).set_ease(Tween.EASE_OUT)


func flash_anel(total: int) -> void:
	_anéis = total
	_label_anel.text = "Anéis: %d" % total
	_label_anel.visible = true
	_label_anel.modulate = VERDE
	var tween := create_tween()
	tween.tween_property(_label_anel, "modulate:a", 1.0, 0.1)
	tween.tween_property(_label_anel, "scale", Vector2(1.4, 1.4), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_label_anel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tween.tween_property(_label_anel, "modulate:a", 0.6, 0.6).set_delay(0.4)


func abrir_fim(distancia: float, segundos: float, tombos: int, xp: int, novo_recorde: bool) -> void:
	_fim = true
	_painel_fim.visible = true
	_fim_stats.text = "%d m percorridos\n%s de descida\n%d obstáculos acertados\n%d anéis atravessados" % [int(distancia), _formatar_tempo(segundos), tombos, _anéis]
	_fim_xp.text = ("+%d XP  •  NOVO RECORDE!" % xp) if novo_recorde else ("+%d XP" % xp)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func fechar_fim() -> void:
	_fim = false
	_painel_fim.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(evento: InputEvent) -> void:
	if _fim:
		return
	if evento.is_action_pressed("ui_cancel"):
		_alternar_pausa()
		get_viewport().set_input_as_handled()


func _alternar_pausa() -> void:
	_pausado = not _pausado
	_painel_pausa.visible = _pausado
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pausado else Input.MOUSE_MODE_CAPTURED
	pausa_alternada.emit(_pausado)


func _formatar_tempo(segundos: float) -> String:
	var mins := int(segundos / 60.0)
	var seg := fmod(maxf(segundos, 0.0), 60.0)
	return "%02d:%04.1f" % [mins, seg]
