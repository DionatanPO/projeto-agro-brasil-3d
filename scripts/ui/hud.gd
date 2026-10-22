extends CanvasLayer
## HUD educativo. Continua recebendo entrada quando o jogo está pausado.

@onready var dialogo: PanelContainer = $Dialogo
@onready var dialogo_titulo: Label = $Dialogo/Inset/Conteudo/DialogoTitulo
@onready var dialogo_texto: Label = $Dialogo/Inset/Conteudo/DialogoTexto
@onready var dialogo_fonte: Label = $Dialogo/Inset/Conteudo/DialogoFonte
@onready var diario: PanelContainer = $Diario
@onready var lista_box: VBoxContainer = $Diario/Inset/Conteudo/Abas/Missão/Margem/Coluna/ListaBox
@onready var aviso_vazio: Label = $Diario/Inset/Conteudo/Abas/Missão/Margem/Coluna/AvisoVazio
@onready var missoes_info: Label = $Diario/Inset/Conteudo/Abas/Missão/Margem/Coluna/MissoesInfo
@onready var objetivo_missao: Label = $Diario/Inset/Conteudo/Abas/Missão/Margem/Coluna/Objetivo
@onready var slider_efeitos: HSlider = $Diario/Inset/Conteudo/Abas/Áudio/Margem/Coluna/VolumeEfeitos
@onready var slider_musica: HSlider = $Diario/Inset/Conteudo/Abas/Áudio/Margem/Coluna/VolumeMusica
@onready var check_mudo: CheckButton = $Diario/Inset/Conteudo/Abas/Áudio/Margem/Coluna/Mudo
@onready var check_tela: CheckButton = $Diario/Inset/Conteudo/Abas/Tela/Margem/Coluna/TelaCheia
@onready var abas: TabContainer = $Diario/Inset/Conteudo/Abas
@onready var btn_aba_missao: Button = $Diario/Inset/Conteudo/SeletorAbas/BtnMissao
@onready var btn_aba_controles: Button = $Diario/Inset/Conteudo/SeletorAbas/BtnControles
@onready var btn_aba_audio: Button = $Diario/Inset/Conteudo/SeletorAbas/BtnAudio
@onready var btn_aba_tela: Button = $Diario/Inset/Conteudo/SeletorAbas/BtnTela
@onready var btn_aba_graficos: Button = $Diario/Inset/Conteudo/SeletorAbas/BtnGraficos
@onready var btn_grafico_baixo: Button = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/Botoes/BtnBaixo
@onready var btn_grafico_medio: Button = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/Botoes/BtnMedio
@onready var btn_grafico_alto: Button = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/Botoes/BtnAlto
@onready var btn_fsr_off: Button = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/BotoesUpscaling/BtnFSR_Off
@onready var btn_fsr1: Button = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/BotoesUpscaling/BtnFSR1
@onready var btn_fsr2: Button = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/BotoesUpscaling/BtnFSR2
@onready var slider_upscaling: HSlider = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/EscalaUpscaling
@onready var valor_escala: Label = $Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/ValorEscala
@onready var btn_vsync: CheckButton = $Diario/Inset/Conteudo/Abas/Tela/Margem/Coluna/BtnVSync

var _dialogo_aberto_para := ""
var _botoes_abas: Array = []
@onready var scrim: ColorRect = $Scrim
@onready var popup_missao: PanelContainer = $MissaoCompleta
@onready var popup_texto: Label = $MissaoCompleta/Inset/Conteudo/Texto
@onready var fps_label: Label = $FPS

var _fps_tempo := 0.0

var _som_ui_click: AudioStreamPlayer
var _som_ui_hover: AudioStreamPlayer
var _som_ui_switch: AudioStreamPlayer

