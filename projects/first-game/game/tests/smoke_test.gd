extends SceneTree
## Generated regression checks, not independent validation or a human playtest.
const State = preload("res://scripts/game_state.gd")
const MainScene = preload("res://main.tscn")
const ZERO := [0, 0, 0, 0, 0, 0, 0, 0, 0]
const A_ROTATIONS := [
	[1, 1, 0, 1, 0, 0, 0, 0, 0],
	[0, 1, 1, 0, 0, 1, 0, 0, 0],
	[0, 0, 0, 0, 0, 1, 0, 1, 1],
	[0, 0, 0, 1, 0, 0, 1, 1, 0],
]
const B_ROTATIONS := [
	[1, 1, 1, 0, 0, 0, 0, 0, 0],
	[0, 0, 1, 0, 0, 1, 0, 0, 1],
	[0, 0, 0, 0, 0, 0, 1, 1, 1],
	[1, 0, 0, 1, 0, 0, 1, 0, 0],
]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	_test_rotation_and_aliases()
	_test_transitions()
	_test_progression()
	_test_algebra()
	_test_sequences()
	await _test_scene()
	if not failures.is_empty():
		printerr("SMOKE FAILED: %d failures / %d checks" % [failures.size(), checks])
		quit(1)
		return
	print("Checks passed: %d; generated tests are not independent validation." % checks)
	print("HARNESS_SMOKE_PASS")
	quit(0)

func _test_rotation_and_aliases() -> void:
	var s = State.new()
	_check(s.get_board() == ZERO and not s.is_solved(), "initial board and goal")
	_check(s.puzzle_count() == 2 and s.mismatch_count() == 4, "initial metadata")
	for mask_index in range(2):
		_check(s.select_mask(mask_index), "valid mask selection")
		for rotation in range(4):
			s.set_rotation(rotation)
			var expected: Array = A_ROTATIONS[rotation] if mask_index == 0 else B_ROTATIONS[rotation]
			_check(s.get_mask() == expected, "explicit rotated mask %d/%d" % [mask_index, rotation])
		s.set_rotation(0)
		for step in range(4):
			s.rotate()
		_check(s.get_mask() == (A_ROTATIONS[0] if mask_index == 0 else B_ROTATIONS[0]),
			"four clockwise turns restore mask")
	s.set_rotation(-1)
	_check(s.snapshot()["rotation"] == 3 and s.get_mask() == B_ROTATIONS[3], "negative rotation wraps")
	s.rotate(1)
	_check(s.snapshot()["rotation"] == 0, "rotation wraps from 3 to 0")
	var before: Dictionary = s.snapshot()
	_check(not s.select_mask(-1) and not s.select_mask(2), "invalid selection rejected")
	_check(s.snapshot() == before, "invalid selection has no side effects")
	var board: Array = s.get_board()
	var target: Array = s.get_target()
	var mask: Array = s.get_mask()
	var preview: Array = s.preview()
	var exposed: Dictionary = s.snapshot()
	board[0] = 99
	target[0] = 99
	mask[0] = 99
	preview[0] = 99
	exposed["board"][0] = 99
	exposed["target"][0] = 99
	_check(s.snapshot() == before, "returned arrays and snapshots are independent copies")

func _test_transitions() -> void:
	var s = State.new()
	var initial: Dictionary = s.snapshot()
	_check(not s.undo() and not s.next_puzzle(), "empty undo and premature progression rejected")
	_check(s.snapshot() == initial, "rejected actions do not mutate state")
	for repeat in range(5):
		_check(s.preview() == A_ROTATIONS[0], "initial preview")
	_check(s.snapshot() == initial, "preview is pure and free")
	var expected: Array = s.preview()
	_check(s.print_mask(), "first print accepted")
	_check(s.get_board() == expected and s.snapshot()["moves"] == 1, "print matches preview")
	s.select_mask(1)
	s.rotate()
	_check(s.undo(), "undo accepted after selection changes")
	_check(s.snapshot() == initial, "undo restores board, counter, mask, orientation and history")
	_check(not s.undo(), "undo exhausted")
	s.rotate()
	s.print_mask()
	s.select_mask(1)
	s.rotate()
	s.reset()
	_check(s.snapshot() == initial, "reset clears history and restores puzzle defaults")

func _solve_first(s) -> void:
	s.select_mask(0)
	s.set_rotation(0)
	_check(s.print_mask(), "puzzle 1 first print")
	s.set_rotation(1)
	_check(s.preview() == [1, 0, 1, 1, 0, 1, 0, 0, 0], "puzzle 1 goal preview")
	_check(s.print_mask(), "puzzle 1 second print")

