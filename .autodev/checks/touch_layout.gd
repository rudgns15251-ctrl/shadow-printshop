extends SceneTree
## Trusted S13 probe: the play screen laid out for fingers. In touch mode, at the
## logical sizes of 16:9, 19.5:9, 20:9 phones and a 16:10 tablet (720 tall), with
## text at 100% and 125%: a TouchBar of large keys (stamps, both rotations,
## print, undo, next) and a top bar with a menu key, the order card and the hint
## key, every key at least 80 logical px tall and inside the window; the three
## sheets side by side, unscrolled, at least 150 px each and never under the bar
## or status line; desktop-only keys hidden (they live in the menu); the notch
## safe area respected. Desktop layout returns when touch mode is off.
var failures: Array = []
var checks := 0
const MIN_KEY := 80.0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("TOUCH LAYOUT FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(8):
		await process_frame

func inside(rect: Rect2, view: Rect2) -> bool:
	return rect.position.x >= view.position.x - 1 and rect.position.y >= view.position.y - 1 and rect.end.x <= view.end.x + 1 and rect.end.y <= view.end.y + 1

func visible_buttons(node: Node, out: Array, skip: Node) -> void:
	for child in node.get_children():
		if child == skip or (child is CanvasItem and not child.is_visible_in_tree()):
			continue
		if child is Button:
			out.append(child)
		visible_buttons(child, out, skip)

func layout(main, label: String) -> void:
	await settle()
	var view: Rect2 = main.get_viewport_rect()
	var bar = main.find_child("TouchBar", true, false)
	check(bar is Control and bar.is_visible_in_tree(), label + ": touch bar shown")
	if not bar is Control:
		return
	var keys: Array = [main.stamp_buttons[0], main.stamp_buttons[1], main.print_button, main.undo_button, main.next_button]
	for item in main.rotate_keys:
		keys.append(item)
	for item in keys:
		check(bar.is_ancestor_of(item), label + ": '" + str(item.text).left(12) + "' is on the touch bar")
	var top = main.find_child("TouchTopBar", true, false)
	var menu_key = main.find_child("TouchMenuKey", true, false)
	check(top is Control and top.is_visible_in_tree() and menu_key is Button and top.is_ancestor_of(menu_key) and top.is_ancestor_of(main.order_card), label + ": top bar with the menu key and order card")
	var buttons: Array = []
	visible_buttons(main, buttons, main.overlay)
	for item in buttons:
		var rect: Rect2 = item.get_global_rect()
		check(rect.size.y >= MIN_KEY - 0.5, label + ": key '" + str(item.text).left(12) + "' at least 80 px tall (" + str(int(rect.size.y)) + ")")
		check(inside(rect, view), label + ": key '" + str(item.text).left(12) + "' inside the window")
	var scroll: ScrollContainer = main.find_child("WorkbenchScroll", true, false)
	check(scroll != null and scroll.scroll_vertical == 0, label + ": unscrolled")
	check(main.boards_grid.columns == 3, label + ": three sheets side by side")
	var bar_rect: Rect2 = bar.get_global_rect()
	var footer: Rect2 = main.feedback.get_parent().get_global_rect()
	for view_node in [main.before_view, main.after_view, main.target_view]:
		var rect: Rect2 = view_node.get_global_rect()
		check(minf(rect.size.x, rect.size.y) >= 150.0, label + ": sheet at least 150 px (" + str(int(minf(rect.size.x, rect.size.y))) + ")")
		check(inside(rect, view) and not rect.intersects(bar_rect) and not rect.intersects(footer), label + ": sheet visible, not under the bar or status line")
	for name in ["의뢰서", "기록함", "도움말", "설정", "메뉴", "진행 저장", "저장 불러오기"]:
		for item in buttons:
			check(str(item.text) != name, label + ": desktop key '" + name + "' moved into the menu")

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.autosave_enabled = false
	main.start_new()
	main.dismiss_story()
	check(main.has_method("set_touch_mode"), "touch mode available")
	if not main.has_method("set_touch_mode"):
		main.free()
		quit(2)
		return
	main.set_touch_mode(true)
	for size in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1600, 720), Vector2i(1152, 720)]:
		for scale in [1.0, 1.25]:
			root.size = size
			main._set_font_scale(scale)
			await layout(main, "%dx%d %d%%" % [size.x, size.y, int(scale * 100)])
	main._set_font_scale(1.0)
	root.size = Vector2i(1600, 720)
	# The menu key opens the menu with the moved keys.
	var menu_key = main.find_child("TouchMenuKey", true, false)
	if menu_key is Button:
		menu_key.pressed.emit()
		await settle()
		var texts := ""
		for node in main.dialog.find_children("*", "Button", true, false):
			texts += str(node.text) + "\n"
		for name in ["기록함", "도움말", "설정", "이야기"]:
			check(texts.contains(name), "menu offers " + name)
		main.dismiss_story()
	# Notch: a left inset keeps every key clear of it.
	if main.has_method("apply_safe_area"):
		main.apply_safe_area(Rect2i(Vector2i(88, 0), Vector2i(1600 - 88 - 40, 720)))
		await settle()
		var buttons: Array = []
		visible_buttons(main, buttons, main.overlay)
		var clear := true
		for item in buttons:
			if item.get_global_rect().position.x < 88 - 0.5 or item.get_global_rect().end.x > 1600 - 40 + 0.5:
				clear = false
		check(clear, "keys stay inside the display safe area")
		main.apply_safe_area(Rect2i(Vector2i.ZERO, Vector2i(1600, 720)))
	else:
		check(false, "campaign applies the display safe area")
	# Off again: the desktop layout returns.
	main.set_touch_mode(false)
	root.size = Vector2i(1280, 720)
	await settle()
	var bar = main.find_child("TouchBar", true, false)
	check(bar == null or not bar.is_visible_in_tree(), "desktop hides the touch bar")
	check(main.print_button.is_visible_in_tree() and main.find_child("StampBench", true, false).is_ancestor_of(main.print_button), "desktop print key back on the stamp bench")
	main.free()
	print("TOUCH_LAYOUT_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("TOUCH_LAYOUT_PASS")
	quit(0 if failures.is_empty() else 2)
