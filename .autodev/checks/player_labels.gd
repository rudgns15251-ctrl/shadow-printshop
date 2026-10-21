extends SceneTree
## Trusted S10 probe: the play screen speaks to the player in Korean. No developer
## labels (CURRENT/AFTER/TARGET/STAMP/SPACE/NEXT) appear on the screen, in
## guidance or in action tooltips across game states; every action keeps its
## shortcut as a bracketed secondary hint, and every shortcut still works.
var failures: Array = []
var checks := 0
const FORBIDDEN := ["CURRENT", "AFTER", "TARGET", "STAMP", "SPACE", "NEXT"]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("PLAYER LABELS FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func screen_texts(main, node: Node, out: Array) -> void:
	for child in node.get_children():
		if child == main.overlay:
			continue
		if (child is Label or child is Button) and child.is_visible_in_tree():
			out.append(str(child.text))
			if child is Button:
				out.append(str(child.tooltip_text))
		screen_texts(main, child, out)

func clean(main, label: String) -> void:
	var texts: Array = []
	screen_texts(main, main, texts)
	var found := []
	for text in texts:
		for word in FORBIDDEN:
			# The developer labels were upper-case ("SPACE · 인쇄", "CURRENT · 현재");
			# bracketed key hints such as "[Space]" are the intended replacement.
			if text.contains(word):
				found.append(word + " in '" + text.left(40) + "'")
	check(found.is_empty(), label + ": no developer labels " + str(found.slice(0, 4)))

func key(code: Key) -> void:
	var focus: Control = root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release)

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	await process_frame
	clean(main, "fresh first puzzle")
	var hints := {main.print_button: "[Space]", main.undo_button: "[U]", main.next_button: "[N]",
		main.stamp_buttons[0]: "[1]", main.stamp_buttons[1]: "[2]"}
	for button in hints:
		check(str(button.text).contains(hints[button]), "key hint " + hints[button] + " on '" + str(button.text) + "'")
	check(str(main.stamp_buttons[0].text).contains("꺾임") and str(main.stamp_buttons[1].text).contains("막대"), "stamp names kept")
	var rotate: Array = []
	for item in main.stamp_buttons[0].get_parent().get_children():
		if item is Button and (str(item.text).contains("[Q]") or str(item.text).contains("[E]")):
			rotate.append(item)
	check(rotate.size() == 2, "rotation keys hinted as [Q]/[E]")
	# Shortcuts still drive the same actions.
	key(KEY_2)
	await process_frame
	check(int(main.session.snapshot()["selected_mask"]) == 1, "2 selects the bar stamp")
	key(KEY_1)
	key(KEY_E)
	await process_frame
	check(int(main.session.snapshot()["selected_mask"]) == 0 and int(main.session.snapshot()["rotation"]) == 1, "1 and E select and rotate")
	key(KEY_Q)
	key(KEY_SPACE)
	await process_frame
	check(int(main.session.snapshot()["moves"]) == 1, "Space prints")
	clean(main, "after a print")
	key(KEY_U)
	await process_frame
	check(int(main.session.snapshot()["history_size"]) == 0, "U undoes")
	solve(main, 0)
	await process_frame
	clean(main, "solved first puzzle")
	key(KEY_N)
	await process_frame
	check(int(main.session.snapshot()["puzzle"]) == 1, "N advances")
	for index in range(1, 8):
		main.dismiss_story()
		solve(main, index)
		if index < 7:
			main.advance()
	await process_frame
	clean(main, "chapter-ending puzzle solved")
	main.advance()
	main.dismiss_story()
	await process_frame
	clean(main, "chapter 2, single-stamp puzzle")
	check(main.stamp_buttons[1].disabled or main.stamp_buttons[0].disabled, "an unavailable stamp is shown as unavailable")
	main._open_help()
	await process_frame
	var help := ""
	for child in main.dialog.get_children():
		if child is Label:
			help += str(child.text)
	check(not help.contains("AFTER") and not help.contains("TARGET") and not help.contains("CURRENT"), "help uses the player-facing board names")
	check(help.contains("견본") and help.contains("미리보기"), "help names the sample and preview boards")
	main.dismiss_story()
	main.free()
	print("PLAYER_LABELS_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("PLAYER_LABELS_PASS")
	quit(0 if failures.is_empty() else 2)
