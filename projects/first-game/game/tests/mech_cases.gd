extends SceneTree
const State = preload("res://scripts/mech_state.gd")
const Original = preload("res://scripts/game_state.gd")
const DATA = preload("res://data/mech_data.gd")
# Independent literal clockwise fixtures, not State.get_mask() expectations.
const MASKS := [11, 38, 416, 200, 7, 292, 448, 73]
var failures := 0
var checks := 0
var sequences := 0

func _initialize() -> void:
	call_deferred("_run")

func check(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		printerr("MECH FAIL %s: %s != %s" % [label, actual, expected])

func packed(board: Array) -> int:
	var value := 0
	for i in range(9):
		value |= int(board[i]) << i
	return value

func apply(state, action: int) -> bool:
	check(state.select_mask(int(action / 4)), true, "allowed selection")
	state.set_rotation(action % 4)
	return state.print_mask()

func solve(state, row: Dictionary) -> void:
	for action in row["solution"]:
		check(apply(state, int(action)), true, "solution print accepted")
	check(state.get_board(), row["target"], "solution target")
	check(state.is_solved(), true, "solution complete")
	var before: Dictionary = state.snapshot()
	check(state.print_mask(), false, "completed print rejected")
	check(state.snapshot(), before, "completed unchanged")

func at(index: int):
	var state = State.new()
	for i in range(index):
		solve(state, DATA.PUZZLES[i])
		check(state.next_puzzle(), true, "manual progression")
	return state

func minimum(row: Dictionary) -> Array:
	var start := packed(row["start"])
	var distances := {start: 0}
	var queue := [start]
	var cursor := 0
	while cursor < queue.size():
		var board: int = queue[cursor]
		cursor += 1
		for stamp in row["allowed_masks"]:
			for rotation in range(4):
				var next: int = board ^ MASKS[int(stamp) * 4 + rotation]
				if not distances.has(next):
					distances[next] = distances[board] + 1
					queue.append(next)
	return [distances.get(packed(row["target"]), -1), queue.size()]

func _run() -> void:
	check(DATA.PUZZLES.size(), 8, "eight puzzles")
	check(Original.PUZZLES.size(), 2, "original count preserved")
	for i in range(2):
		for field in ["title", "start", "target"]:
			check(DATA.PUZZLES[i][field], Original.PUZZLES[i][field], "original fixture preserved")
	for index in range(8):
		var row: Dictionary = DATA.PUZZLES[index]
		var state = at(index)
		var initial: Dictionary = state.snapshot()
		check(minimum(row), [row["minimum_prints"], row["reachable_states"]], "exhaustive BFS")
		for stamp in row["allowed_masks"]:
			state.select_mask(int(stamp))
			for direction in [-1, 1]:
				state.set_rotation(0)
				var mask: Array = state.get_mask()
				for turn in range(4):
					state.rotate(direction)
				check(state.get_mask(), mask, "four rotations")
				check(state.get_board(), row["start"], "rotation free")
		for invalid in [-1, 2]:
			check(state.select_mask(invalid), false, "invalid stamp")
		if not 0 in row["allowed_masks"]:
			check(state.select_mask(0), false, "restricted A")
		state.reset()
		# Find and execute an actually wrong one-print answer independently.
		for stamp in row["allowed_masks"]:
			var action := int(stamp) * 4
			if packed(row["start"]) ^ MASKS[action] != packed(row["target"]):
				check(apply(state, action), true, "wrong answer accepted as move")
				check(state.is_solved(), false, "wrong answer incomplete")
				break
		state.reset()
		solve(state, row)
		check(state.can_advance(), index < 7, "last boundary")
		state.reset()
		# 1000 deterministic length-12 input sequences per board, no RNG.
		# First print uses default selection so complete undo restores full initial snapshot.
		for case_id in range(1000):
			var code := case_id
			var reference := packed(row["start"])
			var history: Array = []
			for step in range(12):
				var choice: int = code % (row["allowed_masks"].size() * 4)
				var stamp: int = row["allowed_masks"][int(choice / 4)]
				var action: int = stamp * 4 + choice % 4
				if step > 0:
					code = int(code / (row["allowed_masks"].size() * 4))
				if step == 0:
					action = int(row["allowed_masks"][0]) * 4
				state.select_mask(int(action / 4))
				state.set_rotation(action % 4)
				var before: Dictionary = state.snapshot()
				var accepted := reference != packed(row["target"])
				check(state.print_mask(), accepted, "sequence acceptance")
				if accepted:
					history.append(before)
					reference ^= MASKS[action]
				check(packed(state.get_board()), reference, "independent sequence board")
			while not history.is_empty():
				check(state.undo(), true, "sequence undo")
				check(state.snapshot(), history.pop_back(), "full pre-print snapshot")
			check(state.snapshot(), initial, "undo initial restoration")
			check(state.undo(), false, "empty undo")
			state.reset()
			sequences += 1
	check(sequences, 8000, "all sequence cases finished")
	print("MECH checks=%d sequences=%d failures=%d" % [checks, sequences, failures])
	quit(1 if failures else 0)
