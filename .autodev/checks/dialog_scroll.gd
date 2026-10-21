extends SceneTree
## Trusted S08 probe: long dialogs open at their top, and keyboard-only players can
## read all of them with PageDown/PageUp/Home/End while focus stays on the dialog
## action. The keys never close a dialog, move focus or change progress, and do
## nothing to gameplay when no dialog is open. The help text names the keys.
var failures: Array = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("DIALOG SCROLL FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func text_of(node: Node) -> String:
	var text: String = node.text if (node is Label or node is Button) else ""
	for child in node.get_children():
		text += "\n" + text_of(child)
	return text

func key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release)

func settle() -> void:
	for i in range(6):
		await process_frame

func max_scroll(main) -> int:
	var bar: VScrollBar = main.popup_scroll.get_v_scroll_bar()
	return int(bar.max_value - bar.page)

func exercise(main, label: String, must_overflow: bool = true) -> void:
	await settle()
	var focus: Control = main.get_viewport().gui_get_focus_owner()
	var progress: Dictionary = main.session.export_progress().duplicate(true)
	check(main.popup_scroll.scroll_vertical == 0, label + ": opens at the top")
	if not must_overflow and max_scroll(main) <= 0:
		# A dialog that fits needs no paging: its action must already be on screen.
		var viewport: Rect2 = main.get_viewport_rect()
		check(focus != null and viewport.encloses(focus.get_global_rect()), label + ": fits, with its action visible without scrolling")
		return
	check(max_scroll(main) > 0, label + ": content overflows at 150% (precondition)")
	key(KEY_PAGEDOWN)
	await settle()
	var after_page: int = main.popup_scroll.scroll_vertical
	check(after_page > 0, label + ": PageDown scrolls down")
	key(KEY_END)
	await settle()
	check(main.popup_scroll.scroll_vertical >= max_scroll(main) - 1, label + ": End reaches the last line")
	key(KEY_PAGEUP)
	await settle()
	check(main.popup_scroll.scroll_vertical < max_scroll(main), label + ": PageUp scrolls up")
	key(KEY_HOME)
	await settle()
	check(main.popup_scroll.scroll_vertical == 0, label + ": Home returns to the top")
	check(main.overlay.visible and main.get_viewport().gui_get_focus_owner() == focus, label + ": dialog stays open with the same focus")
	check(main.session.export_progress() == progress, label + ": progress unchanged")

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.size = Vector2i(1280, 720)
	main._set_font_scale(1.5)
	main.start_new()
	main.dismiss_story()
	main._open_help()
	check(text_of(main.dialog).contains("PageUp") and text_of(main.dialog).contains("PageDown"), "help names the dialog scroll keys")
	main.dismiss_story()
	for index in range(18):
		main.dismiss_story()
		for action in main.session.puzzle_data()[index]["solution"]:
			main.puzzle_view._select(int(int(action) / 4))
			main.session.set_rotation(int(action) % 4)
			main.puzzle_view._print()
		if index < 17:
			main.advance()
			if index == 7:
				await exercise(main, "chapter transition", false)
	main.dismiss_story()
	main.show_credits()
	await exercise(main, "credits")
	main._show_asset_licenses(Callable(main, "_noop"), "결말로 돌아가기")
	await exercise(main, "asset licenses")
	main.dismiss_story()
	await settle()
	var progress: Dictionary = main.session.export_progress().duplicate(true)
	for code in [KEY_PAGEDOWN, KEY_PAGEUP, KEY_HOME, KEY_END]:
		key(code)
	await settle()
	check(not main.overlay.visible and main.session.export_progress() == progress, "keys do nothing to gameplay without a dialog")
	main.free()
	print("DIALOG_SCROLL_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("DIALOG_SCROLL_PASS")
	quit(0 if failures.is_empty() else 2)
