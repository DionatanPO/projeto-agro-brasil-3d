extends Control
## Menu principal moderno em layout lateral no estilo Tomb Raider / AAA.
## Itens tipográficos sem caixa/fundo, foco elegante com slide e barra esmeralda.

const CENA_MUNDO := "res://world.tscn"
const CENA_LOADING := "res://scenes/ui/menus/loading.tscn"
const CENA_HUD := "res://scenes/ui/hud.tscn"
const CENA_CONFIGURACOES := "res://scenes/ui/menu_configuracoes.tscn"

@onready var backdrop: TextureRect = get_node_or_null("Backdrop") as TextureRect
@onready var video_fundo: VideoStreamPlayer = get_node_or_null("VideoFundo") as VideoStreamPlayer
@onready var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
@onready var menu_lateral: Control = get_node_or_null("MenuLateral") as Control
@onready var item_continuar: Control = find_child("ItemContinuar", true, false) as Control
@onready var botao_continuar: Button = find_child("BotaoContinuar", true, false) as Button
@onready var barra_continuar: ColorRect = get_node_or_null("MenuLateral/Coluna/Botoes/ItemContinuar/Barra") as ColorRect
@onready var item_novo: Control = find_child("ItemNovo", true, false) as Control
@onready var botao_novo: Button = find_child("BotaoNovo", true, false) as Button
@onready var barra_novo: ColorRect = get_node_or_null("MenuLateral/Coluna/Botoes/ItemNovo/Barra") as ColorRect
@onready var item_sair: Control = find_child("ItemSair", true, false) as Control
@onready var botao_sair: Button = find_child("BotaoSair", true, false) as Button
@onready var barra_sair: ColorRect = get_node_or_null("MenuLateral/Coluna/Botoes/ItemSair/Barra") as ColorRect
@onready var item_configuracoes: Control = find_child("ItemConfiguracoes", true, false) as Control
@onready var botao_configuracoes: Button = find_child("BotaoConfiguracoes", true, false) as Button
@onready var barra_configuracoes: ColorRect = get_node_or_null("MenuLateral/Coluna/Botoes/ItemConfiguracoes/Barra") as ColorRect
@onready var fade_rect: ColorRect = get_node_or_null("FadeRect") as ColorRect

var _som_ui_click: AudioStreamPlayer
var _som_ui_hover: AudioStreamPlayer
var _transicao_em_andamento := false


