extends Control
## Tela de configuracoes EXCLUSIVA do menu principal.
## Nao reaproveita o Diario/HUD do jogo, nem o PlayerProfile.
## Salva em user://savegame.json via SaveSystem (autoload).

const COR_ACCENT := Color("#2e7d4f")
const COR_INK := Color("#21252b")

const MODO_AUTO := "auto"
const MODO_SEMPRE := "sempre"
const MODO_NUNCA := "nunca"

## Rotulo exibido -> acao do InputMap (criadas pelo autoload InputSetup).
const LISTA_CONTROLES := [
	["Movimentar", "mover_frente"],
	["Voltar / re", "mover_tras"],
	["Esquerda", "mover_esq"],
	["Direita", "mover_dir"],
	["Correr", "correr"],
	["Pular", "pular"],
	["Descer", "descer"],
	["Interagir", "interagir"],
	["Pulverizar", "pulverizar"],
	["Ligar motor", "ligar_motor"],
	["Buzinar", "buzinar"],
	["Diario", "diario"],
	["Tutorial do drone", "tutorial_drone"],
	["Chuva", "chuva"],
	["Camera", "camera"],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	AgroUITheme.apply_to(self)
	_estilizar()
	_carregar_configuracoes()
	_conectar_sinais()
	_montar_lista_controles()

	var btn_voltar := _no("BotaoVoltar") as Button
	if btn_voltar != null:
		btn_voltar.call_deferred("grab_focus")

	set_process_unhandled_input(true)

	# Garante que a tela abra sempre na primeira aba (AUDIO)
	var abas := _no("Abas") as TabContainer
	if abas != null:
		abas.call_deferred("set_current_tab", 0)


## Atalho: fecha o painel com ESC.
func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_voltar()


# ---------------------------------------------------------------- utilidades

func _no(nome: String) -> Node:
	return find_child(nome, true, false)


func _estilizar() -> void:
	var painel := _no("Painel") as PanelContainer
	if painel != null:
		AgroUITheme.style_panel(painel, "light")

	var titulo := _no("Titulo") as Label
	if titulo != null:
		titulo.add_theme_font_size_override("font_size", 30)
		titulo.add_theme_color_override("font_color", COR_ACCENT)

	# Abas: AUDIO | TELA | CONTROLES (a ordem segue a ordem dos filhos)
	var abas := _no("Abas") as TabContainer
	if abas != null:
		abas.set_tab_title(0, "AUDIO")
		abas.set_tab_title(1, "TELA")
		abas.set_tab_title(2, "CONTROLES")
		abas.add_theme_font_size_override("font_size", 15)
		abas.add_theme_color_override("font_selected_color", Color.WHITE)
		abas.add_theme_color_override("font_unselected_color", Color("#4b5563"))
		abas.add_theme_color_override("font_hover_color", COR_ACCENT)
		abas.current_tab = 0

	# O CheckButton nao deve herdar o fundo verde do tema de Button
	var chk_vsync := _no("ChkVSync") as Button
	if chk_vsync != null:
		chk_vsync.custom_minimum_size = Vector2(0, 44)
		chk_vsync.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var ajuda := _no("AjudaVSync") as Label
	if ajuda != null:
		ajuda.add_theme_font_size_override("font_size", 12)
		ajuda.add_theme_color_override("font_color", Color("#6b7280"))

	var rotulo_toque := _no("RotuloToque") as Label
	if rotulo_toque != null:
		rotulo_toque.add_theme_font_size_override("font_size", 16)
		rotulo_toque.add_theme_color_override("font_color", COR_ACCENT)

	var dica_toque := _no("DicaToque") as Label
	if dica_toque != null:
		dica_toque.add_theme_font_size_override("font_size", 12)
		dica_toque.add_theme_color_override("font_color", Color("#6b7280"))

	var btn_voltar := _no("BotaoVoltar") as Button
	if btn_voltar != null:
		AgroUITheme.style_primary_button(btn_voltar)
		btn_voltar.custom_minimum_size = Vector2(220, 44)


func _conectar_sinais() -> void:
	var slider_efeitos := _no("SliderEfeitos") as HSlider
	if slider_efeitos != null:
		slider_efeitos.value_changed.connect(_on_efeitos_alterado)

	var slider_musica := _no("SliderMusica") as HSlider
	if slider_musica != null:
		slider_musica.value_changed.connect(_on_musica_alterado)

	var chk_vsync := _no("ChkVSync") as Button
	if chk_vsync != null:
		chk_vsync.toggled.connect(_on_vsync_alterado)

	var btn_voltar := _no("BotaoVoltar") as Button
	if btn_voltar != null:
		btn_voltar.pressed.connect(_voltar)

	# Modo dos controles de toque: Automatico / Sempre / Nunca
	for item in [
		["BtnToqueAuto", MODO_AUTO],
		["BtnToqueSempre", MODO_SEMPRE],
		["BtnToqueNunca", MODO_NUNCA],
	]:
		var botao := _no(str(item[0])) as Button
		if botao != null:
			botao.pressed.connect(_definir_modo_toque.bind(str(item[1])))


# ------------------------------------------------------------ carregar/salvar

func _carregar_configuracoes() -> void:
	var d := SaveSystem.dados

	var slider_efeitos := _no("SliderEfeitos") as HSlider
	if slider_efeitos != null:
		slider_efeitos.value = float(d.get("volume_efeitos", 70.0))

	var slider_musica := _no("SliderMusica") as HSlider
	if slider_musica != null:
		slider_musica.value = float(d.get("volume_musica", 70.0))

	var chk_vsync := _no("ChkVSync") as Button
	if chk_vsync != null:
		var ativo := bool(d.get("vsync", true))
		chk_vsync.button_pressed = ativo
		if ativo:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		else:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_atualizar_labels()
	_atualizar_botoes_toque()


func _on_efeitos_alterado(valor: float) -> void:
	AudioConfig.definir_volume_efeitos(valor, false)
	_atualizar_labels()
	_salvar()


func _on_musica_alterado(valor: float) -> void:
	AudioConfig.definir_volume_musica(valor, false)
	_atualizar_labels()
	_salvar()


func _on_vsync_alterado(ativo: bool) -> void:
	if ativo:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_atualizar_labels()
	_salvar()


func _atualizar_labels() -> void:
	var chk_vsync := _no("ChkVSync") as Button
	if chk_vsync != null:
		if chk_vsync.button_pressed:
			chk_vsync.text = "V-Sync: LIGADO"
			AgroUITheme.style_primary_button(chk_vsync)
			chk_vsync.add_theme_stylebox_override("hover_pressed", chk_vsync.get_theme_stylebox("pressed"))
		else:
			chk_vsync.text = "V-Sync: DESLIGADO"
			AgroUITheme.style_secondary_button(chk_vsync)

	var lbl_efeitos := _no("LblValorEfeitos") as Label
	var slider_efeitos := _no("SliderEfeitos") as HSlider
	if lbl_efeitos != null and slider_efeitos != null:
		lbl_efeitos.text = "Efeitos: %d%%" % int(slider_efeitos.value)

	var lbl_musica := _no("LblValorMusica") as Label
	var slider_musica := _no("SliderMusica") as HSlider
	if lbl_musica != null and slider_musica != null:
		lbl_musica.text = "Musica: %d%%" % int(slider_musica.value)


func _salvar() -> void:
	var d := SaveSystem.dados

	var slider_efeitos := _no("SliderEfeitos") as HSlider
	if slider_efeitos != null:
		d["volume_efeitos"] = slider_efeitos.value

	var slider_musica := _no("SliderMusica") as HSlider
	if slider_musica != null:
		d["volume_musica"] = slider_musica.value

	var chk_vsync := _no("ChkVSync") as Button
	if chk_vsync != null:
		d["vsync"] = chk_vsync.button_pressed

	SaveSystem.salvar()


# ------------------------------------------------------------------ controles

func _montar_lista_controles() -> void:
	var lista := _no("ListaControles") as VBoxContainer
	if lista == null:
		return

	for filho in lista.get_children():
		filho.queue_free()

	for item in LISTA_CONTROLES:
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 12)

		var nome := Label.new()
		nome.text = str(item[0])
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nome.add_theme_color_override("font_color", COR_INK)
		linha.add_child(nome)

		var tecla := Label.new()
		tecla.text = _texto_tecla(str(item[1]))
		tecla.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tecla.add_theme_color_override("font_color", COR_ACCENT)
		linha.add_child(tecla)

		lista.add_child(linha)