const CENA_FASE_TESTE := "res://world.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	AgroUITheme.apply_to(dialogo)
	AgroUITheme.apply_to(diario)
	AgroUITheme.style_panel(dialogo, "glass")
	AgroUITheme.style_panel(diario, "glass")
	AgroUITheme.apply_to(popup_missao)
	AgroUITheme.style_panel(popup_missao, "glass")
	$MissaoCompleta/Inset/Conteudo/Titulo.add_theme_font_size_override("font_size", 20)
	_configurar_espacamento()
	dialogo_titulo.add_theme_font_size_override("font_size", 16)
	dialogo_texto.add_theme_font_size_override("font_size", 11)
	dialogo_fonte.add_theme_font_size_override("font_size", 9)
	$Diario/Inset/Conteudo/Titulo.add_theme_font_size_override("font_size", 18)
	$Diario/Inset/Conteudo/Subtitulo.add_theme_color_override("font_color", AgroUITheme.MUTED_INK)
	$Diario/Inset/Conteudo/Subtitulo.add_theme_font_size_override("font_size", 12)
	for cabecalho in [
		$Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/RotuloGrafico,
		$Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/RotuloUpscaling,
		$Diario/Inset/Conteudo/Abas/Tela/Margem/Coluna/RotuloVSync,
	]:
		cabecalho.add_theme_font_size_override("font_size", 12)
		cabecalho.add_theme_color_override("font_color", AgroUITheme.MUTED_INK)
	for dica in [
		$Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/DicaGrafico,
		$Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/DicaUpscaling,
		$Diario/Inset/Conteudo/Abas/Tela/Margem/Coluna/DicaTela,
		$Diario/Inset/Conteudo/Abas/Tela/Margem/Coluna/DicaVSync,
		$Diario/Inset/Conteudo/Abas/Graficos/Margem/Coluna/ValorEscala,
	]:
		dica.add_theme_font_size_override("font_size", 11)
		dica.add_theme_color_override("font_color", AgroUITheme.MUTED_INK)
	missoes_info.add_theme_font_size_override("font_size", 12)
	aviso_vazio.add_theme_font_size_override("font_size", 12)
	aviso_vazio.add_theme_color_override("font_color", Color("#a16207"))
	objetivo_missao.add_theme_font_size_override("font_size", 14)
	$Diario/Inset/Conteudo/Abas/Controles/Margem/Coluna/TextoControles.add_theme_font_size_override("font_size", 12)
	$Dialogo/Inset/Conteudo/BotaoEntendi.pressed.connect(_on_entendi)
	$Diario/Inset/Conteudo/Acoes/BotaoFechar.pressed.connect(_on_fechar_diario)
	$Diario/Inset/Conteudo/Acoes/BotaoVoltar.pressed.connect(_on_voltar_menu)
	$MissaoCompleta/Inset/Conteudo/BotaoNovaFase.pressed.connect(_on_ir_nova_fase)
	$MissaoCompleta/Inset/Conteudo/BotaoContinuar.pressed.connect(_on_continuar_explorando)
	AgroUITheme.style_primary_button($Dialogo/Inset/Conteudo/BotaoEntendi)
	AgroUITheme.style_secondary_button($Diario/Inset/Conteudo/Acoes/BotaoFechar)
	AgroUITheme.style_secondary_button($Diario/Inset/Conteudo/Acoes/BotaoVoltar)
	AgroUITheme.style_primary_button($MissaoCompleta/Inset/Conteudo/BotaoNovaFase)
	AgroUITheme.style_secondary_button($MissaoCompleta/Inset/Conteudo/BotaoContinuar)
	slider_efeitos.set_value_no_signal(AudioConfig.volume_efeitos())
	slider_musica.set_value_no_signal(AudioConfig.volume_musica())
	check_mudo.set_pressed_no_signal(AudioServer.is_bus_mute(0))
	check_tela.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	slider_efeitos.value_changed.connect(_on_efeitos_mudou)
	slider_musica.value_changed.connect(_on_musica_mudou)
	check_mudo.toggled.connect(_on_mudo)
	check_tela.toggled.connect(_on_tela_cheia)
	_botoes_abas = [btn_aba_missao, btn_aba_controles, btn_aba_audio, btn_aba_tela, btn_aba_graficos]
	for i in _botoes_abas.size():
		_botoes_abas[i].pressed.connect(_on_aba.bind(i))
	_on_aba(0)
	btn_grafico_baixo.pressed.connect(_on_grafico.bind("baixo"))
	btn_grafico_medio.pressed.connect(_on_grafico.bind("medio"))
	btn_grafico_alto.pressed.connect(_on_grafico.bind("alto"))
	_atualizar_botoes_grafico(QualidadeGrafica.nivel_salvo())
	QualidadeGrafica.aplicar(QualidadeGrafica.nivel_salvo())
	btn_fsr_off.pressed.connect(_on_upscaling.bind("off"))
	btn_fsr1.pressed.connect(_on_upscaling.bind("fsr1"))
	btn_fsr2.pressed.connect(_on_upscaling.bind("fsr2"))
	slider_upscaling.set_value_no_signal(float(SaveSystem.dados.get("upscaling_preset", 1)))
	slider_upscaling.value_changed.connect(_on_upscaling_escala)
	_atualizar_botoes_upscaling(str(SaveSystem.dados.get("upscaling", "off")))
	_atualizar_rotulo_escala(int(SaveSystem.dados.get("upscaling_preset", 1)))
	_aplicar_upscaling(str(SaveSystem.dados.get("upscaling", "off")), _escala_do_preset(int(SaveSystem.dados.get("upscaling_preset", 1))))
	btn_vsync.set_pressed_no_signal(bool(SaveSystem.dados.get("vsync", true)))
	_aplicar_vsync(bool(SaveSystem.dados.get("vsync", true)))
	btn_vsync.toggled.connect(_on_vsync)
	_configurar_sons_ui()
	dialogo.hide()
	diario.hide()
	popup_missao.hide()
	scrim.hide()
	Jogo.dialogo_solicitado.connect(_abrir_dialogo)
	Jogo.alternar_diario.connect(_alternar_diario)
	Jogo.descoberta_registrada.connect(_on_descoberta)
	Missoes.missao_concluida.connect(_on_missao)

