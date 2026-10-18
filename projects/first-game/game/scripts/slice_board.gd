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
var undo_impression := false
var impression_time := 0.0
var success := 0.0:
	set(value):
		success = value
		queue_redraw()
var success_time := 0.0
const IMPRESSION_DURATION := 0.32
const SUCCESS_DURATION := 0.70
const FEEDBACK_DURATION := 0.20
var feedback_time := 0.0
var feedback_new_puzzle := false

func clear_feedback() -> void:
	feedback_time = 0.0
	queue_redraw()
	set_process(impression_time > 0.0 or success_time > 0.0)

func animate_feedback(new_puzzle: bool = false) -> void:
	# Presentation only: independent of the impression/success clocks and board data.
	feedback_new_puzzle = new_puzzle
	feedback_time = FEEDBACK_DURATION
	queue_redraw()
	set_process(true)

func clear_success() -> void:
	success_time = 0.0
	success = 0.0
	set_process(impression_time > 0.0 or feedback_time > 0.0)

func animate_success() -> void:
	success_time = SUCCESS_DURATION
	success = 1.0
	set_process(true)

func clear_impression() -> void:
	impression_time = 0.0
	impression = 0.0
	impression_cells.clear()
	set_process(success_time > 0.0 or feedback_time > 0.0)

func animate_impression(affected: Array, is_undo: bool = false) -> void:
	undo_impression = is_undo
	impression_cells = affected.duplicate()
	impression_time = IMPRESSION_DURATION
	impression = 1.0
	set_process(true)

func _ready() -> void:
	super._ready()
	set_process(false)

func _process(delta: float) -> void:
	# Node-owned clocks avoid retaining callback tweeners when rapid input
	# cancels an effect or the scene exits before the effect finishes.
	if impression_time > 0.0:
		impression_time = maxf(0.0, impression_time - delta)
		var remaining: float = impression_time / IMPRESSION_DURATION
		impression = remaining * remaining
		if impression_time == 0.0:
			impression_cells.clear()
	if success_time > 0.0:
		success_time = maxf(0.0, success_time - delta)
		success = 1.0 - sin((1.0 - success_time / SUCCESS_DURATION) * PI / 2.0)
	if feedback_time > 0.0:
		feedback_time = maxf(0.0, feedback_time - delta)
		queue_redraw()
	set_process(impression_time > 0.0 or success_time > 0.0 or feedback_time > 0.0)

func _exit_tree() -> void:
	clear_feedback()
	clear_impression()
	clear_success()

func set_completed(value: bool) -> void:
	if not value:
		clear_success()
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
	if feedback_time > 0.0:
		# Brief inset rim leaves numbers/markers readable; no transforms to restore.
		var remaining: float = feedback_time / FEEDBACK_DURATION
		var cue := Color("#315d49") if feedback_new_puzzle else ACCENT
		cue.a = remaining
		draw_rect(frame.grow(-4.0 - (1.0 - remaining) * 3.0), cue, false, 3.0)
	if success > 0.0:
		# Trace clockwise inside the existing paper frame, without covering text.
		var rim := frame.grow(-5.0)
		var corners: PackedVector2Array = PackedVector2Array([rim.position, Vector2(rim.end.x, rim.position.y), rim.end, Vector2(rim.position.x, rim.end.y), rim.position])
		var elapsed: float = clampf(1.0 - success_time / SUCCESS_DURATION, 0.0, 1.0)
		var travel: float = smoothstep(0.0, 0.85, elapsed) * 4.0
		var glow := Color("#315d49")
		glow.a = minf(1.0, success * 3.0)
		for side in range(4):
			var portion: float = clampf(travel - side, 0.0, 1.0)
			if portion > 0.0:
				draw_line(corners[side], corners[side].lerp(corners[side + 1], portion), glow, 3.0, true)
	var font: Font = ThemeDB.fallback_font
	var text_size: int = int(maxf(18.0, minf(31.0, width * 0.32)))
	for y in range(3):
		for x in range(3):
			var idx: int = y * 3 + x
			var rect := Rect2(offset + Vector2(x, y) * width + Vector2(3.0, 3.0), Vector2(width - 6.0, width - 6.0))
			var dark: bool = cells[idx] == 1
			# A small paper compression/lift stays inside the tile and never moves text.
			var active: bool = impression > 0.0 and impression_cells.size() == 9 and impression_cells[idx] == 1
			var pressure: float = sin((1.0 - impression_time / IMPRESSION_DURATION) * PI) if active else 0.0
			var paper_rect: Rect2 = rect.grow(-pressure * 1.5)
			# A shallow paper edge and deterministic fibers keep every tile legible.
			draw_rect(Rect2(paper_rect.position + Vector2(0.0, 2.0 + pressure * (2.0 if undo_impression else -1.0)), paper_rect.size), Color("#75634e"))
			draw_rect(paper_rect, INK if dark else PAPER)
			var fiber := Color(0.95, 0.89, 0.78, 0.07) if dark else Color(0.40, 0.31, 0.22, 0.08)
			for line in range(4):
				var fiber_y: float = rect.position.y + rect.size.y * (0.16 + line * 0.21)
				draw_line(Vector2(rect.position.x + 5.0, fiber_y), Vector2(rect.end.x - 5.0, fiber_y + 0.8), fiber, 1.0)
			if active:
				# Print settles inward; undo lifts an outward blue paper rim.
				var rim := Color("#efba76") if dark else ACCENT
				if undo_impression:
					rim = Color("#a4d4e8") if dark else Color("#153f60")
				rim.a = impression * 0.85
				var inset: float = 2.0 + (impression if undo_impression else 1.0 - impression) * 6.0
				draw_rect(rect.grow(-inset), rim, false, 1.0 + impression * 2.0)
			if success > 0.0:
				var settled: float = clampf(success * 1.8 - idx * 0.08, 0.0, 1.0)
				var seal := Color("#a9d6b6") if dark else Color("#315d49")
				seal.a = settled * 0.75
				draw_rect(rect.grow(-5.0), seal, false, 2.0)
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
