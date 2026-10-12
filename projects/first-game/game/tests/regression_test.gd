extends SceneTree
## Always-on assertions of the real state API; no UI, mocks or private-state edits.
const State = preload("res://scripts/game_state.gd")
# Independent row-major fixtures. Do not derive expectations from State constants.
const MASKS := [
	[
		[1, 1, 0, 1, 0, 0, 0, 0, 0],
		[0, 1, 1, 0, 0, 1, 0, 0, 0],
		[0, 0, 0, 0, 0, 1, 0, 1, 1],
		[0, 0, 0, 1, 0, 0, 1, 1, 0],
	],
	[
		[1, 1, 1, 0, 0, 0, 0, 0, 0],
		[0, 0, 1, 0, 0, 1, 0, 0, 1],
		[0, 0, 0, 0, 0, 0, 1, 1, 1],
		[1, 0, 0, 1, 0, 0, 1, 0, 0],
	],
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
const EXIT_FAILURE := 1
var checks := 0
var failures := 0
var completed_scenarios := 0
var sequence_cases := 0

func _initialize() -> void:
	call_deferred("_run")

# Godot's built-in assert may be omitted in release builds. These checks are not.
func _expect(actual: Variant, expected: Variant, context: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		printerr("REGRESSION FAIL: %s | expected=%s actual=%s" % [context, expected, actual])

func _expected_snapshot(puzzle: int, board: Array, selected: int = 0,
		rotation: int = 0, moves: int = 0, history: int = 0) -> Dictionary:
	return {
		"puzzle": puzzle, "title": PUZZLES[puzzle]["title"],
		"board": board.duplicate(), "target": PUZZLES[puzzle]["target"].duplicate(),
		"selected_mask": selected, "rotation": rotation, "moves": moves,
		"history_size": history, "solved": board == PUZZLES[puzzle]["target"],
	}

func _expect_state(state, expected: Dictionary, context: String) -> void:
	_expect(state.snapshot(), expected, context + " snapshot")
	_expect(state.get_board(), expected["board"], context + " board")
	_expect(state.get_target(), expected["target"], context + " target")
	_expect(state.get_mask(), MASKS[expected["selected_mask"]][expected["rotation"]],
		context + " mask")
	_expect(state.is_solved(), expected["solved"], context + " goal")
	_expect(state.can_advance(), expected["solved"] and expected["puzzle"] == 0,
		context + " advance availability")
	var different := 0
	for cell in range(9):
		if expected["board"][cell] != expected["target"][cell]:
			different += 1
	_expect(state.mismatch_count(), different, context + " mismatch count")

func _flip(board: Array, mask: Array) -> Array:
	var result: Array = board.duplicate()
	for cell in range(9):
		if mask[cell] == 1:
			result[cell] = 1 - board[cell]
	return result

func _solve_first(state) -> void:
	_expect(state.print_mask(), true, "puzzle 1 print A0")
	state.rotate()
	_expect(state.print_mask(), true, "puzzle 1 print A90")
	_expect_state(state, _expected_snapshot(0, PUZZLES[0]["target"], 0, 1, 2, 2),
		"puzzle 1 solved")

func _new_at(puzzle: int):
	var state = State.new()
	if puzzle == 1:
		_solve_first(state)
		_expect(state.next_puzzle(), true, "enter puzzle 2")
	_expect_state(state, _expected_snapshot(puzzle, PUZZLES[puzzle]["start"]), "new puzzle")
	return state

func _test_selection_rotation() -> void:
	var state = State.new()
	_expect(state.puzzle_count(), 2, "two existing puzzles")
	_expect_state(state, _expected_snapshot(0, PUZZLES[0]["start"]), "initial")
	for selected in range(2):
		_expect(state.select_mask(selected), true, "select valid stamp")
		state.set_rotation(0)
		for turn in range(1, 5):
			state.rotate()
			_expect_state(state, _expected_snapshot(0, PUZZLES[0]["start"], selected, turn % 4),
				"clockwise %d/%d" % [selected, turn])
		for turn in range(1, 5):
			state.rotate(-1)
			_expect_state(state, _expected_snapshot(0, PUZZLES[0]["start"], selected, (4 - turn) % 4),
				"counterclockwise %d/%d" % [selected, turn])
		for pair in [[-9, 3], [-5, 3], [-4, 0], [-1, 3], [0, 0], [1, 1], [3, 3], [4, 0], [5, 1], [9, 1]]:
			state.set_rotation(pair[0])
			_expect_state(state, _expected_snapshot(0, PUZZLES[0]["start"], selected, pair[1]),
				"normalized rotation %d" % pair[0])
		var before: Dictionary = state.snapshot()
		_expect(state.select_mask(1 - selected), true, "switch stamp retaining orientation")
		var switched: Dictionary = before.duplicate(true)
		switched["selected_mask"] = 1 - selected
		_expect_state(state, switched, "switch preserves board, turns and orientation")
		for invalid in [-1, 2, 99]:
			_expect(state.select_mask(invalid), false, "reject invalid stamp %d" % invalid)
			_expect_state(state, switched, "invalid selection unchanged")
	completed_scenarios += 1

func _test_print_undo_reset() -> void:
	for puzzle in range(2):
		var state = _new_at(puzzle)
		var initial: Dictionary = _expected_snapshot(puzzle, PUZZLES[puzzle]["start"])
		_expect(state.undo(), false, "empty undo")
		_expect(state.next_puzzle(), false, "unsolved next")
		_expect_state(state, initial, "rejected actions unchanged")
		_expect(state.select_mask(1), true, "choose B")
		state.set_rotation(1)
		var before: Dictionary = _expected_snapshot(puzzle, PUZZLES[puzzle]["start"], 1, 1)
		var printed: Array = [0, 0, 1, 0, 0, 1, 0, 0, 1] if puzzle == 0 else [0, 1, 1, 1, 0, 1, 0, 0, 0]
		_expect(state.preview(), printed, "literal XOR preview on puzzle %d" % puzzle)
		_expect(state.preview(), printed, "repeated preview")
		_expect_state(state, before, "preview has no side effects")
		_expect(state.print_mask(), true, "first B90 print")
		_expect_state(state, _expected_snapshot(puzzle, printed, 1, 1, 1, 1), "first print")
		_expect(state.print_mask(), true, "second identical print")
		_expect_state(state, _expected_snapshot(puzzle, PUZZLES[puzzle]["start"], 1, 1, 2, 2),
			"two XOR prints cancel but count two moves")
		_expect(state.select_mask(0), true, "change selection after print")
		state.rotate(-1)
		_expect(state.undo(), true, "undo last print after free edits")
		_expect_state(state, _expected_snapshot(puzzle, printed, 1, 1, 1, 1),
			"undo restores print-time selection and orientation")
		state.set_rotation(3)
		_expect(state.undo(), true, "undo first print")
		_expect_state(state, before, "undo restores preprint state")
		_expect(state.undo(), false, "history exhausted")
		_expect_state(state, before, "empty undo preserves selection")
		_expect(state.print_mask(), true, "branch after all undos")
		_expect_state(state, _expected_snapshot(puzzle, printed, 1, 1, 1, 1), "fresh history branch")
		state.reset()
		_expect_state(state, initial, "reset preserves puzzle, restores start and defaults")
		_expect(state.undo(), false, "reset clears history")
		state.reset()
		_expect_state(state, initial, "repeated reset")
	completed_scenarios += 1

func _test_returned_copies() -> void:
	var state = State.new()
	_expect(state.print_mask(), true, "copy isolation setup")
	var before: Dictionary = _expected_snapshot(0, MASKS[0][0], 0, 0, 1, 1)
	var board: Array = state.get_board()
	var target: Array = state.get_target()
	var mask: Array = state.get_mask()
	var preview: Array = state.preview()
	var exposed: Dictionary = state.snapshot()
	board[0] = 99
	target[0] = 99
	mask[0] = 99
	preview[0] = 99
	exposed["board"][0] = 99
	exposed["target"][0] = 99
	exposed["moves"] = 99
	_expect_state(state, before, "returned data cannot mutate live state")
	_expect(state.undo(), true, "copy isolation does not corrupt history")
	_expect_state(state, _expected_snapshot(0, PUZZLES[0]["start"]), "history copy preserved")
	state.reset()
	_expect_state(State.new(), _expected_snapshot(0, PUZZLES[0]["start"]), "fixtures and instances isolated")
	completed_scenarios += 1

func _test_goals_and_progression() -> void:
	var state = State.new()
	_solve_first(state)
	var solved_first: Dictionary = _expected_snapshot(0, PUZZLES[0]["target"], 0, 1, 2, 2)
	_expect(state.preview(), PUZZLES[0]["target"], "solved preview frozen")
	_expect(state.print_mask(), false, "solved first print blocked")
	_expect_state(state, solved_first, "blocked first print unchanged")
	_expect(state.undo(), true, "undo goal reopens puzzle")
	_expect_state(state, _expected_snapshot(0, MASKS[0][0], 0, 1, 1, 1), "unsolved after goal undo")
	_expect(state.next_puzzle(), false, "advance blocked after goal undo")
	_expect(state.print_mask(), true, "solve first again")
	state.reset()
	_expect_state(state, _expected_snapshot(0, PUZZLES[0]["start"]), "reset solved first")
	_solve_first(state)
	_expect(state.next_puzzle(), true, "advance from solved first")
	_expect_state(state, _expected_snapshot(1, PUZZLES[1]["start"]), "second puzzle starts clean")
	_expect(state.undo(), false, "cannot undo across puzzle boundary")
	state.set_rotation(2)
	var intermediate := [0, 1, 0, 1, 0, 1, 0, 1, 0]
	_expect(state.preview(), intermediate, "A180 removes initial ink in puzzle 2")
	_expect(state.print_mask(), true, "puzzle 2 first print")
	_expect_state(state, _expected_snapshot(1, intermediate, 0, 2, 1, 1), "puzzle 2 intermediate")
	_expect(state.select_mask(1), true, "puzzle 2 B selection")
	state.rotate(-1)
	_expect(state.preview(), PUZZLES[1]["target"], "B90 goal preview")
	_expect(state.is_solved(), false, "preview alone cannot solve")
	_expect(state.print_mask(), true, "puzzle 2 second print")
	var solved_second: Dictionary = _expected_snapshot(1, PUZZLES[1]["target"], 1, 1, 2, 2)
	_expect_state(state, solved_second, "second goal reached")
	_expect(state.preview(), PUZZLES[1]["target"], "final preview frozen")
	_expect(state.print_mask(), false, "final print blocked")
	_expect(state.next_puzzle(), false, "no third puzzle or wraparound")
	_expect_state(state, solved_second, "final blocked actions unchanged")
	_expect(state.undo(), true, "final goal undo")
	_expect_state(state, _expected_snapshot(1, intermediate, 1, 1, 1, 1), "final undo reopens")
	_expect(state.print_mask(), true, "final goal can be solved again")
	state.reset()
	_expect_state(state, _expected_snapshot(1, PUZZLES[1]["start"]), "final reset stays on puzzle 2")
	_expect(state.undo(), false, "final reset clears history")
	completed_scenarios += 1

# 8 oriented stamps, all ordered three-print sequences on each puzzle: 2 * 8^3.
# Reference boards use literal masks and conditional flips, never state.preview().
func _test_bounded_sequences() -> void:
	for puzzle in range(2):
		for first in range(8):
			for second in range(8):
				for third in range(8):
					var state = _new_at(puzzle)
					var board: Array = PUZZLES[puzzle]["start"].duplicate()
					var history: Array = []
					var selected := 0
					var rotation := 0
					var moves := 0
					var context := "sequence %d:%d,%d,%d" % [puzzle, first, second, third]
					for action in [first, second, third]:
						selected = 0 if action < 4 else 1
						rotation = action % 4
						_expect(state.select_mask(selected), true, context + " select")
						state.set_rotation(rotation)
						var before: Dictionary = _expected_snapshot(puzzle, board, selected, rotation, moves, history.size())
						var accepted: bool = board != PUZZLES[puzzle]["target"]
						var expected_preview: Array = _flip(board, MASKS[selected][rotation]) if accepted else board.duplicate()
						_expect(state.preview(), expected_preview, context + " reference preview")
						_expect_state(state, before, context + " preview is read-only")
						_expect(state.print_mask(), accepted, context + " print return")
						if accepted:
							history.append(before)
							board = expected_preview
							moves += 1
						_expect_state(state, _expected_snapshot(puzzle, board, selected, rotation, moves, history.size()),
							context + " after print")
					while not history.is_empty():
						var previous: Dictionary = history.pop_back()
						_expect(state.undo(), true, context + " undo")
						_expect_state(state, previous, context + " full undo snapshot")
					var exhausted: Dictionary = state.snapshot()
					_expect(state.undo(), false, context + " empty undo")
					_expect(state.snapshot(), exhausted, context + " empty undo unchanged")
					state.reset()
					_expect_state(state, _expected_snapshot(puzzle, PUZZLES[puzzle]["start"]), context + " reset")
					sequence_cases += 1
	_expect(sequence_cases, 1024, "all bounded sequences completed")
	completed_scenarios += 1

func _run() -> void:
	_test_selection_rotation()
	_test_print_undo_reset()
	_test_returned_copies()
	_test_goals_and_progression()
	_test_bounded_sequences()
	# An aborted scenario must not accidentally fall through to the pass marker.
	_expect(completed_scenarios, 5, "all scenario groups completed")
	if failures > 0:
		printerr("REGRESSION FAILED: %d failures / %d checks" % [failures, checks])
		quit(EXIT_FAILURE)
		return
	print("Regression checks passed: %d; bounded sequences: %d" % [checks, sequence_cases])
	print("HARNESS_REGRESSION_PASS")
	quit(0)
