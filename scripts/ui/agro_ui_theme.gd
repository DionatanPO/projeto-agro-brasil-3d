extends RefCounted
class_name AgroUITheme
## Design system minimalista/moderno 100% em codigo (sem assets).
## Superficies claras, texto escuro, um unico destaque verde.

const INK := Color("#21252b")
const MUTED_INK := Color("#6b7280")
const CREAM := Color("#ffffff")
const FIELD_GREEN := Color("#1e6b3a")
const ACCENT_GREEN := Color("#2e7d4f")
const ACCENT_HOVER := Color("#35945c")
const ACCENT_PRESS := Color("#256b43")
const PANEL_BG := Color("#ffffff")
const PANEL_DARK := Color("#232a33")
const SOFT_BG := Color("#f1f3f5")
const BORDER := Color("#d9dee4")
const DISABLED_BG := Color("#e5e7eb")
const DISABLED_INK := Color("#9aa1ab")

static func apply_to(root: Control) -> void:
	var ui_theme := Theme.new()
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_color("font_hover_color", "Button", INK)
	ui_theme.set_color("font_pressed_color", "Button", CREAM)
	ui_theme.set_color("font_focus_color", "Button", INK)
	ui_theme.set_color("font_disabled_color", "Button", DISABLED_INK)
	ui_theme.set_font_size("font_size", "Label", 14)
	ui_theme.set_font_size("font_size", "Button", 15)
	ui_theme.set_stylebox("panel", "PanelContainer", _panel(PANEL_BG, 12, 14))
	ui_theme.set_stylebox("normal", "Button", _button(PANEL_BG, BORDER, 8, 8))
	ui_theme.set_stylebox("hover", "Button", _button(SOFT_BG, BORDER, 8, 8))
	ui_theme.set_stylebox("pressed", "Button", _button(ACCENT_PRESS, ACCENT_PRESS, 8, 8))
	ui_theme.set_stylebox("disabled", "Button", _button(DISABLED_BG, DISABLED_BG, 8, 8))
	ui_theme.set_stylebox("focus", "Button", _focus())
	ui_theme.set_stylebox("panel", "TabContainer", _panel(PANEL_BG, 8, 0))
	ui_theme.set_stylebox("tab_selected", "TabContainer", _button(ACCENT_GREEN, ACCENT_GREEN, 6, 8))
	ui_theme.set_stylebox("tab_unselected", "TabContainer", _button(SOFT_BG, BORDER, 6, 8))
	ui_theme.set_stylebox("tab_hover", "TabContainer", _button(DISABLED_BG, BORDER, 6, 8))
	ui_theme.set_color("font_selected_color", "TabContainer", CREAM)
	ui_theme.set_color("font_unselected_color", "TabContainer", MUTED_INK)
	ui_theme.set_color("font_hover_color", "TabContainer", INK)
	root.theme = ui_theme

static func style_panel(panel: PanelContainer, variant: String = "light") -> void:
	var bg := PANEL_BG
	if variant == "dark" or variant == "screws":
		bg = PANEL_DARK
	panel.add_theme_stylebox_override("panel", _panel(bg, 12, 14))

static func style_primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button(ACCENT_GREEN, ACCENT_GREEN, 8, 10))
	button.add_theme_stylebox_override("hover", _button(ACCENT_HOVER, ACCENT_HOVER, 8, 10))
	button.add_theme_stylebox_override("pressed", _button(ACCENT_PRESS, ACCENT_PRESS, 8, 10))
	button.add_theme_stylebox_override("disabled", _button(DISABLED_BG, DISABLED_BG, 8, 10))
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_color_override("font_pressed_color", CREAM)
	button.add_theme_color_override("font_focus_color", CREAM)
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)
	button.add_theme_font_size_override("font_size", 15)

static func style_secondary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button(PANEL_BG, BORDER, 8, 10))
	button.add_theme_stylebox_override("hover", _button(SOFT_BG, BORDER, 8, 10))
	button.add_theme_stylebox_override("pressed", _button(DISABLED_BG, BORDER, 8, 10))
	button.add_theme_stylebox_override("disabled", _button(DISABLED_BG, DISABLED_BG, 8, 10))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)


static func style_text_menu_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 0
	empty.content_margin_right = 0
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4

	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_stylebox_override("disabled", empty)

	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.85, 0.89, 0.86, 0.75))
	button.add_theme_color_override("font_hover_color", Color(0.38, 1.0, 0.62, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.25, 0.85, 0.45, 1.0))
	button.add_theme_color_override("font_focus_color", Color(0.38, 1.0, 0.62, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 0.35))

	button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	button.add_theme_constant_override("shadow_offset_x", 1)
	button.add_theme_constant_override("shadow_offset_y", 2)