func _configurar_espacamento() -> void:
	for inset in [$Dialogo/Inset, $Diario/Inset]:
		inset.add_theme_constant_override("margin_left", 20)
		inset.add_theme_constant_override("margin_top", 17)
		inset.add_theme_constant_override("margin_right", 20)
		inset.add_theme_constant_override("margin_bottom", 17)
	$Dialogo/Inset/Conteudo.add_theme_constant_override("separation", 10)
	$Diario/Inset/Conteudo.add_theme_constant_override("separation", 8)

func _abrir_dialogo(conteudo_id: String) -> void:
	var c: Dictionary = Jogo.obter_conteudo(conteudo_id)
	if c.is_empty():
		push_warning("HUD: conteúdo '%s' não encontrado." % conteudo_id)
		return
	_dialogo_aberto_para = conteudo_id
	dialogo_titulo.text = str(c.get("titulo", conteudo_id))
	dialogo_texto.text = str(c.get("texto", ""))
	dialogo_fonte.text = "Fonte: " + str(c.get("fonte", ""))
	dialogo.show()
	scrim.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Dialogo/Inset/Conteudo/BotaoEntendi.grab_focus()

func _on_entendi() -> void:
	dialogo.hide()
	scrim.hide()
	get_tree().paused = false
	if not _dialogo_aberto_para.is_empty():
		Jogo.registrar_descoberta(_dialogo_aberto_para)
	_dialogo_aberto_para = ""

func _alternar_diario() -> void:
	diario.visible = not diario.visible
	scrim.visible = diario.visible
	get_tree().paused = diario.visible
	if diario.visible:
		_preencher_diario()
		# Libera o cursor: no jogo o mouse fica capturado e, sem isto, o
		# caderno abre com o cursor preso/escondido e nao da para clicar.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		$Diario/Inset/Conteudo/Acoes/BotaoFechar.grab_focus()

func _on_fechar_diario() -> void:
	diario.hide()
	scrim.hide()
	get_tree().paused = false
	# Volta a capturar o mouse (gameplay), a menos que outro painel esteja aberto.
	if not dialogo.visible and not popup_missao.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if diario.visible and (event.is_action_pressed("diario") or event.is_action_pressed("ui_cancel")):
		_on_fechar_diario()
		get_viewport().set_input_as_handled()

