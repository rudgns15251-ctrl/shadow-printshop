extends SceneTree
## Trusted S13 probe: dialogs, title, settings and scenes for fingers. In touch
## mode every key in the title menu, help, settings, menu, story list, archive,
## orders, hints, chapter record, confirmations and credits is at least 80
## logical px tall and at least 140 px wide (about a fingertip); sliders and check boxes are
## at least 64 px tall; the title menu fits 1280x720 unscrolled; long documents
## scroll by dragging (no keyboard needed) and say so; the scene keys are large
## and a tap on the scene reads on. Desktop dialogs are unchanged when touch mode
## is off.
var failures: Array = []
var checks := 0
const MIN_KEY := 80.0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("TOUCH DIALOGS FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(6):
		await process_frame

func controls(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is CanvasItem and not child.is_visible_in_tree():
			continue
		if child is BaseButton or child is Slider:
			out.append(child)
		controls(child, out)

func dialog_keys(main, label: String) -> void:
	await settle()
	var found: Array = []
	controls(main.dialog, found)
	check(not found.is_empty(), label + ": has controls")
	for item in found:
		var rect: Rect2 = item.get_global_rect()
		if item is Button and not item is CheckBox:
			check(rect.size.y >= MIN_KEY - 0.5, label + ": key '" + str(item.text).left(14) + "' at least 80 px tall (" + str(int(rect.size.y)) + ")")
			check(rect.size.x >= 140.0 - 0.5, label + ": key '" + str(item.text).left(14) + "' at least 140 px wide")
		else:
			check(rect.size.y >= 64.0 - 0.5, label + ": control at least 64 px tall (" + item.get_class() + ")")

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.autosave_enabled = false
	root.size = Vector2i(1280, 720)
	check(main.has_method("set_touch_mode"), "touch mode available")
	if not main.has_method("set_touch_mode"):
		main.free()
		quit(2)
		return
	main.set_touch_mode(true)
	main._open_start()
	await dialog_keys(main, "title")
	check(not main.popup_scroll.get_v_scroll_bar().visible, "title menu fits 1280x720 unscrolled")
	main.start_new()
	main.dismiss_story()
	for opener in ["_open_help", "_open_settings", "_open_pause", "_open_story", "_open_journal", "_open_order", "_ask_reset", "_ask_new_game"]:
		main.call(opener)
		await dialog_keys(main, opener)
		main.dismiss_story()
	main.puzzle_view._print()
	main._open_hint()
	await dialog_keys(main, "hint")
	main.dismiss_story()
	main.puzzle_view._undo()
	# Long documents: drag scrolling, and the hint says so.
	main._set_font_scale(1.5)
	main._open_help()
	await settle()
	check(main.popup_scroll.get_v_scroll_bar().visible, "help is long enough to scroll at 150%")
	# Touch drags scroll a ScrollContainer; a dead zone keeps taps on keys from scrolling.
	check(main.popup_scroll.scroll_deadzone >= 8, "the document scrolls by dragging without stealing taps")
	var hint = main.find_child("DialogHint", true, false)
	check(hint is Label and hint.is_visible_in_tree() and (str(hint.text).contains("밀어") or str(hint.text).contains("넘겨")), "reading hint tells the player to swipe")
	main.dismiss_story()
	main._set_font_scale(1.0)
	# Chapter record and the ending credits.
	for index in range(8):
		main.dismiss_story()
		solve(main, index)
		if index < 7:
			main.advance()
	main.advance()
	var stage = main.find_child("StoryStage", true, false)
	await settle()
	for name in ["AdvanceKey", "SkipKey"]:
		var key = stage.find_child(name, true, false)
		check(key is Button and key.get_global_rect().size.y >= MIN_KEY - 0.5, "scene key " + name + " at least 80 px tall")
	var line_before: int = int(stage.line_index)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(640, 200)
	stage._gui_input(tap)
	await settle()
	check(int(stage.line_index) == line_before + 1 or not stage.visible, "a tap on the scene reads on")
	stage.skip()
	await dialog_keys(main, "chapter record")
	main.dismiss_story()
	for index in range(8, 18):
		main.dismiss_story()
		solve(main, index)
		if index < 17:
			main.advance()
	main.dismiss_story()
	main.show_credits()
	await dialog_keys(main, "credits")
	main.dismiss_story()
	# Desktop dialogs unchanged.
	main.set_touch_mode(false)
	main._open_help()
	await settle()
	var desktop: Array = []
	controls(main.dialog, desktop)
	check(not desktop.is_empty() and desktop[0].get_global_rect().size.y < MIN_KEY, "desktop dialog keys keep their size")
	main.dismiss_story()
	main.free()
	print("TOUCH_DIALOGS_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("TOUCH_DIALOGS_PASS")
	quit(0 if failures.is_empty() else 2)
