extends SceneTree
## Additive regression, not independent QA or a substitute for human gameplay.
const State = preload("res://scripts/slice_state.gd")
const Integrated = preload("res://integrated_main.tscn")
const DATA = preload("res://data/mech_data.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, context: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("SLICE TEST FAIL: " + context)

func _run() -> void:
	var legacy_saves: Array = []
	var game = State.new()
	_check(game.puzzle_count() == 8, "8 puzzles available")
	for puzzle in range(8):
		_check(game.snapshot()["puzzle"] == puzzle, "correct active puzzle")
		var original: Dictionary = game.export_progress()
		var allowed: Array = DATA.PUZZLES[puzzle]["allowed_masks"]
		for index in range(2):
			_check(game.select_mask(index) == (index in allowed), "stamp restriction %d/%d" % [puzzle, index])
		for step in DATA.PUZZLES[puzzle]["solution"]:
			var stamp: int = int(int(step) / 4)
			var rotation: int = int(step) % 4
			_check(game.select_mask(stamp), "select witness stamp")
			game.set_rotation(rotation)
			_check(game.print_mask(), "witness print accepted")
		_check(game.is_solved(), "witness solves puzzle %d" % puzzle)
		_check(not game.print_mask(), "solved puzzle rejects further prints")
		var serial: Dictionary = game.export_progress()
		if puzzle < 6:
			var legacy: Dictionary = serial.duplicate(true)
			legacy["hints"] = [0, 1, 2, 3, 0, 1]
			legacy_saves.append(legacy)
		var restored = State.new()
		_check(restored.import_progress(serial), "restore complete puzzle")
		_check(restored.snapshot() == game.snapshot(), "restored exact state")
		_check(restored.export_progress()["history"] == serial["history"], "restored history")
		var tampered: Dictionary = serial.duplicate(true)
		tampered["board"][0] = 5
		_check(not restored.import_progress(tampered), "reject invalid cell")
		_check(restored.snapshot() == game.snapshot(), "invalid restore preserves existing state")
		var json_roundtrip: Variant = JSON.parse_string(JSON.stringify(serial))
		var json_copy = State.new()
		_check(json_copy.import_progress(json_roundtrip), "JSON numeric restore accepted")
		_check(json_copy.snapshot() == game.snapshot(), "JSON roundtrip exact state")
		for attempt in range(int(serial["moves"])):
			_check(restored.undo(), "undo restored history")
		_check(restored.get_board() == DATA.PUZZLES[puzzle]["start"], "undo restores puzzle start")
		_check(restored.snapshot()["history_size"] == 0, "undo drains history")
		restored.reset()
		_check(restored.export_progress() == original, "reset restores full initial progress")
		if puzzle < 7:
			_check(game.next_puzzle(), "manual next after solved")
		else:
			_check(not game.next_puzzle(), "final boundary")
	# Ensure old smoke/regression fixtures are unaffected by new default scene.
	var old = preload("res://scripts/game_state.gd").new()
	_check(old.puzzle_count() == 2, "legacy state retained")
	var view = Integrated.instantiate()
	view.autosave_enabled = false
	root.add_child(view)
	await process_frame
	_check(view.overlay.visible, "start screen visible")
	view.overlay.hide()
	view._new_game()
	_check(view.state.puzzle_count() == 8, "UI binds eight-puzzle state")
	_check(view.heading.text.contains("1 / 8"), "UI shows eight puzzles")
	_check(view.stamp_view.texture != null, "art integrated")
	_check(view.audio.size() == 3, "three SFX streams loaded")
	view._print()
	_check(view.state.snapshot()["moves"] == 1, "UI print applies once")
	view._undo()
	_check(view.state.snapshot()["moves"] == 0, "UI undo restores move count")
	# Literal new designs supplement the generic witness and history tests above.
	_check(DATA.PUZZLES[6]["allowed_masks"] == [0] and DATA.PUZZLES[6]["target"] == [0,0,0,0,0,0,0,0,0], "puzzle 7 clears paper with elbows only")
	_check(DATA.PUZZLES[7]["minimum_prints"] == 5 and DATA.PUZZLES[7]["allowed_masks"] == [0,1], "puzzle 8 mixed five-print design")
	for legacy in legacy_saves:
		_check(view._valid_progress(legacy), "six-puzzle save with hints remains valid")
		var old_copy = State.new()
		_check(old_copy.import_progress(legacy), "legacy solved state imports")
		_check(old_copy.is_solved() and old_copy.can_advance(), "legacy completion can continue through appended puzzles")
		_check(old_copy.undo(), "legacy saved undo history remains usable")
		old_copy.reset()
		_check(old_copy.get_board() == DATA.PUZZLES[int(legacy["puzzle"])]["start"], "legacy saved reset")
	var invalid_legacy: Dictionary = legacy_saves[5].duplicate(true)
	invalid_legacy["puzzle"] = 6
	_check(not view._valid_progress(invalid_legacy), "six hint slots rejected for new puzzle indices")
	for puzzle in range(8):
		_check(view.heading.text.contains("%d / 8" % (puzzle + 1)), "UI progress count")
		for action in DATA.PUZZLES[puzzle]["solution"]:
			view._select(int(int(action) / 4))
			view.state.set_rotation(int(action) % 4)
			view._print()
		_check(view.state.is_solved(), "UI solution completes")
		_check(view.next_button.disabled == (puzzle == 7), "UI final boundary after eight")
		if puzzle < 7:
			_check(not view.feedback.text.contains("모두 해결"), "early completion does not finish game")
			view._next()
		else:
			_check(view.feedback.text.contains("8개 퍼즐을 모두 해결"), "final completion text")
			var final_snapshot: Dictionary = view.state.snapshot()
			view._next()
			_check(view.state.snapshot() == final_snapshot, "final next does not wrap")
			view._undo()
			_check(not view.state.is_solved(), "final UI undo reopens puzzle eight")
			view._reset_confirmed()
			_check(view.state.get_board() == DATA.PUZZLES[7]["start"] and view.state.snapshot()["history_size"] == 0, "final UI reset")
	# Release started SFX playback before freeing the test scene.
	# This changes only teardown, not the 144 acceptance assertions.
	for player in view.audio.values():
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	# Give the audio mixing thread time to release active playback handles.
	await create_timer(0.20).timeout
	view.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.75).timeout
	if failures == 0:
		print("SLICE_ACCEPTANCE_PASS checks=%d" % assertions)
		quit(0)
	else:
		printerr("SLICE_ACCEPTANCE_FAIL %d failures / %d checks" % [failures, assertions])
		quit(1)
