extends SceneTree
## Trusted S09 probe: gameplay sits in a visible night printshop scene: a full
## screen NightScene texture (assets/art/scene_shop_night.svg) behind the UI and
## an Atmosphere layer using shaders/atmosphere.gdshader between the scene and
## the UI. The shader's `motion` uniform is 0 with reduced motion and positive
## otherwise. Layers never take input. Not an aesthetic or listening review.
var failures: Array = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("NIGHT ATMOSPHERE FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func motion(layer) -> float:
	var material = layer.material
	return float(material.get_shader_parameter("motion")) if material is ShaderMaterial else -1.0

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	await process_frame
	var scene = main.find_child("NightScene", true, false)
	var layer = main.find_child("Atmosphere", true, false)
	check(scene is TextureRect and scene.texture != null and scene.texture.resource_path == "res://assets/art/scene_shop_night.svg", "night printshop scene texture")
	check(scene is TextureRect and scene.is_visible_in_tree() and scene.mouse_filter == Control.MOUSE_FILTER_IGNORE, "scene visible and input-transparent")
	check(layer is CanvasItem and layer.material is ShaderMaterial and layer.material.shader != null and layer.material.shader.resource_path == "res://shaders/atmosphere.gdshader", "atmosphere shader layer")
	if scene == null or layer == null:
		main.free()
		quit(2)
		return
	check(layer.is_visible_in_tree() and (not layer is Control or layer.mouse_filter == Control.MOUSE_FILTER_IGNORE), "atmosphere visible and input-transparent")
	check(layer.is_greater_than(scene) and main.heading.is_greater_than(layer) and main.overlay.is_greater_than(layer), "layer order: scene < atmosphere < UI < dialogs")
	main._setting_value_changed(false, "reduce_motion")
	check(motion(layer) > 0.0, "subtle motion enabled by default")
	main._setting_value_changed(true, "reduce_motion")
	check(motion(layer) == 0.0, "reduced motion stops atmosphere motion")
	main._setting_value_changed(false, "reduce_motion")
	check(motion(layer) > 0.0, "motion restored when reduced motion is turned off")
	var image: Image = scene.texture.get_image()
	var dark := 0
	var samples := 0
	for y in range(0, image.get_height(), 16):
		for x in range(0, image.get_width(), 16):
			samples += 1
			if image.get_pixel(x, y).get_luminance() < 0.35:
				dark += 1
	check(samples > 0 and float(dark) / samples > 0.35, "the scene reads as night (enough dark area)")
	main.free()
	print("NIGHT_ATMOSPHERE_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("NIGHT_ATMOSPHERE_PASS")
	quit(0 if failures.is_empty() else 2)