func _ready() -> void:
	# Garante que a cor de limpeza entre transições de tela seja sempre preta
	RenderingServer.set_default_clear_color(Color.BLACK)

	# O menu ocupa toda a área disponível
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Configura o vídeo de fundo em tela cheia (abordagem correta do Godot 4)
	if video_fundo:
		var video := load("res://assets/video/intro.ogv") as VideoStream
		if video != null:
			video_fundo.stream = video
			video_fundo.autoplay = true
			video_fundo.loop = true
			video_fundo.volume_db = -80.0  # Sem som
			video_fundo.expand = true  # Vídeo escala para o tamanho do nó
			video_fundo.play()  # Inicia a reprodução explicitamente

		# Faz o VideoStreamPlayer ocupar a tela inteira
		video_fundo.anchors_preset = Control.PRESET_FULL_RECT
		video_fundo.anchor_left = 0.0
		video_fundo.anchor_top = 0.0
		video_fundo.anchor_right = 1.0
		video_fundo.anchor_bottom = 1.0
		video_fundo.offset_left = 0.0
		video_fundo.offset_top = 0.0
		video_fundo.offset_right = 0.0
		video_fundo.offset_bottom = 0.0

	# Remove a textura estática do backdrop para não cobrir o vídeo
	if backdrop:
		backdrop.texture = null

	set_process(true)

	if not _validar_nos():
		return

	# Configura a camada de fade
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	fade_rect.z_index = 100

	# Sons de UI
	_configurar_sons_ui()

	# Configura microinterações e estilos
	if botao_continuar != null:
		_configurar_item_menu(botao_continuar, barra_continuar)
	if botao_novo != null:
		_configurar_item_menu(botao_novo, barra_novo)
	if botao_sair != null:
		_configurar_item_menu(botao_sair, barra_sair)
	if botao_configuracoes != null:
		_configurar_item_menu(botao_configuracoes, barra_configuracoes)

	# Lógica de Save: se não houver save game, esconde ou desativa "Continuar Jornada"
	var tem_progresso := SaveSystem.tem_save()
	if item_continuar != null:
		item_continuar.visible = tem_progresso
	if botao_continuar != null:
		botao_continuar.disabled = not tem_progresso

	# Conexão de sinais
	if botao_continuar != null and not botao_continuar.pressed.is_connected(_on_continuar_jogo):
		botao_continuar.pressed.connect(_on_continuar_jogo)

	if botao_novo != null and not botao_novo.pressed.is_connected(_on_novo_jogo):
		botao_novo.pressed.connect(_on_novo_jogo)

	if botao_sair != null and not botao_sair.pressed.is_connected(_on_sair):
		botao_sair.pressed.connect(_on_sair)

	if botao_configuracoes != null and not botao_configuracoes.pressed.is_connected(_on_configuracoes):
		botao_configuracoes.pressed.connect(_on_configuracoes)

	# Foco inicial inteligente
	if tem_progresso and botao_continuar != null and botao_continuar.visible:
		botao_continuar.grab_focus()
	elif botao_novo != null:
		botao_novo.grab_focus()

	# Animação suave de entrada
	modulate.a = 0.0
	var entrada := create_tween()
	entrada.set_trans(Tween.TRANS_CUBIC)
	entrada.set_ease(Tween.EASE_OUT)
	entrada.tween_property(self, "modulate:a", 1.0, 0.7)

func _process(_delta: float) -> void:
	# O vídeo é reproduzido diretamente pelo VideoStreamPlayer.
	# Não é necessário copiar frames para o Backdrop.
	pass


func _validar_nos() -> bool:
	var valido := true
	if menu_lateral == null:
		push_error("Menu: não foi encontrado o nó 'MenuLateral'.")
		valido = false
	if botao_novo == null:
		push_error("Menu: não foi encontrado 'BotaoNovo'.")
		valido = false
	if botao_sair == null:
		push_error("Menu: não foi encontrado 'BotaoSair'.")
		valido = false
	if botao_configuracoes == null:
		push_error("Menu: não foi encontrado 'BotaoConfiguracoes'.")
		valido = false
	if fade_rect == null:
		push_error("Menu: não foi encontrado o nó 'FadeRect'.")
		valido = false
	return valido


func _configurar_item_menu(botao: Button, barra: ColorRect) -> void:
	if botao == null:
		return

	AgroUITheme.style_text_menu_button(botao)

	if barra != null:
		barra.modulate.a = 0.0

	var on_enter := func() -> void:
		_tocar_hover_ui()
		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(botao, "position:x", 16.0, 0.18)
		if barra != null:
			tw.tween_property(barra, "modulate:a", 1.0, 0.18)

	var on_exit := func() -> void:
		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(botao, "position:x", 0.0, 0.18)
		if barra != null:
			tw.tween_property(barra, "modulate:a", 0.0, 0.18)

	if not botao.mouse_entered.is_connected(on_enter):
		botao.mouse_entered.connect(on_enter)
	if not botao.focus_entered.is_connected(on_enter):
		botao.focus_entered.connect(on_enter)

	if not botao.mouse_exited.is_connected(on_exit):
		botao.mouse_exited.connect(on_exit)
	if not botao.focus_exited.is_connected(on_exit):
		botao.focus_exited.connect(on_exit)


## Continuar Jornada: mantém o save salvo e inicia o mapa
func _on_continuar_jogo() -> void:
	if _transicao_em_andamento:
		return
	_desativar_botoes()
	Loading.proxima_cena = CENA_MUNDO
	Loading.titulo_carga = "Continuando sua jornada..."
	_transicionar_para_loading()


