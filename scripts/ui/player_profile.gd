extends Control
## PlayerProfile — card compacto de HUD: avatar circular, nível e barra de XP.
## Compatível com Godot 4.x.

signal level_up_reached(new_level: int)

# ── Nós ──────────────────────────────────────────────────────────────────────
@onready var _fundo:      Panel          = $Fundo
@onready var _avatar:     TextureRect    = $Layout/AvatarMask/Avatar
@onready var _mask:       Control        = $Layout/AvatarMask
@onready var _level_label: Label         = $Layout/Info/NivelRow/LevelLabel
@onready var _xp_bar:     ProgressBar    = $Layout/Info/XPBar
@onready var _xp_label:   Label          = $Layout/Info/XPLabel

# ── Constantes ────────────────────────────────────────────────────────────────
const MAX_LEVEL:  int   = 30
const XP_BASE:    int   = 100
const XP_GROWTH:  float = 1.5

## Posição e tamanho fixos no canto superior esquerdo.
const HUD_MARGIN := Vector2(20.0, 20.0)
const HUD_SIZE   := Vector2(300.0, 80.0)
const AVATAR_PX  := 56

# ── Estado ────────────────────────────────────────────────────────────────────
var _player_xp:    int = 0
var _player_level: int = 1


# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Tamanho e posição fixos — impedindo que o Control se expanda.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = HUD_SIZE
	size               = HUD_SIZE
	position           = HUD_MARGIN

	_estilizar_fundo()
	_estilizar_avatar()
	_estilizar_xp_bar()

	# Carrega avatar padrão (falha silenciosa se não existir).
	set_avatar_from_path("res://assets/imagens/ui_personagem.png")

	# Conecta XPManager se disponível.
	if not is_instance_valid(XPManager):
		push_warning("PlayerProfile: XPManager não encontrado.")
		_update_display()
		return

	if not XPManager.xp_changed.is_connected(_on_xp_changed):
		XPManager.xp_changed.connect(_on_xp_changed)
	if not XPManager.level_changed.is_connected(_on_level_changed):
		XPManager.level_changed.connect(_on_level_changed)
	if not XPManager.level_up_reached.is_connected(_on_level_up_reached):
		XPManager.level_up_reached.connect(_on_level_up_reached)

	_player_xp    = XPManager.get_xp()
	_player_level = clampi(XPManager.get_level(), 1, MAX_LEVEL)
	_update_display()


# ── Estilo do fundo (glassmorphism escuro) ────────────────────────────────────
func _estilizar_fundo() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.10, 0.06, 0.82)
	style.set_corner_radius_all(14)
	style.corner_detail = 16
	style.set_border_width_all(1)
	style.border_color = Color(0.28, 0.75, 0.42, 0.55)
	style.shadow_color  = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size   = 8
	style.shadow_offset = Vector2(0, 3)
	_fundo.add_theme_stylebox_override("panel", style)


# ── Estilo do avatar (quadrado com clip = circulo via script) ─────────────────
func _estilizar_avatar() -> void:
	# A máscara tem tamanho fixo; clip_contents = true já está na cena.
	_mask.custom_minimum_size = Vector2(AVATAR_PX, AVATAR_PX)

	# Anel de borda verde: adicionado DENTRO do AvatarMask como overlay.
	# Assim o HBoxContainer não o trata como um segundo item de layout.
	var anel := Panel.new()
	anel.name = "AvatarAnel"
	anel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anel.set_anchors_preset(Control.PRESET_FULL_RECT)
	anel.anchor_right  = 1.0
	anel.anchor_bottom = 1.0
	_mask.add_child(anel)

	var anel_style := StyleBoxFlat.new()
	anel_style.bg_color = Color(0, 0, 0, 0)  # transparente — só a borda aparece
	anel_style.set_corner_radius_all(AVATAR_PX / 2)
	anel_style.corner_detail = 20
	anel_style.set_border_width_all(2)
	anel_style.border_color = Color(0.30, 0.90, 0.50, 0.80)
	anel.add_theme_stylebox_override("panel", anel_style)

	# TextureRect preenche o mask sem overflow.
	_avatar.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ── Estilo da barra de XP ─────────────────────────────────────────────────────
func _estilizar_xp_bar() -> void:
	# Fundo da barra.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.15, 0.12, 0.70)
	bg.set_corner_radius_all(5)
	bg.set_border_width_all(1)
	bg.border_color = Color(1, 1, 1, 0.10)

	# Preenchimento da barra.
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.22, 0.85, 0.48, 1.0)
	fill.set_corner_radius_all(5)
	fill.shadow_color = Color(0.10, 0.75, 0.35, 0.55)
	fill.shadow_size  = 4

	_xp_bar.add_theme_stylebox_override("background", bg)
	_xp_bar.add_theme_stylebox_override("fill",       fill)
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter    = Control.MOUSE_FILTER_IGNORE


# ── API pública ───────────────────────────────────────────────────────────────
func set_avatar_texture(texture: Texture2D) -> void:
	_avatar.texture = texture


func set_avatar_from_path(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("PlayerProfile: arquivo não encontrado: " + path)
		return
	var tex := load(path) as Texture2D
	if tex:
		set_avatar_texture(tex)
	else:
		push_warning("PlayerProfile: não foi possível carregar: " + path)


# ── Callbacks XPManager ───────────────────────────────────────────────────────
func _on_xp_changed(_amount: int, total: int) -> void:
	_player_xp = maxi(0, total)
	_update_display()


func _on_level_changed(_old: int, new_level: int) -> void:
	_player_level = clampi(new_level, 1, MAX_LEVEL)
	_update_display()


func _on_level_up_reached(new_level: int) -> void:
	level_up_reached.emit(new_level)


# ── Atualiza display ──────────────────────────────────────────────────────────
func _update_display() -> void:
	if not is_node_ready():
		return

	_level_label.text = "%02d" % _player_level

	if _player_level >= MAX_LEVEL:
		_xp_bar.value   = 100.0
		_xp_label.text  = "NÍVEL MÁXIMO"
		return

	var xp_atual   := _get_total_xp_for_level(_player_level)
	var xp_proximo := _get_total_xp_for_level(_player_level + 1)
	var xp_needed  := xp_proximo - xp_atual
	var xp_earned  := maxi(0, _player_xp - xp_atual)

	var progress := 0.0
	if xp_needed > 0:
		progress = clampf(float(xp_earned) / float(xp_needed), 0.0, 1.0)

	_xp_bar.value  = progress * 100.0
	_xp_label.text = "%d / %d XP" % [mini(xp_earned, xp_needed), xp_needed]


# ── Helpers XP ────────────────────────────────────────────────────────────────
func _get_total_xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var total := 0
	for lv in range(1, mini(level, MAX_LEVEL + 1)):
		total += int(XP_BASE * pow(XP_GROWTH, lv - 1))
	return total
