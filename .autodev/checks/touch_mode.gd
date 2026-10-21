extends SceneTree
## Trusted S13 probe: touch mode. On a phone (OS feature "mobile", or forced
## with set_touch_mode(true) for tests) the game speaks to fingers, not keys: no
## keyboard hints ([Space], [Q], PageDown...) on the play screen, guidance, help,
## hints, scenes or reading hints, while every action and state cue stays. The
## Android back gesture does what Escape does (skip a scene, close a dialog,
## open the menu during play, never quit from the title). Pausing the app saves
## progress and quiets the room sound; resuming brings it back. Desktop stays
## exactly as before (keyboard hints back when touch mode is off).
var failures: Array = []
var checks := 0
var key_hint := RegEx.create_from_string("\\[(Space|Enter|Esc|Q|E|U|Z|N|R|1|2|PageDown|PageUp|Home|End)\\]|\\((N|U/Z|Space/Enter|Enter|Esc|R|Q/E|1/2)\\)|PageDown|PageUp|Home/End")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("TOUCH MODE FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(4):
		await process_frame

func gather(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is CanvasItem and not child.is_visible_in_tree():
			continue
		if child is Label or child is Button:
			out.append(str(child.text).replace(char(0x2060), ""))
			if not str(child.tooltip_text).is_empty():
				out.append(str(child.tooltip_text))
		gather(child, out)

func no_keys(node: Node, label: String) -> void:
	await settle()
	var texts: Array = []
	gather(node, texts)
	var found: Array = []
	for text in texts:
		var hit := key_hint.search(str(text))
		if hit != null:
			found.append(hit.get_string() + " in '" + str(text).left(40) + "'")
	check(found.is_empty(), label + ": no keyboard hints in touch mode " + str(found.slice(0, 3)))

func back(main) -> void:
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await settle()

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.size = Vector2i(1280, 720)
	check(main.has_method("set_touch_mode") and "touch_mode" in main, "campaign exposes touch mode")
	if not main.has_method("set_touch_mode"):
		main.free()
		print("TOUCH_MODE_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
		quit(2)
		return
	check(main.touch_mode == OS.has_feature("mobile"), "touch mode follows the platform by default")
	check(not main.get_tree().quit_on_go_back, "the engine does not quit on the back gesture; the game handles it")
	# A title already open when touch mode starts (first launch on a phone) loses its key hints too.
	main._open_start()
	await settle()
	main.set_touch_mode(true)
	await no_keys(main.overlay, "title open before touch mode")
	# Title: back never quits or starts a game.
	main._open_start()
	await settle()
	await no_keys(main.overlay, "title")
	await back(main)
	check(main.overlay.visible and not main.game_active, "back on the title keeps the title")
	main.start_new()
	main.dismiss_story()
	await no_keys(main, "first order")
	var stamp: String = str(main.stamp_buttons[0].text)
	check(stamp.contains("꺾임") and stamp.contains("✓"), "stamp name and selection cue kept: " + stamp)
	main.puzzle_view._print()
	await no_keys(main, "after a print")
	for level in range(3):
		main._open_hint()
		await no_keys(main.overlay, "hint %d" % (level + 1))
		main.dismiss_story()
	main.puzzle_view._undo()
	main._set_font_scale(1.5)
	main._open_help()
	await no_keys(main.overlay, "help at 150%")
	var hint = main.find_child("DialogHint", true, false)
	if hint is Label and hint.is_visible_in_tree():
		check(not str(hint.text).contains("PageDown"), "reading hint speaks of swiping, not keys")
	# Back closes a dialog.
	await back(main)
	check(not main.overlay.visible, "back closes a dialog")
	main._set_font_scale(1.0)
	# Back during play opens the menu; back again closes it.
	await back(main)
	check(main.overlay.visible and main.dialog.find_children("*", "Button", true, false).size() > 0, "back during play opens the menu")
	await back(main)
	check(not main.overlay.visible, "back again returns to the order")
	# Scenes: keys say nothing about keyboards; back skips.
	main.play_scene("SC_OPENING")
	await no_keys(main.overlay, "scene")
	await back(main)
	var stage = main.find_child("StoryStage", true, false)
	check(stage != null and not stage.visible and not main.overlay.visible, "back skips a scene")
	# Ending guidance.
	main.autosave_enabled = false
	for index in range(18):
		main.dismiss_story()
		solve(main, index)
		if index < 17:
			main.advance()
	main.dismiss_story()
	await no_keys(main, "ending")
	# App lifecycle: pausing saves and quiets the room; resuming restores it.
	main.autosave_enabled = true
	main._setting_value_changed(0.5, "bgm")
	await settle()
	var room: AudioStreamPlayer = main.get_environment_audio()
	main.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await settle()
	check(main.campaign_save.load_candidate().size() > 0 and main.campaign_save.load_candidate()["session"].export_progress() == main.session.export_progress(), "pausing the app saves progress")
	check(room == null or room.stream_paused or not room.playing, "pausing the app quiets the room")
	main.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await settle()
	check(room == null or (room.playing and not room.stream_paused), "resuming the app brings the room back")
	# Desktop unchanged.
	main.set_touch_mode(false)
	await settle()
	check(str(main.print_button.text).contains("[Space]") and str(main.stamp_buttons[0].text).contains("[1]"), "desktop keeps keyboard hints")
	main.free()
	print("TOUCH_MODE_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("TOUCH_MODE_PASS")
	quit(0 if failures.is_empty() else 2)