static func style_glass_button(button: Button, is_primary: bool = false) -> void:
	var radius := 10
	var inset_h := 22
	var inset_v := 14

	if is_primary:
		# Botão Primário: Vidro escuro sofisticado com contorno e brilho verde esmeralda
		var normal_bg := Color(0.05, 0.16, 0.10, 0.78)
		var normal_border := Color(0.24, 0.82, 0.46, 0.70)
		var hover_bg := Color(0.10, 0.35, 0.20, 0.88)
		var hover_border := Color(0.38, 1.0, 0.62, 1.0)
		var press_bg := Color(0.06, 0.22, 0.13, 0.95)
		var press_border := Color(0.28, 0.85, 0.48, 1.0)
		var glow_normal := Color(0.12, 0.65, 0.32, 0.25)
		var glow_hover := Color(0.24, 0.95, 0.50, 0.45)

		button.add_theme_stylebox_override("normal", _glass_stylebox(normal_bg, normal_border, 2, glow_normal, 8, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("hover", _glass_stylebox(hover_bg, hover_border, 2, glow_hover, 14, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("pressed", _glass_stylebox(press_bg, press_border, 2, glow_normal, 4, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("disabled", _glass_stylebox(Color(0.08, 0.08, 0.08, 0.5), Color(0.2, 0.2, 0.2, 0.3), 1, Color(0, 0, 0, 0), 0, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("focus", _focus_glass(hover_border, radius))

		button.add_theme_color_override("font_color", Color("#ffffff"))
		button.add_theme_color_override("font_hover_color", Color("#ffffff"))
		button.add_theme_color_override("font_pressed_color", Color("#c8f5d8"))
		button.add_theme_color_override("font_focus_color", Color("#ffffff"))
		button.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.4))
		button.add_theme_font_size_override("font_size", 16)
	else:
		# Botão Secundário: Vidro translúcido escuro refinado com acento esmeralda no hover
		var normal_bg := Color(0.03, 0.07, 0.05, 0.65)
		var normal_border := Color(1.0, 1.0, 1.0, 0.16)
		var hover_bg := Color(0.08, 0.18, 0.12, 0.85)
		var hover_border := Color(0.30, 0.88, 0.52, 0.85)
		var press_bg := Color(0.05, 0.12, 0.08, 0.92)
		var press_border := Color(0.22, 0.75, 0.42, 0.88)
		var glow_normal := Color(0.0, 0.0, 0.0, 0.30)
		var glow_hover := Color(0.18, 0.70, 0.38, 0.32)

		button.add_theme_stylebox_override("normal", _glass_stylebox(normal_bg, normal_border, 1, glow_normal, 6, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("hover", _glass_stylebox(hover_bg, hover_border, 2, glow_hover, 12, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("pressed", _glass_stylebox(press_bg, press_border, 1, glow_normal, 3, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("disabled", _glass_stylebox(Color(0.08, 0.08, 0.08, 0.4), Color(0.2, 0.2, 0.2, 0.2), 1, Color(0, 0, 0, 0), 0, radius, inset_v, inset_h))
		button.add_theme_stylebox_override("focus", _focus_glass(hover_border, radius))

		button.add_theme_color_override("font_color", Color("#e6ece8"))
		button.add_theme_color_override("font_hover_color", Color("#ffffff"))
		button.add_theme_color_override("font_pressed_color", Color("#c0e6ce"))
		button.add_theme_color_override("font_focus_color", Color("#ffffff"))
		button.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.35))
		button.add_theme_font_size_override("font_size", 15)


static func _glass_stylebox(bg: Color, border: Color, border_w: int, glow: Color, shadow_sz: int, radius: int, inset_v: int, inset_h: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.corner_detail = 12
	style.set_border_width_all(border_w)
	style.border_color = border
	style.shadow_color = glow
	style.shadow_size = shadow_sz
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = inset_h
	style.content_margin_right = inset_h
	style.content_margin_top = inset_v
	style.content_margin_bottom = inset_v
	return style


static func _focus_glass(border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(2)
	style.border_color = border
	style.set_corner_radius_all(radius + 2)
	style.corner_detail = 12
	return style


static func set_label_color(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)

static func _panel(bg: Color, radius: int, inset: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	if bg == PANEL_DARK:
		style.set_border_width_all(0)
	else:
		style.set_border_width_all(1)
		style.border_color = BORDER
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	return style

static func _button(bg: Color, border: Color, radius: int, inset: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	return style

static func _focus() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(2)
	style.border_color = ACCENT_GREEN
	style.set_corner_radius_all(8)
	return style