func _on_efeitos_mudou(valor: float) -> void:
	AudioConfig.definir_volume_efeitos(valor)


func _on_musica_mudou(valor: float) -> void:
	AudioConfig.definir_volume_musica(valor)

func _on_mudo(ativado: bool) -> void:
	AudioServer.set_bus_mute(0, ativado)

func _on_tela_cheia(ativado: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if ativado else DisplayServer.WINDOW_MODE_WINDOWED)


func _on_grafico(nivel: String) -> void:
	QualidadeGrafica.definir(nivel)
	_atualizar_botoes_grafico(nivel)
	if _som_ui_switch != null:
		_som_ui_switch.play()


func _atualizar_botoes_grafico(nivel: String) -> void:
	btn_grafico_baixo.set_pressed_no_signal(nivel == "baixo")
	btn_grafico_medio.set_pressed_no_signal(nivel == "medio")
	btn_grafico_alto.set_pressed_no_signal(nivel == "alto")
	for par in [[btn_grafico_baixo, "baixo"], [btn_grafico_medio, "medio"], [btn_grafico_alto, "alto"]]:
		if par[1] == nivel:
			AgroUITheme.style_primary_button(par[0])
		else:
			AgroUITheme.style_secondary_button(par[0])


func _on_upscaling(modo: String) -> void:
	SaveSystem.dados["upscaling"] = modo
	SaveSystem.salvar()
	_atualizar_botoes_upscaling(modo)
	_aplicar_upscaling(modo, _escala_do_preset(int(SaveSystem.dados.get("upscaling_preset", 1))))


func _on_upscaling_escala(preset: float) -> void:
	var p := int(round(preset))
	SaveSystem.dados["upscaling_preset"] = p
	SaveSystem.dados["upscaling_scale"] = _escala_do_preset(p)
	SaveSystem.salvar()
	_atualizar_rotulo_escala(p)
	_aplicar_upscaling(str(SaveSystem.dados.get("upscaling", "off")), _escala_do_preset(p))


func _escala_do_preset(p: int) -> float:
	match p:
		0:
			return 0.5
		2:
			return 0.85
		_:
			return 0.67


func _atualizar_rotulo_escala(p: int) -> void:
	match p:
		0:
			valor_escala.text = "Performance • mais FPS"
		2:
			valor_escala.text = "Qualidade • mais nítido"
		_:
			valor_escala.text = "Equilibrado"


func _on_vsync(ativado: bool) -> void:
	SaveSystem.dados["vsync"] = ativado
	SaveSystem.salvar()
	_aplicar_vsync(ativado)


func _aplicar_vsync(ativado: bool) -> void:
	if ativado:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func _configurar_sons_ui() -> void:
	_som_ui_click = AudioStreamPlayer.new()
	_som_ui_click.stream = load("res://assets/audio/ui/click1.ogg")
	_som_ui_click.bus = "Efeitos"
	add_child(_som_ui_click)
	_som_ui_hover = AudioStreamPlayer.new()
	_som_ui_hover.stream = load("res://assets/audio/ui/rollover1.ogg")
	_som_ui_hover.bus = "Efeitos"
	_som_ui_hover.volume_db = -8.0
	add_child(_som_ui_hover)
	_som_ui_switch = AudioStreamPlayer.new()
	_som_ui_switch.stream = load("res://assets/audio/ui/switch1.ogg")
	_som_ui_switch.bus = "Efeitos"
	add_child(_som_ui_switch)
	for b in _botoes_abas + [btn_grafico_baixo, btn_grafico_medio, btn_grafico_alto, btn_fsr_off, btn_fsr1, btn_fsr2, $Dialogo/Inset/Conteudo/BotaoEntendi, $Diario/Inset/Conteudo/Acoes/BotaoFechar, $Diario/Inset/Conteudo/Acoes/BotaoVoltar]:
		b.pressed.connect(_tocar_click_ui)
		(b as Button).mouse_entered.connect(_tocar_hover_ui)


func _tocar_click_ui() -> void:
	if _som_ui_click != null:
		_som_ui_click.play()


