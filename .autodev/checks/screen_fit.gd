extends SceneTree
## Trusted S12 probe: the play screen fits and reads at every supported size.
## At 1280x720 and 1920x1080 with text at 100/125/150%: three sheets side by
## side, the 견본 sheet and the print key visible without scrolling and never
## under the status bar, a one-line heading with no padding, one row of flat
## status chips, a dark backing behind the header, one header arrangement per
## width, ink-dark bench text on wood. The finished campaign shows the ending
## instead of the sheets (undo restores them); long documents say how to read on;
## focus returns where the player was after a scene; the fluorescent band burns
## only in the night shop; reduced motion stops a running fade. Not a taste review.
var failures: Array = []
var checks := 0
const WOOD := Color("#d8c7ad")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("SCREEN FIT FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(8):
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release)

func inside(rect: Rect2, view: Rect2) -> bool:
	return rect.position.x >= view.position.x - 1 and rect.position.y >= view.position.y - 1 and rect.end.x <= view.end.x + 1 and rect.end.y <= view.end.y + 1

func contrast(a: Color, b: Color) -> float:
	var hi := maxf(a.get_luminance(), b.get_luminance())
	var lo := minf(a.get_luminance(), b.get_luminance())
	return (hi + 0.05) / (lo + 0.05)

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func tube(layer) -> float:
	return float(layer.material.get_shader_parameter("tube")) if layer is CanvasItem and layer.material is ShaderMaterial and layer.material.get_shader_parameter("tube") != null else -1.0

