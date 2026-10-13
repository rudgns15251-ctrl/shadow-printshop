extends "res://scripts/mech_state.gd"
## Six-puzzle state with verified, lossless undo history persistence.
const SCHEMA_VERSION := 1
const PUZZLE_SET_VERSION := 1

func export_progress() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"puzzle_set_version": PUZZLE_SET_VERSION,
		"puzzle": _puzzle_index,
		"board": _board.duplicate(),
		"selected_mask": _selected_mask,
		"rotation": _rotation,
		"moves": _moves,
		"history": _history.duplicate(true),
	}

static func _valid_board(value: Variant) -> bool:
	if not value is Array or value.size() != 9:
		return false
	for cell in value:
		if not _whole(cell, 0, 1):
			return false
	return true

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value == floorf(float(value)) and value >= minimum and value <= maximum

static func _integer_board(value: Array) -> Array:
	var result: Array = []
	for cell in value:
		result.append(int(cell))
	return result

func import_progress(data: Variant) -> bool:
	# Validate all fields and reconstruct every historical print before mutating this instance.
	if not data is Dictionary:
		return false
	for key in ["schema_version", "puzzle_set_version", "puzzle", "board", "selected_mask", "rotation", "moves", "history"]:
		if not data.has(key):
			return false
	if data["schema_version"] != SCHEMA_VERSION or data["puzzle_set_version"] != PUZZLE_SET_VERSION:
		return false
	if not _whole(data["puzzle"], 0, puzzle_count() - 1):
		return false
	var puzzle_index: int = int(data["puzzle"])
	var allowed: Array = puzzle_data()[puzzle_index]["allowed_masks"]
	if not _whole(data["selected_mask"], 0, 1) or not (int(data["selected_mask"]) in allowed):
		return false
	if not _whole(data["rotation"], 0, 3) or not _valid_board(data["board"]):
		return false
	if not data["history"] is Array or data["history"].size() > 10000:
		return false
	if not _whole(data["moves"], 0, 10000) or data["moves"] != data["history"].size():
		return false
	var replay = get_script().new()
	replay._puzzle_index = puzzle_index
	replay.reset()
	for index in range(data["history"].size()):
		var previous = data["history"][index]
		if not previous is Dictionary:
			return false
		for key in ["board", "moves", "mask", "rotation"]:
			if not previous.has(key):
				return false
		if not _valid_board(previous["board"]) or _integer_board(previous["board"]) != replay.get_board():
			return false
		if not _whole(previous["moves"], index, index):
			return false
		if not _whole(previous["mask"], 0, 1) or not (int(previous["mask"]) in allowed):
			return false
		if not _whole(previous["rotation"], 0, 3):
			return false
		if not replay.select_mask(int(previous["mask"])):
			return false
		replay.set_rotation(int(previous["rotation"]))
		if not replay.print_mask():
			return false
	if replay.get_board() != _integer_board(data["board"]) or replay.snapshot()["moves"] != data["moves"]:
		return false
	var clean_history: Array = []
	for previous in data["history"]:
		clean_history.append({"board": _integer_board(previous["board"]), "moves": int(previous["moves"]),
			"mask": int(previous["mask"]), "rotation": int(previous["rotation"])})
	_board = _integer_board(data["board"])
	_puzzle_index = puzzle_index
	_selected_mask = int(data["selected_mask"])
	_rotation = int(data["rotation"])
	_moves = int(data["moves"])
	_history = clean_history
	return true