func _tocar_hover_ui() -> void:
	if _som_ui_hover != null:
		_som_ui_hover.play()


func _atualizar_botoes_upscaling(modo: String) -> void:
	btn_fsr_off.set_pressed_no_signal(modo == "off")
	btn_fsr1.set_pressed_no_signal(modo == "fsr1")
	btn_fsr2.set_pressed_no_signal(modo == "fsr2")
	for par in [[btn_fsr_off, "off"], [btn_fsr1, "fsr1"], [btn_fsr2, "fsr2"]]:
		if par[1] == modo:
			AgroUITheme.style_primary_button(par[0])
		else:
			AgroUITheme.style_secondary_button(par[0])


func _aplicar_upscaling(modo: String, escala: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var metodo := RenderingServer.get_current_rendering_method()
	if modo == "fsr2" and metodo != "forward_plus":
		modo = "fsr1"
	match modo:
		"fsr1":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = clampf(escala, 0.5, 1.0)
		"fsr2":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = clampf(escala, 0.5, 1.0)
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0

func _on_aba(indice: int) -> void:
	abas.current_tab = indice
	for i in _botoes_abas.size():
		var b: Button = _botoes_abas[i]
		b.set_pressed_no_signal(i == indice)
		if i == indice:
			AgroUITheme.style_primary_button(b)
		else:
			AgroUITheme.style_secondary_button(b)

func _on_ir_nova_fase() -> void:
	get_tree().paused = false
	SaveSystem.salvar()
	Loading.proxima_cena = CENA_FASE_TESTE
	Loading.titulo_carga = "Carregando a próxima fase..."
	get_tree().change_scene_to_file("res://scenes/ui/menus/loading.tscn")

func _on_continuar_explorando() -> void:
	popup_missao.hide()
	if not diario.visible and not dialogo.visible:
		scrim.hide()
		get_tree().paused = false

func _on_voltar_menu() -> void:
	get_tree().paused = false
	SaveSystem.salvar()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/menus/menu_inicial.tscn")

func _on_descoberta(_ponto_id: String) -> void:
	if diario.visible:
		_preencher_diario()

func _on_missao(missao_id: String) -> void:
	if diario.visible:
		_preencher_diario()
	var m: Dictionary = Missoes.por_id.get(missao_id, {})
	popup_texto.text = str(m.get("titulo", missao_id))
	popup_missao.show()
	scrim.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$MissaoCompleta/Inset/Conteudo/BotaoNovaFase.grab_focus()

func _preencher_diario() -> void:
	var prox: Dictionary = Missoes.proxima_pendente()
	if prox.is_empty():
		objetivo_missao.text = "Todas as missões concluídas! Parabéns!"
	else:
		objetivo_missao.text = "OBJETIVO  •  %s — %s" % [prox.get("titulo", ""), prox.get("descricao", "")]
	var descobertas: Variant = SaveSystem.dados.get("descobertas", [])
	var vazio: bool = not (descobertas is Array) or descobertas.is_empty()
	aviso_vazio.visible = vazio
	lista_box.visible = not vazio
	for f in lista_box.get_children():
		lista_box.remove_child(f)
		f.free()
	if not vazio:
		for ponto: Variant in descobertas:
			var c: Dictionary = Jogo.obter_conteudo(str(ponto))
			var item := Label.new()
			item.text = "•  " + str(c.get("titulo", ponto))
			item.add_theme_font_size_override("font_size", 12)
			lista_box.add_child(item)
	var linhas: Array[String] = []
	for missao_id: String in Missoes.ordem:
		var m: Dictionary = Missoes.por_id.get(missao_id, {})
		var marca := "✓" if Missoes.esta_concluida(missao_id) else "○"
		linhas.append("%s  %s" % [marca, m.get("titulo", missao_id)])
	missoes_info.text = "\n".join(linhas)


func _process(delta: float) -> void:
	_fps_tempo += delta
	if _fps_tempo < 0.25:
		return
	_fps_tempo = 0.0
	var fps := Engine.get_frames_per_second()
	fps_label.text = "%d FPS (%.1f ms)" % [fps, 1000.0 / maxf(float(fps), 1.0)]
