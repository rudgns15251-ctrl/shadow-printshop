extends SceneTree
## Trusted S10 probe: the puzzle is laid out as a workbench. The three boards sit
## in a Workbench container, the stamp controls on a wood StampBench, and an
## OrderCard shows the current order (id and speaker) and opens it. At 100% font
## the three boards and the print key fit both target resolutions without
## scrolling; at 150% nothing overflows horizontally and print stays reachable.
var failures: Array = []
var checks := 0
const WOOD := Color("#d8c7ad")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("WORKBENCH LAYOUT FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func texts(node: Node) -> String:
	var out := str(node.text) if (node is Label or node is Button) else ""
	for child in node.get_children():
		out += "\n" + texts(child)
	return out

func settle() -> void:
	for i in range(8):
		await process_frame

func inside(rect: Rect2, view: Rect2) -> bool:
	return rect.position.x >= view.position.x - 1 and rect.position.y >= view.position.y - 1 and rect.end.x <= view.end.x + 1 and rect.end.y <= view.end.y + 1

func fits(main, label: String) -> void:
	await settle()
	var view: Rect2 = main.get_viewport_rect()
	for board in [main.before_view, main.after_view, main.target_view, main.print_button]:
		check(inside(board.get_global_rect(), view), label + ": " + board.name + " visible without scrolling")
	var scroll: ScrollContainer = main.find_child("WorkbenchScroll", true, false)
	if scroll == null:
		scroll = main.heading.get_parent()
		while scroll != null and not scroll is ScrollContainer:
			scroll = scroll.get_parent()
	check(scroll == null or scroll.scroll_vertical == 0, label + ": no scrolling needed")

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	var bench = main.find_child("Workbench", true, false)
	check(bench is Control and bench.is_ancestor_of(main.before_view) and bench.is_ancestor_of(main.after_view) and bench.is_ancestor_of(main.target_view), "boards are on the Workbench")
	var stamp_bench = main.find_child("StampBench", true, false)
	check(stamp_bench is Control and stamp_bench.is_ancestor_of(main.print_button) and stamp_bench.is_ancestor_of(main.stamp_view), "stamp and actions are on the StampBench")
	if stamp_bench is PanelContainer:
		var style = stamp_bench.get_theme_stylebox("panel")
		var color: Color = style.bg_color if style is StyleBoxFlat else Color.BLACK
		check(Vector3(color.r, color.g, color.b).distance_to(Vector3(WOOD.r, WOOD.g, WOOD.b)) < 0.3, "StampBench reads as wood")
	var card = main.find_child("OrderCard", true, false)
	check(card is BaseButton and card.is_visible_in_tree(), "order card visible and pressable")
	if card is BaseButton:
		check(texts(card).contains("의뢰 1") and texts(card).contains("백인호"), "order card names the current order and speaker")
		card.pressed.emit()
		await process_frame
		check(main.overlay.visible and texts(main.dialog).contains("의뢰서 · 의뢰 1"), "order card opens the order")
		main.dismiss_story()
		for action in main.session.puzzle_data()[0]["solution"]:
			main.puzzle_view._select(int(int(action) / 4))
			main.session.set_rotation(int(action) % 4)
			main.puzzle_view._print()
		main.advance()
		main.dismiss_story()
		await process_frame
		check(texts(card).contains("의뢰 2"), "order card follows the current puzzle")
	for res in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = res
		main._set_font_scale(1.0)
		await fits(main, "%dx%d 100%%" % [res.x, res.y])
	root.size = Vector2i(1280, 720)
	main._set_font_scale(1.5)
	await settle()
	var view: Rect2 = main.get_viewport_rect()
	var stack: Array = [main]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == main.overlay:
			continue
		if node is Button and node.is_visible_in_tree():
			var rect: Rect2 = node.get_global_rect()
			check(rect.position.x >= -1 and rect.end.x <= view.end.x + 1, "150%: no horizontal overflow '" + str(node.text).left(20) + "'")
		stack.append_array(node.get_children())
	main.print_button.grab_focus()
	await settle()
	check(inside(main.print_button.get_global_rect(), view), "150%: print key reachable by focus scrolling")
	main._set_font_scale(1.0)
	main.free()
	print("WORKBENCH_LAYOUT_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("WORKBENCH_LAYOUT_PASS")
	quit(0 if failures.is_empty() else 2)