func play_screen(main, label: String) -> void:
	await settle()
	var scroll: ScrollContainer = main.find_child("WorkbenchScroll", true, false)
	var footer: Control = main.feedback.get_parent()
	check(scroll != null and scroll.scroll_vertical == 0, label + ": opens unscrolled")
	if scroll == null:
		return
	var view: Rect2 = scroll.get_global_rect()
	check(main.boards_grid.columns == 3, label + ": three sheets side by side")
	var target_card: Control = main.target_view.get_parent().get_parent()
	check(inside(target_card.get_global_rect(), view), label + ": 견본 sheet visible without scrolling")
	check(inside(main.print_button.get_global_rect(), view), label + ": print key visible without scrolling")
	check(not main.print_button.get_global_rect().intersects(footer.get_global_rect()), label + ": print key never under the status bar")
	check(main.heading.autowrap_mode == TextServer.AUTOWRAP_OFF and not str(main.heading.text).contains("  ") and main.heading.get_line_count() == 1, label + ": one-line heading without padding")
	var rows := {}
	for chip in main.progress_indicators:
		rows[int(chip.get_global_rect().position.y)] = true
	check(rows.size() == 1, label + ": all status chips on one row")
	var idx: int = int(main.session.snapshot()["puzzle"])
	for i in range(main.progress_indicators.size()):
		if i != idx:
			var style = main.progress_indicators[i].get_theme_stylebox("panel")
			check(style is StyleBoxFlat and style.shadow_size == 0, label + ": status chip %d is flat, not a key" % (i + 1))
			break
	var backing = main.find_child("HeaderBacking", true, false)
	var night = backing.get_theme_stylebox("panel") if backing is PanelContainer else null
	check(backing is PanelContainer and backing.is_ancestor_of(main.heading) and night is StyleBoxFlat and night.bg_color.get_luminance() < 0.2 and night.bg_color.a >= 0.6, label + ": header on a dark backing")
	check(main.title_navigation.vertical == false, label + ": header keeps one arrangement on a wide window")
	var bench = main.find_child("StampBench", true, false)
	if bench != null:
		for node in bench.find_children("*", "Label", true, false):
			# Only text lying directly on the wood (not on the ink selection strip).
			var surface: Node = node.get_parent()
			while surface != null and not surface is PanelContainer:
				surface = surface.get_parent()
			if surface == bench and node.is_visible_in_tree() and not str(node.text).is_empty():
				check(contrast(node.get_theme_color("font_color"), WOOD) >= 4.5, label + ": bench text readable on wood '" + str(node.text).left(12) + "'")

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.autosave_enabled = false
	main.start_new()
	main.dismiss_story()
	var room = main.find_child("Atmosphere", true, false)
	for res in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for scale in [1.0, 1.25, 1.5]:
			root.size = res
			main._set_font_scale(scale)
			await play_screen(main, "%dx%d %d%% first order" % [res.x, res.y, int(scale * 100)])
	check(tube(room) == 1.0, "the fluorescent band burns in the night shop (chapter 1)")
	for index in range(13):
		main.dismiss_story()
		solve(main, index)
		main.advance()
	main.dismiss_story()
	check(tube(room) == 0.0, "the tube is off after midnight (chapter 3 room)")
	for res in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for scale in [1.0, 1.25, 1.5]:
			root.size = res
			main._set_font_scale(scale)
			await play_screen(main, "%dx%d %d%% chapter 3" % [res.x, res.y, int(scale * 100)])
	root.size = Vector2i(1280, 720)
	main._set_font_scale(1.0)
	# Scenes: the band follows the plate.
	var stage = main.find_child("StoryStage", true, false)
	var scene_layer = stage.find_child("SceneAtmosphere", true, false) if stage != null else null
	main.play_scene("SC_OPENING")
	await settle()
	check(tube(scene_layer) == 1.0, "opening scene in the night shop keeps the band")
	main.dismiss_story()
	main.play_scene("SC_C02_MIDNIGHT")
	await settle()
	check(tube(scene_layer) == 0.0, "after-midnight scene has no tube band")
	# Reduced motion stops a fade already running.
	main.dismiss_story()
	main.play_scene("SC_OPENING")
	await process_frame
	main._setting_value_changed(true, "reduce_motion")
	check(stage != null and is_equal_approx(stage.modulate.a, 1.0), "reduced motion stops a running scene fade")
	main.dismiss_story()
	main._setting_value_changed(false, "reduce_motion")
	# Long documents say how to read on; short ones do not.
	main._set_font_scale(1.5)
	main._open_help()
	await settle()
	var hint = main.find_child("DialogHint", true, false)
	check(hint is Label and hint.is_visible_in_tree() and main.popup_panel.is_ancestor_of(hint) and not main.popup_scroll.is_ancestor_of(hint) and str(hint.text).contains("PageDown"), "long help shows how to read on, outside the scrolling text")
	check(inside(main.popup_panel.get_global_rect(), main.get_viewport_rect()), "long dialog panel inside the window")
	main.dismiss_story()
	main._set_font_scale(1.0)
	root.size = Vector2i(1920, 1080)
	main.puzzle_view._print()
	main._open_hint()
	await settle()
	check(not (hint is Label and hint.is_visible_in_tree()), "short dialog has no reading hint")
	main.dismiss_story()
	main.puzzle_view._undo()
	root.size = Vector2i(1280, 720)
	# The ending replaces the sheets; undo restores them.
	for index in range(13, 18):
		main.dismiss_story()
		solve(main, index)
		if index < 17:
			main.advance()
	await settle()
	var bench = main.find_child("Workbench", true, false)
	check(main.is_finished() and main.ending_panel.visible and bench is Control and not bench.visible, "finished campaign shows the ending instead of the sheets")
	main._set_font_scale(1.5)
	await settle()
	var ending_rows := {}
	for chip in main.progress_indicators:
		ending_rows[int(chip.get_global_rect().position.y)] = true
	check(ending_rows.size() == 1, "finished campaign at 150%: all status chips on one row")
	main._set_font_scale(1.0)
	await settle()
	var keys = main.ending_panel.find_child("EndingKeys", true, false)
	var key_count := 0
	if keys is BoxContainer:
		for item in keys.get_children():
			if item is Button:
				key_count += 1
				check(inside(item.get_global_rect(), main.find_child("WorkbenchScroll", true, false).get_global_rect()), "ending key visible without scrolling: " + str(item.text))
		var text_before := false
		for node in keys.get_parent().get_children():
			if node == keys:
				break
			if node is Label and str(node.text).length() > 60:
				text_before = true
		check(text_before, "ending text comes before its keys")
	check(key_count >= 3, "ending keys share one row")
	main._undo()
	await settle()
	check(bench is Control and bench.visible and not main.ending_panel.visible, "undo brings the sheets back")
	main.puzzle_view._select(int(int(main.session.puzzle_data()[17]["solution"][-1]) / 4))
	main.session.set_rotation(int(main.session.puzzle_data()[17]["solution"][-1]) % 4)
	main.puzzle_view._print()
	await settle()
	check(main.is_finished(), "finished again")
	# Focus returns where the player was after a scene.
	var scene_key: Button = null
	for node in main.ending_panel.find_children("*", "Button", true, false):
		if str(node.text).contains("결말 장면"):
			scene_key = node
	if scene_key != null:
		scene_key.pressed.emit()
		await settle()
		key(KEY_ESCAPE)
		await settle()
		check(main.get_viewport().gui_get_focus_owner() == scene_key, "after the ending scene focus returns to its key")
	main._open_story()
	await settle()
	var entry: Button = null
	for node in main.dialog.find_children("*", "Button", true, false):
		if str(node.text).begins_with("장면 · ") and not node.disabled:
			entry = node
	if entry != null:
		var label := str(entry.text)
		entry.pressed.emit()
		await settle()
		key(KEY_ESCAPE)
		await settle()
		var focus: Control = main.get_viewport().gui_get_focus_owner()
		check(focus is Button and str(focus.text) == label and main.dialog.is_ancestor_of(focus), "after a replay focus returns to that scene's entry")
	main.dismiss_story()
	main.free()
	print("SCREEN_FIT_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("SCREEN_FIT_PASS")
	quit(0 if failures.is_empty() else 2)
