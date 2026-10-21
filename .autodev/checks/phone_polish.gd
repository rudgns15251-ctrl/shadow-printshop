extends SceneTree
## Trusted S14 probe: what a phone player sees in touch mode, beyond key sizes.
## The chosen stamp's shape stays on screen (the wood stamp moves to the touch
## bar) and so does the instruction line; the top bar sits on a dark backing
## that keeps the heading readable over every room plate; the sheets use the
## height the bench left instead of leaving an empty band above the bar. Phones
## have no 종료 key (the system closes apps), the settings note speaks of this
## device, and the touch help says where 초기화 and saving went. Dialogs and story
## scenes stay clear of the notch. Turning touch mode off restores the desktop.
var failures: Array = []
var checks := 0
const BAND := 48.0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("PHONE POLISH FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(8):
		await process_frame

func texts(node: Node, kind: String) -> String:
	var found := ""
	for child in node.find_children("*", kind, true, false):
		if child is CanvasItem and child.is_visible_in_tree():
			found += str(child.text) + "\n"
	return found

func luminance(c: Color) -> float:
	var parts: Array = []
	for v in [c.r, c.g, c.b]:
		parts.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]

func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

func backing_of(node: Node, top: Node) -> StyleBoxFlat:
	var at := node.get_parent()
	while at != null and at != top:
		if at is PanelContainer and at.get_theme_stylebox("panel") is StyleBoxFlat:
			return at.get_theme_stylebox("panel")
		at = at.get_parent()
	return null