func _test_progression() -> void:
	var s = State.new()
	_solve_first(s)
	_check(s.is_solved() and s.mismatch_count() == 0 and s.can_advance(), "puzzle 1 goal detected")
	var complete: Dictionary = s.snapshot()
	_check(s.preview() == s.get_board(), "solved preview is unchanged")
	_check(not s.print_mask() and s.snapshot() == complete, "solved printing rejected atomically")
	_check(s.undo() and not s.is_solved() and not s.can_advance(), "undo reopens completed puzzle")
	_check(not s.next_puzzle(), "undo prevents advancement")
	_check(s.print_mask() and s.is_solved(), "redo by printing restored selection")
	_check(s.next_puzzle(), "advance to puzzle 2")
	var second: Dictionary = s.snapshot()
	_check(second["puzzle"] == 1 and second["moves"] == 0 and second["history_size"] == 0,
		"progression starts a new turn history")
	_check(s.get_board() == [0, 1, 0, 1, 0, 0, 0, 0, 1], "puzzle 2 initial ink")
	_check(not s.undo(), "cannot undo across puzzle boundary")
	s.set_rotation(2)
	_check(s.preview() == [0, 1, 0, 1, 0, 1, 0, 1, 0], "puzzle 2 first preview")
	s.print_mask()
	s.select_mask(1)
	s.set_rotation(1)
	_check(s.preview() == [0, 1, 1, 1, 0, 0, 0, 1, 1], "puzzle 2 goal preview with ink removal")
	s.print_mask()
	_check(s.is_solved() and s.snapshot()["moves"] == 2, "puzzle 2 complete")
	var final_state: Dictionary = s.snapshot()
	_check(not s.can_advance() and not s.next_puzzle() and not s.print_mask(), "final boundary locked")
	_check(s.snapshot() == final_state, "final rejected actions preserve state")
	s.reset()
	_check(s.snapshot() == second, "reset final puzzle without rewinding progression")

func _test_algebra() -> void:
	for mask_index in range(2):
		for rotation in range(4):
			var s = State.new()
			s.select_mask(mask_index)
			s.set_rotation(rotation)
			s.print_mask()
			s.print_mask()
			_check(s.get_board() == ZERO and s.snapshot()["moves"] == 2, "two identical prints cancel")
	var left = State.new()
	var right = State.new()
	left.print_mask()
	left.select_mask(1)
	left.set_rotation(1)
	left.print_mask()
	right.select_mask(1)
	right.set_rotation(1)
	right.print_mask()
	right.select_mask(0)
	right.set_rotation(0)
	right.print_mask()
	_check(left.get_board() == right.get_board(), "XOR masks commute without intermediate constraints")
	# Each start differs from its goal and no single allowed action reaches it.
	# Combined with the two-print witnesses above, this checks the minimum of 2.
	for puzzle in range(2):
		var s = State.new()
		if puzzle == 1:
			_solve_first(s)
			s.next_puzzle()
		_check(not s.is_solved(), "minimum is not zero")
		for mask_index in range(2):
			s.select_mask(mask_index)
			for rotation in range(4):
				s.set_rotation(rotation)
				_check(s.preview() != s.get_target(), "no one-print solution")

func _test_sequences() -> void:
	for seed in range(1000):
		var s = State.new()
		var replay = State.new()
		var applied := 0
		var generator := seed + 1
		for step in range(12):
			generator = (generator * 48271) % 2147483647
			var mask_index := generator % 2
			var rotation := (generator >> 1) % 4
			s.select_mask(mask_index)
			replay.select_mask(mask_index)
			s.set_rotation(rotation)
			replay.set_rotation(rotation)
			var expected: Array = s.preview()
			var accepted: bool = s.print_mask()
			_check(replay.print_mask() == accepted, "replay action result")
			_check(s.snapshot() == replay.snapshot(), "deterministic replay")
			if accepted:
				applied += 1
				_check(s.get_board() == expected, "sequence preview equals print")
			for cell in s.get_board():
				_check(cell == 0 or cell == 1, "binary invariant")
			if s.is_solved():
				break
		for step in range(applied):
			_check(s.undo(), "sequence undo available")
		_check(s.get_board() == ZERO and s.snapshot()["moves"] == 0
			and s.snapshot()["history_size"] == 0, "sequence undo restores initial board")

func _key(scene, code: int, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	scene._input(event)

func _test_scene() -> void:
	var scene = MainScene.instantiate()
	root.add_child(scene)
	await process_frame
	_check(scene.before_view.cells == ZERO, "main scene current board binding")
	_check(scene.after_view.cells == A_ROTATIONS[0], "main scene initial preview binding")
	_key(scene, KEY_E, true)
	_check(scene.state.snapshot()["rotation"] == 0, "held-key echo ignored")
	_key(scene, KEY_SPACE)
	_key(scene, KEY_E)
	_check(scene.after_view.cells == scene.state.get_target(), "keyboard rotation updates visible preview")
	_key(scene, KEY_ENTER)
	_check(scene.state.is_solved() and scene.print_button.disabled and not scene.next_button.disabled,
		"keyboard solve updates action availability")
	scene.undo_button.pressed.emit()
	_check(not scene.state.is_solved() and scene.next_button.disabled, "mouse undo reopens puzzle")
	_key(scene, KEY_SPACE)
	scene.next_button.pressed.emit()
	_check(scene.state.snapshot()["puzzle"] == 1 and scene.undo_button.disabled, "mouse progression")
	_key(scene, KEY_E)
	_key(scene, KEY_E)
	scene.print_button.pressed.emit()
	scene.mask_buttons[1].pressed.emit()
	_key(scene, KEY_Q)
	scene.print_button.pressed.emit()
	_check(scene.state.is_solved() and scene.next_button.disabled, "mixed input completes final puzzle")
	_key(scene, KEY_R)
	_check(scene.state.snapshot()["puzzle"] == 1 and scene.state.snapshot()["moves"] == 0
		and not scene.print_button.disabled, "keyboard reset refreshes final puzzle")
	scene.queue_free()
	await process_frame
