extends SceneTree
## Google Play graphics from the game itself (run windowed, not headless):
##   godot --path <game> --script store_graphics.gd -- output=<dir>
## icon-512.png          adaptive background + foreground layers, full square
## feature-graphic-1024x500.png  the night shop plate with the title in the game's fonts
## screenshot-*.png      1920x1080 renders of the game in touch mode (no editing)
const UiTheme := preload("res://scripts/ui_theme.gd")
var output := ""
var main

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			output = arg.substr(7)
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func svg(path: String, size: int) -> Image:
	var image := Image.new()
	var text := FileAccess.get_file_as_string(path)
	var width := float(text.get_slice("width=\"", 1).get_slice("\"", 0))
	image.load_svg_from_string(text, size / width)
	image.convert(Image.FORMAT_RGBA8)
	return image

func icon() -> void:
	var canvas := svg("res://assets/art/android_icon_background.svg", 512)
	var front := svg("res://assets/art/android_icon_foreground.svg", 512)
	canvas.blend_rect(front, Rect2i(Vector2i.ZERO, front.get_size()), Vector2i.ZERO)
	canvas.save_png(output.path_join("icon-512.png"))

func feature() -> void:
	root.size = Vector2i(1024, 500)
	DisplayServer.window_set_size(root.size)
	# Pixel coordinates for this one image; the game's own scaling returns after.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	var plate := TextureRect.new()
	plate.texture = load("res://assets/art/scene_shop_night.svg")
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(plate)
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.NIGHT, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(shade)
	var mark := TextureRect.new()
	mark.texture = ImageTexture.create_from_image(svg("res://assets/art/app_icon.svg", 300))
	mark.position = Vector2(660, 100)
	mark.size = Vector2(300, 300)
	stage.add_child(mark)
	var column := VBoxContainer.new()
	column.position = Vector2(72, 150)
	column.size = Vector2(560, 220)
	column.add_theme_constant_override("separation", 14)
	stage.add_child(column)
	for row in [["음영 인쇄소", UiTheme.MYEONGJO_BOLD, 84, UiTheme.LAMP], ["1998년 11월 17일 밤", UiTheme.MYEONGJO, 30, UiTheme.PAPER],
			["도장을 찍어 견본을 맞추는 미스터리 퍼즐", UiTheme.GOTHIC, 24, Color(UiTheme.PAPER, 0.86)]]:
		var label := Label.new()
		label.text = row[0]
		label.add_theme_font_override("font", row[1])
		label.add_theme_font_size_override("font_size", row[2])
		label.add_theme_color_override("font_color", row[3])
		label.add_theme_color_override("font_outline_color", UiTheme.SHADOW)
		label.add_theme_constant_override("outline_size", 6)
		column.add_child(label)
	await frames(10)
	root.get_texture().get_image().save_png(output.path_join("feature-graphic-1024x500.png"))
	stage.free()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

func solve(index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func shot(name: String) -> void:
	await frames(12)
	var image: Image = root.get_texture().get_image()
	if image.get_size() != Vector2i(1920, 1080):
		image.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	image.save_png(output.path_join("screenshot-%s.png" % name))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	icon()
	await feature()
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.autosave_enabled = false
	main._setting_value_changed(true, "reduce_motion")
	main.set_touch_mode(true)
	main._open_start()
	await shot("1-title")
	main.start_new()
	main.dismiss_story()
	# First order, one stamp printed: the preview and the target side by side.
	var first: Array = main.session.puzzle_data()[0]["solution"]
	main.puzzle_view._select(int(int(first[0]) / 4))
	main.session.set_rotation(int(first[0]) % 4)
	main.puzzle_view._print()
	await shot("2-workbench")
	main._open_order()
	await shot("3-order")
	main.dismiss_story()
	var scene_id := str(main.scene_rows()[0]["id"])
	main.play_scene(scene_id, Callable())
	await frames(4)
	main.find_child("StoryStage", true, false).advance()
	await shot("4-scene")
	main.find_child("StoryStage", true, false).skip()
	main.dismiss_story()
	# The last order of the first chapter, from a fresh night.
	main.start_new()
	main.dismiss_story()
	for index in range(0, 7):
		main.dismiss_story()
		solve(index)
		main.advance()
	main.dismiss_story()
	await shot("5-order8")
	main._open_journal()
	await shot("6-journal")
	main.dismiss_story()
	main.free()
	quit(0)
