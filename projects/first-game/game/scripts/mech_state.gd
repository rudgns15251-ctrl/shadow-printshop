extends "res://scripts/game_state.gd"
## Additive experiment: inherited XOR, print history, rotation and undo semantics.
const DATA = preload("res://data/mech_data.gd")

func puzzle_data() -> Array:
	return DATA.PUZZLES

func puzzle_count() -> int:
	return puzzle_data().size()

func get_target() -> Array:
	return puzzle_data()[_puzzle_index]["target"].duplicate()

func select_mask(index: int) -> bool:
	if not index in puzzle_data()[_puzzle_index]["allowed_masks"]:
		return false
	return super.select_mask(index)

func reset() -> void:
	_board = puzzle_data()[_puzzle_index]["start"].duplicate()
	_selected_mask = int(puzzle_data()[_puzzle_index]["allowed_masks"][0])
	_rotation = 0
	_moves = 0
	_history.clear()

func snapshot() -> Dictionary:
	return {
		"puzzle": _puzzle_index, "title": puzzle_data()[_puzzle_index]["title"],
		"board": get_board(), "target": get_target(),
		"selected_mask": _selected_mask, "rotation": _rotation,
		"moves": _moves, "history_size": _history.size(), "solved": is_solved(),
	}