func _texto_tecla(acao: String) -> String:
	if not InputMap.has_action(acao):
		return "-"

	var partes: Array[String] = []
	for evento in InputMap.action_get_events(acao):
		var texto := ""
		if evento is InputEventKey:
			var codigo: int = evento.physical_keycode
			if codigo == 0:
				codigo = evento.keycode
			texto = OS.get_keycode_string(codigo)
		elif evento is InputEventJoypadButton:
			texto = _nome_botao_joypad(evento.button_index)
		elif evento is InputEventJoypadMotion:
			continue

		if texto != "" and not partes.has(texto):
			partes.append(texto)
		if partes.size() >= 2:
			break

	if partes.is_empty():
		return "-"
	return " / ".join(partes)


func _nome_botao_joypad(indice: int) -> String:
	match indice:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-Pad Cima"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad Baixo"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad Esq."
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad Dir."
	return "Botao %d" % indice


func _definir_modo_toque(modo: String) -> void:
	SaveSystem.dados["controles_toque"] = modo
	SaveSystem.salvar()
	_atualizar_botoes_toque()


func _atualizar_botoes_toque() -> void:
	var atual := str(SaveSystem.dados.get("controles_toque", MODO_AUTO))
	for item in [
		["BtnToqueAuto", MODO_AUTO],
		["BtnToqueSempre", MODO_SEMPRE],
		["BtnToqueNunca", MODO_NUNCA],
	]:
		var botao := _no(str(item[0])) as Button
		if botao == null:
			continue
		if str(item[1]) == atual:
			AgroUITheme.style_primary_button(botao)
		else:
			AgroUITheme.style_secondary_button(botao)


# --------------------------------------------------------------------- fechar

func _voltar() -> void:
	var pai := get_parent()
	if pai != null and pai.has_method("fechar_configuracoes_menu"):
		pai.fechar_configuracoes_menu()
	else:
		queue_free()
