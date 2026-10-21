extends SceneTree
## Trusted S09 probe: the product opens on a real title screen (TitleBackdrop with
## scene art inside the overlay, a large NanumMyeongjo 음영 인쇄소 title, a 1998
## subtitle) while keeping the existing start menu actions, focus and Escape
## safety. The backdrop shows only for the title menu. Not an aesthetic review.
var failures: Array = []
var checks := 0
const MENU := ["처음부터", "기록함", "이야기 다시 읽기", "도움말", "설정", "종료"]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("TITLE SCREEN FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func visible_controls(node: Node, out: Array) -> void:
	for child in node.get_children():
		if (child is Label or child is Button) and child.is_visible_in_tree():
			out.append(child)
		visible_controls(child, out)

func by_text(main, text: String) -> Control:
	var found: Array = []
	visible_controls(main.overlay, found)
	for item in found:
		if item.text == text:
			return item
	return null

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)
	await process_frame

func backdrop_visible(main) -> bool:
	var backdrop = main.find_child("TitleBackdrop", true, false)
	return backdrop is CanvasItem and backdrop.is_visible_in_tree() and main.overlay.is_ancestor_of(backdrop)

func title_checks(main, label: String) -> void:
	check(main.overlay.visible and backdrop_visible(main), label + ": title backdrop shown")
	var title := by_text(main, "음영 인쇄소")
	check(title is Label, label + ": large product title")
	if title is Label:
		var font: Font = title.get_theme_font("font")
		check(font.get_font_name().contains("Myeongjo") or font.get_font_name().contains("명조"), label + ": title uses NanumMyeongjo")
		check(title.get_theme_font_size("font_size") >= 44, label + ": title is display-sized")
	var found: Array = []
	visible_controls(main.overlay, found)
	check(found.any(func(item): return item is Label and str(item.text).contains("1998")), label + ": 1998 subtitle")
	for text in MENU:
		check(by_text(main, text) is Button, label + ": menu action " + text)
	check(by_text(main, "이어하기") is Button or by_text(main, "이어하기 (저장 없음)") is Button, label + ": continue action")
	var focus: Control = main.get_viewport().gui_get_focus_owner()
	check(focus is Button and focus.text == "처음부터", label + ": focus starts on 처음부터")
	for item in found:
		if item is Button:
			var rect: Rect2 = item.get_global_rect()
			check(rect.position.x >= -1.0 and rect.end.x <= main.get_viewport_rect().size.x + 1.0, label + ": no horizontal overflow " + item.text)

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	title_checks(main, "fresh start")
	await escape()
	check(main.overlay.visible and not main.game_active and backdrop_visible(main), "Escape never starts or closes the title")
	main._open_help()
	await process_frame
	check(main.overlay.visible and not backdrop_visible(main), "help from the title uses the normal document dialog")
	main._return_from_help()
	await process_frame
	check(backdrop_visible(main), "returning from help restores the title")
	main._set_font_scale(1.5)
	main._open_start()
	await process_frame
	title_checks(main, "150% font")
	main._set_font_scale(1.0)
	main._open_start()
	await process_frame
	var start := by_text(main, "처음부터")
	if start is Button:
		start.pressed.emit()
	await process_frame
	check(main.game_active and not backdrop_visible(main), "처음부터 starts play and hides the title backdrop")
	main.free()
	print("TITLE_SCREEN_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("TITLE_SCREEN_PASS")
	quit(0 if failures.is_empty() else 2)