## Nova Jornada: ZERA completamente os dados salvos e cria um jogo novo limpo
func _on_novo_jogo() -> void:
	if _transicao_em_andamento:
		return
	_desativar_botoes()

	# Reseta e apaga todo o save anterior, criando o estado padrão inicial
	SaveSystem.apagar()
	SaveSystem.salvar()

	Loading.proxima_cena = CENA_MUNDO
	Loading.titulo_carga = "Iniciando nova jornada..."
	_transicionar_para_loading()


func _on_sair() -> void:
	if _transicao_em_andamento:
		return
	_transicao_em_andamento = true
	_desativar_botoes()
	get_tree().quit()


## Configurações: painel EXCLUSIVO do menu principal
## (não reaproveita o Diário/HUD do jogo nem do mundo principal)
func _on_configuracoes() -> void:
	if _transicao_em_andamento:
		return

	# Evita abrir duas vezes
	if get_node_or_null("MenuConfiguracoes") != null:
		return

	_transicao_em_andamento = true

	# Abre o painel de configurações exclusivo do menu principal
	var cena_cfg := load(CENA_CONFIGURACOES) as PackedScene
	if cena_cfg == null:
		push_error("Menu principal: nao foi possivel carregar " + CENA_CONFIGURACOES)
		_transicao_em_andamento = false
		return

	var inst_cfg := cena_cfg.instantiate() as Control
	if inst_cfg == null:
		_transicao_em_andamento = false
		return

	inst_cfg.name = "MenuConfiguracoes"
	inst_cfg.process_mode = Node.PROCESS_MODE_ALWAYS
	inst_cfg.z_index = 200
	add_child(inst_cfg)
	inst_cfg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Fade de entrada suave (o tween precisa rodar mesmo com a árvore pausada)
	inst_cfg.modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(inst_cfg, "modulate:a", 1.0, 0.25)


## Fecha o painel de configurações do menu principal e volta ao menu
func fechar_configuracoes_menu() -> void:
	var cfg := get_node_or_null("MenuConfiguracoes")
	if cfg != null:
		cfg.queue_free()
	_transicao_em_andamento = false


func _desativar_botoes() -> void:
	_transicao_em_andamento = true
	if botao_continuar != null:
		botao_continuar.disabled = true
	if botao_novo != null:
		botao_novo.disabled = true
	if botao_sair != null:
		botao_sair.disabled = true
	if botao_configuracoes != null:
		botao_configuracoes.disabled = true


func _transicionar_para_loading() -> void:
	var transicao := create_tween()
	transicao.set_trans(Tween.TRANS_CUBIC)
	transicao.set_ease(Tween.EASE_IN_OUT)
	transicao.tween_property(fade_rect, "modulate:a", 1.0, 0.8)
	transicao.tween_callback(func() -> void:
		get_tree().change_scene_to_file(CENA_LOADING)
	)


func _configurar_sons_ui() -> void:
	_som_ui_click = AudioStreamPlayer.new()
	_som_ui_click.stream = load("res://assets/audio/ui/click1.ogg")
	_som_ui_click.bus = "Efeitos"
	add_child(_som_ui_click)

	_som_ui_hover = AudioStreamPlayer.new()
	_som_ui_hover.stream = load("res://assets/audio/ui/rollover1.ogg")
	_som_ui_hover.bus = "Efeitos"
	_som_ui_hover.volume_db = -6.0
	add_child(_som_ui_hover)

	for b: Button in [botao_continuar, botao_novo, botao_configuracoes, botao_sair]:
		if b != null and not b.pressed.is_connected(_tocar_click_ui):
			b.pressed.connect(_tocar_click_ui)


func _tocar_click_ui() -> void:
	if _som_ui_click != null and _som_ui_click.stream != null:
		_som_ui_click.play()


func _tocar_hover_ui() -> void:
	if _som_ui_hover != null and _som_ui_hover.stream != null:
		_som_ui_hover.play()