func inside_x(rect: Rect2, left: float, right: float) -> bool:
	return rect.position.x >= left - 0.5 and rect.end.x <= right + 0.5

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.autosave_enabled = false
	# Desktop first: the title keeps 종료 and the settings note names the computer.
	main._open_start()
	await settle()
	check(texts(main.dialog, "Button").contains("종료"), "desktop title keeps 종료")
	main.set_touch_mode(true)
	main._open_start()
	await settle()
	check(not texts(main.dialog, "Button").contains("종료"), "no 종료 key on a phone (the system closes apps)")
	check(texts(main.dialog, "Button").contains("처음부터") and texts(main.dialog, "Button").contains("설정"), "phone title keeps its other keys")
	main._open_settings()
	await settle()
	var notes := texts(main.dialog, "Label")
	check(notes.contains("설정은 이 기기에 저장됩니다.") and not notes.contains("이 컴퓨터"), "settings note speaks of this device")
	main._open_help()
	await settle()
	var help := texts(main.dialog, "Label")
	check(help.contains("메뉴") and help.contains("초기화") and help.contains("저장"), "touch help says where 초기화 and saving are")
	main.start_new()
	main.dismiss_story()
	await settle()
	var bar = main.find_child("TouchBar", true, false)
	check(bar is Control and bar.is_visible_in_tree(), "touch bar shown")
	if not bar is Control:
		print("PHONE_POLISH_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
		quit(2)
		return
	# The stamp's shape (with its 1 = 뒤집힐 칸 mask) stays on screen.
	check(main.stamp_view.is_visible_in_tree() and bar.is_ancestor_of(main.stamp_view), "the chosen stamp's shape is on the touch bar")
	check(main.stamp_mask_view.is_visible_in_tree() and main.stamp_view.get_global_rect().size.y >= 64.0, "stamp shape at least 64 px tall")
	check(main.stamp_view.get_global_rect().size.y <= bar.get_global_rect().size.y + 0.5, "stamp shape fits the bar height")
	# The instruction line is visible, without keyboard hints.
	var instruction := str(main.subheading.text).replace(char(0x2060), "")
	check(main.subheading.is_visible_in_tree() and instruction.contains("견본") and not instruction.contains("["), "instruction line visible: " + instruction)
	check(main.subheading.get_global_rect().end.y <= main.boards_grid.get_global_rect().position.y + 0.5, "instruction line above the sheets")
	# Heading and instruction on a dark backing (readable over bright plates).
	var top = main.find_child("TouchTopBar", true, false)
	for label in [main.heading, main.subheading]:
		var style := backing_of(label, main)
		check(style != null and style.bg_color.a >= 0.75 and contrast(style.bg_color, label.get_theme_color("font_color")) >= 4.5,
			"'" + str(label.text).left(14) + "' on a dark backing")
	check(top is Control and top.is_visible_in_tree(), "top bar shown")
	# The sheets take the height the bench left.
	for size in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1152, 720)]:
		for scale in [1.0, 1.25]:
			root.size = size
			main._set_font_scale(scale)
			await settle()
			var grid: Rect2 = main.boards_grid.get_global_rect()
			var scroll: Rect2 = main.find_child("WorkbenchScroll", true, false).get_global_rect()
			var band: float = bar.get_global_rect().position.y - grid.end.y
			var label := "%dx%d %d%%" % [size.x, size.y, int(scale * 100)]
			# When the sheets already fill the row (16:10 tablets), the rest of the height may stay.
			var full_width: bool = grid.size.x >= scroll.size.x - 48.0
			check(band <= (BAND * 2.0 if full_width else BAND), label + ": no empty band above the bar (" + str(int(band)) + " px)")
			check(grid.end.y <= scroll.end.y + 0.5 and grid.end.x <= scroll.end.x + 0.5, label + ": sheets wholly visible")
			var bench: Control = main.find_child("WorkbenchScroll", true, false).get_child(0)
			check(bench.get_combined_minimum_size().y <= scroll.size.y + 0.5, label + ": the whole workbench (captions, legend) fits unscrolled")
			check(minf(main.after_view.get_global_rect().size.x, main.after_view.get_global_rect().size.y) >= 150.0, label + ": sheets at least 150 px")
	main._set_font_scale(1.0)
	root.size = Vector2i(1600, 720)
	await settle()
	# Dialogs and story scenes stay clear of a notch.
	var view_w: float = main.get_viewport_rect().size.x
	main.apply_safe_area(Rect2i(Vector2i(88, 0), Vector2i(int(view_w) - 88, 720)))
	await settle()
	main._open_help()
	await settle()
	check(inside_x(main.popup_panel.get_global_rect(), 88, view_w - 88), "dialog clear of the notch")
	main.dismiss_story()
	var scene_id := str(main.scene_rows()[0]["id"])
	main.play_scene(scene_id, Callable())
	await settle()
	var stage = main.find_child("StoryStage", true, false)
	for name in ["AdvanceKey", "SkipKey", "NamePlate"]:
		var node = stage.find_child(name, true, false) if stage != null else null
		if node == null and name == "NamePlate":
			continue
		check(node is Control and inside_x(node.get_global_rect(), 88, view_w - 88), "scene " + name + " clear of the notch")
	if stage != null and stage.box != null:
		check(inside_x(stage.box.get_global_rect(), 88, view_w - 88), "scene text box clear of the notch")
	stage.skip()
	main.dismiss_story()
	main.apply_safe_area(Rect2i(Vector2i.ZERO, Vector2i(int(view_w), 720)))
	# Desktop again: the bench owns the stamp, the title row owns the instruction.
	main.set_touch_mode(false)
	root.size = Vector2i(1280, 720)
	await settle()
	var bench = main.find_child("StampBench", true, false)
	check(bench != null and bench.is_ancestor_of(main.stamp_view) and main.stamp_view.is_visible_in_tree(), "desktop: stamp back on the bench")
	check(main.title_navigation.is_ancestor_of(main.subheading) and main.subheading.is_visible_in_tree(), "desktop: instruction back in the title row")
	check(main.find_child("TouchTopBar", true, false) == null or not main.find_child("TouchTopBar", true, false).is_visible_in_tree(), "desktop: no touch top bar")
	main._open_start()
	await settle()
	check(texts(main.dialog, "Button").contains("종료"), "desktop: 종료 returns")
	main._open_settings()
	await settle()
	check(texts(main.dialog, "Label").contains("설정은 이 컴퓨터에 저장됩니다."), "desktop: settings note names the computer")
	main.dismiss_story()
	var margins: MarginContainer = main.title_navigation.get_parent().get_parent()
	check(margins.get_theme_constant("margin_left") == 16, "desktop margins unchanged")
	print("PHONE_POLISH_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	main.free()
	if failures.is_empty():
		print("PHONE_POLISH_PASS")
	quit(0 if failures.is_empty() else 2)
