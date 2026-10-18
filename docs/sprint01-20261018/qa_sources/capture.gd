extends SceneTree
const Data = preload("res://data/mech_data.gd")
var view
var output := ""
var records: Array = []
var failures: Array = []
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output = arg.substr(7)
	call_deferred("run")
func nodes(node: Node, out: Array) -> void:
	if node is Control: out.append(node)
	for child in node.get_children(): nodes(child, out)
func capture(label: String) -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var filename := "%dx%d-%d-%s.png" % [root.size.x,root.size.y,int(view.settings["font_scale"]*100),label]
	var code := root.get_texture().get_image().save_png(output.path_join(filename))
	if code != OK: failures.append(filename + " screenshot failed")
	var controls: Array = []
	nodes(view, controls)
	var outside: Array = []
	var layout_errors: Array = []
	var bounds := Rect2(Vector2.ZERO,Vector2(root.size))
	for item in controls:
		if not item.is_visible_in_tree() or not item is BaseButton: continue
		var rect: Rect2 = item.get_global_rect()
		# Main and modal content can be vertically scrolled; horizontal overflow cannot.
		if rect.position.x < -1.0 or rect.end.x > bounds.end.x + 1.0:
			outside.append(item.text)
	if label == "settings":
		for item in controls:
			if not item is Label or item.text not in ["전체 음량", "효과음"]: continue
			var text_width: float = item.get_theme_font("font").get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x
			if item.size.x + 1.0 < text_width:
				layout_errors.append(item.text + " label narrower than its short name")
			for sibling in item.get_parent().get_children():
				if sibling is HSlider and item.get_global_rect().intersection(sibling.get_global_rect()).get_area() > 1.0:
					layout_errors.append(item.text + " overlaps slider")
	if not layout_errors.is_empty(): failures.append(filename + " " + str(layout_errors))
	if not outside.is_empty(): failures.append(filename + " horizontal overflow " + str(outside))
	records.append({"image":filename,"size":[root.size.x,root.size.y],"font":view.settings["font_scale"],"screen":label,"horizontal_overflow":outside,"layout_errors":layout_errors,"state":view.state.snapshot()})
func close_dialog() -> void:
	view.overlay.hide()
	var focus = root.gui_get_focus_owner()
	if focus != null: focus.release_focus()
func run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2);return
	view=load("res://integrated_main.tscn").instantiate()
	view.autosave_enabled=false
	root.add_child(view)
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution
		for font_scale in [1.0,1.25,1.5]:
			view._set_font_scale(font_scale)
			view._open_start()
			await capture("start")
			close_dialog()
			view._new_game()
			await capture("play")
			view._open_help()
			await capture("help")
			close_dialog()
			view._open_settings()
			await capture("settings")
			close_dialog()
			view._open_pause()
			await capture("pause")
			close_dialog()
			for action in Data.PUZZLES[0]["solution"]:
				view._select(int(int(action)/4));view.state.set_rotation(int(action)%4);view._print()
			view._finish_reaction();view._clear_impression()
			await capture("complete")
	view.free();view=null
	var report={"passed":failures.is_empty(),"records":records,"failures":failures,"subjective_visual_review":"pending"}
	var f=FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "));f.close()
	print("SPRINT_CAPTURE_RESULT "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 2)
