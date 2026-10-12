extends RefCounted
## Deterministic rules, independent from UI, input, time and persistence.
## Arrays are row-major from top-left. 1 is dark ink.

const SIDE := 3
const MASKS := [
	[1, 1, 0, 1, 0, 0, 0, 0, 0], # A: elbow
	[1, 1, 1, 0, 0, 0, 0, 0, 0], # B: edge bar
]
const PUZZLES := [
	{
		"title": "Two elbows",
		"start": [0, 0, 0, 0, 0, 0, 0, 0, 0],
		"target": [1, 0, 1, 1, 0, 1, 0, 0, 0],
	},
	{
		"title": "Ink can disappear",
		"start": [0, 1, 0, 1, 0, 0, 0, 0, 1],
		"target": [0, 1, 1, 1, 0, 0, 0, 1, 1],
	},
]

var _board: Array = []
var _puzzle_index := 0
var _selected_mask := 0
var _rotation := 0
var _moves := 0
var _history: Array = []

func _init() -> void:
	reset()

func puzzle_count() -> int:
	return PUZZLES.size()

func get_board() -> Array:
	return _board.duplicate()

func get_target() -> Array:
	return PUZZLES[_puzzle_index]["target"].duplicate()

func get_mask() -> Array:
	var result: Array = MASKS[_selected_mask].duplicate()
	for step in range(_rotation):
		var rotated: Array = []
		rotated.resize(SIDE * SIDE)
		for y in range(SIDE):
			for x in range(SIDE):
				rotated[x * SIDE + (SIDE - 1 - y)] = result[y * SIDE + x]
		result = rotated
	return result

func select_mask(index: int) -> bool:
	if index < 0 or index >= MASKS.size():
		return false
	_selected_mask = index
	return true

func set_rotation(quarter_turns: int) -> void:
	_rotation = posmod(quarter_turns, 4)

func rotate(direction: int = 1) -> void:
	set_rotation(_rotation + direction)

func is_solved() -> bool:
	return _board == get_target()

func mismatch_count() -> int:
	var target := get_target()
	var count := 0
	for i in range(_board.size()):
		if _board[i] != target[i]:
			count += 1
	return count

func preview() -> Array:
	var result := get_board()
	if is_solved():
		return result
	var mask := get_mask()
	for i in range(result.size()):
		result[i] = int(result[i]) ^ int(mask[i])
	return result

func print_mask() -> bool:
	if is_solved():
		return false
	_history.append({
		"board": get_board(), "moves": _moves,
		"mask": _selected_mask, "rotation": _rotation,
	})
	_board = preview()
	_moves += 1
	return true

func undo() -> bool:
	if _history.is_empty():
		return false
	var previous: Dictionary = _history.pop_back()
	_board = previous["board"].duplicate()
	_moves = previous["moves"]
	_selected_mask = previous["mask"]
	_rotation = previous["rotation"]
	return true

func reset() -> void:
	_board = PUZZLES[_puzzle_index]["start"].duplicate()
	_selected_mask = 0
	_rotation = 0
	_moves = 0
	_history.clear()

func can_advance() -> bool:
	return is_solved() and _puzzle_index + 1 < puzzle_count()

func next_puzzle() -> bool:
	if not can_advance():
		return false
	_puzzle_index += 1
	reset()
	return true

func snapshot() -> Dictionary:
	return {
		"puzzle": _puzzle_index, "title": PUZZLES[_puzzle_index]["title"],
		"board": get_board(), "target": get_target(),
		"selected_mask": _selected_mask, "rotation": _rotation,
		"moves": _moves, "history_size": _history.size(),
		"solved": is_solved(),
	}
