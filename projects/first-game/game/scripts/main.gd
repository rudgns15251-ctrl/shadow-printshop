extends Control

const State = preload("res://scripts/game_state.gd")
const BoardView = preload("res://scripts/board_view.gd")
var state = State.new()
var before_view
var after_view
var target_view
var mask_view
var heading: Label
var status: Label
var selection: Label
var after_label: Label
var print_button: Button
var undo_button: Button
var next_button: Button
var mask_buttons: Array[Button] = []

func _ready() -> void:
	get_window().min_size = Vector2i(1040, 840)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	heading = _label(column, "", 28)
	_label(column, "Match CURRENT to TARGET. A stamp flips its 1-cells: 0 becomes 1, 1 becomes 0.\nChoose A/B, rotate, compare the preview, then PRINT. Stamps stay aligned to the full 3x3 board.", 17)

	var boards := HBoxContainer.new()
	boards.add_theme_constant_override("separation", 18)
	column.add_child(boards)
	before_view = _board_card(boards, "CURRENT / before", Vector2(240, 240))
	after_view = _board_card(boards, "AFTER / preview", Vector2(240, 240))
	target_view = _board_card(boards, "TARGET / order", Vector2(240, 240))
	_label(column, "0 = light paper    1 = dark ink    Orange border = cells this stamp will flip.", 16)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 24)
	column.add_child(controls)
	mask_view = _board_card(controls, "SELECTED STAMP", Vector2(120, 120))
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 10)
	controls.add_child(actions)
	selection = _label(actions, "", 18)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 8)
	actions.add_child(choices)
	mask_buttons.append(_button(choices, "1: A / elbow", func(): _select(0)))
	mask_buttons.append(_button(choices, "2: B / bar", func(): _select(1)))
	_button(choices, "Q: rotate left", func(): _rotate(-1))
	_button(choices, "E: rotate right", func(): _rotate(1))
	var commands := HBoxContainer.new()
	commands.add_theme_constant_override("separation", 8)
	actions.add_child(commands)
	print_button = _button(commands, "Space: PRINT", _print)
	undo_button = _button(commands, "U / Z: undo", _undo)
	_button(commands, "R: reset", _reset)
	next_button = _button(commands, "N: next puzzle", _next)
	status = _label(column, "", 20)
	_label(column, "Keyboard: 1 / 2 select | Q / E rotate 90 degrees | Space / Enter print | U / Z undo | R reset | N next\nMouse: click the same action buttons. No dragging or direct cell editing. Close the window to exit.", 16)
	_refresh()

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _board_card(parent: Node, title: String, extent: Vector2) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#141e2d")
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var label := _label(content, title, 18)
	if title == "AFTER / preview":
		after_label = label
	var board = BoardView.new()
	board.custom_minimum_size = extent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(board)
	return board

func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 42
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _refresh() -> void:
	var data: Dictionary = state.snapshot()
	heading.text = "C01 / Shadow Printshop   |   Puzzle %d / %d: %s" % [
		data["puzzle"] + 1, state.puzzle_count(), data["title"]]
	var affected: Array = [] if data["solved"] else state.get_mask()
	before_view.show_cells(state.get_board(), affected)
	after_view.show_cells(state.preview(), affected)
	target_view.show_cells(state.get_target())
	mask_view.show_cells(state.get_mask())
	after_label.text = "AFTER / complete" if data["solved"] else "AFTER / preview"
	selection.text = "Stamp %s   |   Rotation %d degrees clockwise   |   Prints: %d" % [
		"A" if data["selected_mask"] == 0 else "B", data["rotation"] * 90, data["moves"]]
	for i in range(mask_buttons.size()):
		mask_buttons[i].text = ("%d: %s / %s" % [i + 1, "A" if i == 0 else "B",
			"elbow" if i == 0 else "bar"]) + (" [selected]" if i == data["selected_mask"] else "")
	print_button.disabled = data["solved"]
	undo_button.disabled = data["history_size"] == 0
	next_button.disabled = not state.can_advance()
	if data["solved"]:
		if state.can_advance():
			status.text = "MATCH! Next is manual: press N or click 'N: next puzzle' for puzzle 2.\nU / Z: undo | R: reset to retry this puzzle."
		else:
			status.text = "Both puzzles complete. No next puzzle. Close the window to exit.\nU / Z: undo | R: reset to retry this puzzle."
	else:
		status.text = "Different cells: %d   |   Preview is free. Only PRINT counts as a turn." % state.mismatch_count()

func _select(index: int) -> void:
	state.select_mask(index)
	_refresh()

func _rotate(direction: int) -> void:
	state.rotate(direction)
	_refresh()

func _print() -> void:
	state.print_mask()
	_refresh()

func _undo() -> void:
	state.undo()
	_refresh()

func _reset() -> void:
	state.reset()
	_refresh()

func _next() -> void:
	state.next_puzzle()
	_refresh()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _select(0)
		KEY_2: _select(1)
		KEY_Q: _rotate(-1)
		KEY_E: _rotate(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: _print()
		KEY_U, KEY_Z: _undo()
		KEY_R: _reset()
		KEY_N: _next()
		_: return
	get_viewport().set_input_as_handled()
