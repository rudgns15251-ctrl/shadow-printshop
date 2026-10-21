extends RefCounted
## Shared campaign look: bundled SIL OFL Nanum fonts (unmodified files) and the
## paper / ink / wood / vermilion surfaces of ART_STYLE_BIBLE. Hangul is drawn by
## the bundled faces; only glyphs they lack (a few arrows/marks) may still use the
## engine or system fallback.

const GOTHIC := preload("res://assets/fonts/NanumGothic-Regular.ttf")
const GOTHIC_BOLD := preload("res://assets/fonts/NanumGothic-Bold.ttf")
const MYEONGJO := preload("res://assets/fonts/NanumMyeongjo-Regular.ttf")
const MYEONGJO_BOLD := preload("res://assets/fonts/NanumMyeongjo-Bold.ttf")

const INK := Color("#24211d")
const PAPER := Color("#f4ebdd")
const WOOD := Color("#d8c7ad")
const GREEN := Color("#315d49")
const VERMILION := Color("#8a3f24")
const NIGHT := Color("#1d2430")
const SHADOW := Color("#121110")
const LAMP := Color("#f2d49b")

static func apply(theme: Theme) -> void:
	# Symbols the Nanum faces lack try the engine's bundled font before the OS.
	for face in [GOTHIC, GOTHIC_BOLD, MYEONGJO, MYEONGJO_BOLD]:
		if face.fallbacks.is_empty() and ThemeDB.fallback_font != null:
			face.fallbacks = [ThemeDB.fallback_font]
	theme.default_font = GOTHIC
	for control_type in ["Button", "CheckBox", "OptionButton"]:
		theme.set_font("font", control_type, GOTHIC_BOLD)

## A paper or wood surface that sits on the bench: thin ink edge, soft drop shadow.
static func surface(color: Color, radius: int = 10, vertical_padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = INK.lerp(color, 0.35)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.content_margin_top = vertical_padding
	style.content_margin_bottom = vertical_padding
	style.shadow_color = Color(SHADOW, 0.32)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	style.anti_aliasing = true
	return style

## A pressed-paper key: heavier lower edge so it reads as something to press.
static func key(color: Color, edge: Color, pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(7)
	style.border_color = edge
	style.set_border_width_all(1)
	style.border_width_bottom = 1 if pressed else 3
	style.set_content_margin_all(10)
	style.content_margin_top = 8 + (2 if pressed else 0)
	style.content_margin_bottom = 8 - (2 if pressed else 0)
	style.shadow_color = Color(SHADOW, 0.0 if pressed else 0.22)
	style.shadow_size = 0 if pressed else 3
	style.shadow_offset = Vector2(0, 2)
	style.anti_aliasing = true
	return style

static func title_font(label: Control) -> void:
	label.add_theme_font_override("font", MYEONGJO_BOLD)

static func document_font(label: Control) -> void:
	label.add_theme_font_override("font", MYEONGJO)
