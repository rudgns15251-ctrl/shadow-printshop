extends "res://scripts/board_view.gd"
## Accessible paper/ink rendering; independent 0/1 indicators and highlight symbols.
const PAPER := Color("#f4ebdd")
const INK := Color("#24211d")
const ACCENT := Color("#8a3f24")

const WOOD = preload("res://assets/art/press_wood.svg")
var frame_color: Color = INK
var completed := false
var impression_cells: Array = []
var impression := 0.0:
	set(value):
		impression = value
		queue_redraw()
var impression_tween: Tween

func clear_impression() -> void:
	if impression_tween != null:
		impression_tween.kill()
		impression_tween = null
	impression = 0.0
	impression_cells.clear()

func animate_impression(affected: Array) -> void:
	clear_impression()
	impression_cells = affected.duplicate()
	impression = 1.0
	impression_tween = create_tween()
	impression_tween.tween_property(self, "impression", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	impression_tween.tween_callback(clear_impression)

func _exit_tree() -> void:
	clear_impression()

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
			# A shallow paper edge and deterministic fibers keep every tile legible.
			draw_rect(Rect2(rect.position + Vector2(0.0, 2.0), rect.size), Color("#75634e"))
			draw_rect(rect, INK if dark else PAPER)
			var fiber := Color(0.95, 0.89, 0.78, 0.07) if dark else Color(0.40, 0.31, 0.22, 0.08)
			for line in range(4):
				var fiber_y: float = rect.position.y + rect.size.y * (0.16 + line * 0.21)
				draw_line(Vector2(rect.position.x + 5.0, fiber_y), Vector2(rect.end.x - 5.0, fiber_y + 0.8), fiber, 1.0)
			if impression > 0.0 and impression_cells.size() == 9 and impression_cells[idx] == 1:
				# The impression settles inward without moving the board or its text.
				var rim := Color("#efba76") if dark else ACCENT
				rim.a = impression * 0.85
				draw_rect(rect.grow(-2.0 - (1.0 - impression) * 4.0), rim, false, 1.0 + impression * 2.0)
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
