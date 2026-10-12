extends Control
## Built-in flat drawing and default font; no imported assets.
var cells: Array = []
var highlights: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func show_cells(values: Array, affected: Array = []) -> void:
	cells = values.duplicate()
	highlights = affected.duplicate()
	queue_redraw()

func _draw() -> void:
	if cells.size() != 9:
		return
	var extent: float = minf(size.x, size.y)
	var tile := extent / 3.0
	var offset := (size - Vector2(extent, extent)) / 2.0
	var font := ThemeDB.fallback_font
	var font_size := int(clampf(tile * 0.30, 14.0, 26.0))
	for y in range(3):
		for x in range(3):
			var i := y * 3 + x
			var rect := Rect2(offset + Vector2(x, y) * tile + Vector2(3, 3),
				Vector2(tile - 6, tile - 6))
			var dark: bool = cells[i] == 1
			var fill := Color("#26354b") if dark else Color("#eee7d5")
			var ink := Color("#ffffff") if dark else Color("#25344a")
			draw_rect(rect, fill)
			draw_rect(rect, Color("#64748b"), false, 1.0)
			if highlights.size() == 9 and highlights[i] == 1:
				draw_rect(rect.grow(-3), Color("#eea64a"), false, 3.0)
			var text := str(cells[i])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var baseline := rect.get_center() + Vector2(-width / 2.0,
				(font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
			draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
