extends "res://scripts/board_view.gd"
## Accessible paper/ink rendering; independent 0/1 indicators and highlight symbols.
const PAPER := Color("#f4ebdd")
const INK := Color("#24211d")
const ACCENT := Color("#8a3f24")

const WOOD = preload("res://assets/art/press_wood.svg")
var frame_color: Color = INK
var completed := false

func set_completed(value: bool) -> void:
	completed = value
	queue_redraw()

func _draw() -> void:
	if cells.size() != 9:
		return
	var edge: float = maxf(0.0, minf(size.x, size.y) - 16.0)
	var width: float = edge / 3.0
	var offset: Vector2 = (size - Vector2(edge, edge)) / 2.0
	var frame := Rect2(offset - Vector2(8, 8), Vector2(edge + 16, edge + 16))
	draw_texture_rect(WOOD, frame, false)
	draw_rect(frame.grow(-2), Color("#315d49") if completed else frame_color, false, 3.0)
	var font: Font = ThemeDB.fallback_font
	var text_size: int = int(maxf(18.0, minf(31.0, width * 0.32)))
	for y in range(3):
		for x in range(3):
			var idx: int = y * 3 + x
			var rect := Rect2(offset + Vector2(x, y) * width + Vector2(3.0, 3.0), Vector2(width - 6.0, width - 6.0))
			var dark: bool = cells[idx] == 1
			draw_rect(rect, INK if dark else PAPER)
			draw_rect(rect, INK, false, 1.5)
			if highlights.size() == 9 and highlights[idx] == 1:
				draw_rect(rect.grow(-4.0), Color("#efba76") if dark else ACCENT, false, 3.0)
				var left := rect.position + Vector2(7.0, 7.0)
				draw_colored_polygon(PackedVector2Array([left, left + Vector2(13.0, 0.0), left + Vector2(0.0, 13.0)]), Color("#efba76") if dark else ACCENT)
			var symbol: String = str(cells[idx])
			var size_text: Vector2 = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size)
			var ascent: float = font.get_ascent(text_size)
			var descent: float = font.get_descent(text_size)
			var pos: Vector2 = rect.get_center() + Vector2(-size_text.x / 2.0, (ascent - descent) / 2.0)
			draw_string(font, pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, PAPER if dark else INK)
