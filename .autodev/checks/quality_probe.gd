extends SceneTree
## Supplementary trusted QA. Existing acceptance tests remain untouched.
const Scene = preload("res://integrated_main.tscn")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("QUALITY FAIL: " + message)

func settle() -> void:
	for frame in range(8):
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func inspect_layout(scene: Control, context: String) -> void:
	var bounds := Rect2(Vector2.ZERO, scene.size)
	for control in [scene.heading, scene.subheading, scene.feedback, scene.progress_label]:
		check(control.size.x > 0 and control.size.y > 0, context + " text has area")
		check(control.get_global_rect().end.x <= bounds.end.x + 2, context + " text inside horizontal viewport")
	check(scene.feedback.get_global_rect().end.y <= bounds.end.y + 2, context + " feedback on screen")
	var cards: Array = []
	for card in scene.boards_grid.get_children():
		check(card.get_global_rect().end.x <= bounds.end.x + 2, context + " board inside horizontal viewport")
		for other in cards:
			check(not card.get_global_rect().intersects(other.get_global_rect()), context + " board cards do not overlap")
		cards.append(card)
	# A ScrollContainer may intentionally put content below the viewport.
	# Check scroll reachability rather than incorrectly declaring it clipped.
	for button in [scene.print_button, scene.undo_button, scene.next_button]:
		check(button.size.x >= button.get_minimum_size().x, context + " button text fits minimum width")
		check(button.get_global_rect().end.x <= bounds.end.x + 2, context + " action inside horizontal viewport")

func run() -> void:
	var scene = Scene.instantiate()
	scene.autosave_enabled = false
	root.add_child(scene)
	await settle()
	check(scene.overlay.visible, "start menu present")
	scene._new_game()
	scene.overlay.hide()
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		root.content_scale_size = resolution
		for scale_value in [1.0, 1.25, 1.5]:
			scene._set_font_scale(scale_value)
			await settle()
			inspect_layout(scene, "%s font %.2f" % [resolution, scale_value])
			scene._open_settings()
			await settle()
			check(scene.popup_panel.size.x <= scene.size.x, "settings fits viewport width")
			check(scene.popup_panel.size.y <= scene.size.y, "settings fits viewport height")
			scene._settings_close()
			await settle()
	# Full event dispatch exercises GUI focus and unhandled-input duplication.
	scene._reset_confirmed()
	scene.print_button.grab_focus()
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	await settle()
	event = InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = false
	Input.parse_input_event(event)
	await settle()
	check(scene.state.snapshot()["moves"] == 1, "focused Space prints exactly once")
	scene._undo()
	check(scene.state.snapshot()["moves"] == 0, "UI undo after focus input")
	scene._setting_value_changed(true, "reduce_motion")
	scene._print()
	check(scene.reaction_time == 0.0, "reduced motion stops reaction")
	scene._open_pause()
	var paused: Dictionary = scene.state.snapshot()
	scene._print()
	check(scene.state.snapshot() == paused, "dialog blocks print")
	scene.overlay.hide()
	scene._setting_value_changed(true, "mute")
	for player in scene.audio.values():
		check(player.volume_db <= -80.0 and not player.playing, "mute stops SFX")
	scene._setting_value_changed(false, "mute")
	scene._setting_value_changed(0.5, "master")
	scene._setting_value_changed(0.5, "sfx")
	for player in scene.audio.values():
		check(is_equal_approx(player.volume_db, linear_to_db(0.25)), "combined audio gain")
	# Exercise real serialization, backup fallback and corrupt-file rejection in
	# isolated user:// storage supplied by the coordinator, never the player's save.
	check(scene._save_progress(), "save succeeds")
	var saved: Dictionary = scene.state.snapshot()
	check(scene._save_progress(), "second save creates backup")
	var file := FileAccess.open(scene.SAVE_PATH, FileAccess.WRITE)
	file.store_string("invalid json")
	file.close()
	scene._undo()
	check(scene._load_progress(), "corrupt primary recovers backup")
	check(scene.state.snapshot() == saved, "backup restores exact state")
	file = FileAccess.open(scene.SAVE_BACKUP, FileAccess.WRITE)
	file.store_string("invalid json")
	file.close()
	check(not scene._load_progress(), "two corrupt saves rejected")
	check(scene.state.snapshot() == saved, "failed load preserves current state")
	# Scene's real exit cleanup must release audio; no teardown delay is used to
	# claim a leak is fixed. Engine exit diagnostics are separately enforced.
	scene.queue_free()
	await settle()
	if failures == 0:
		print("AUTODEV_QUALITY_PASS checks=%d matrix=2x3" % checks)
		quit(0)
	else:
		printerr("AUTODEV_QUALITY_FAIL failures=%d checks=%d" % [failures, checks])
		quit(1)
