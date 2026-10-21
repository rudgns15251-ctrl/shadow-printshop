extends SceneTree
## Trusted S11 probe: story scenes have restrained motion and sound that respect
## the settings. A scene fades in, a new speaker's portrait fades in, the room
## atmosphere shader also lies over the scene, and each line turn plays the
## paper sound. Reduced motion makes everything immediate and still; SFX volume
## zero silences the turn. Input is never held by a fade, skipping mid-fade
## leaves nothing running, and the next scene starts clean. Not a taste review.
var failures: Array = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("SCENE MOTION FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func scene_with_speaker_change() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_scenes.json"))
	for scene in parsed["scenes"]:
		var lines: Array = scene["lines"]
		for index in range(1, lines.size()):
			if not str(lines[index]["speaker"]).is_empty() and str(lines[index]["speaker"]) != str(lines[index - 1]["speaker"]):
				return {"scene": scene, "index": index}
	return {}

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	main._setting_value_changed(false, "reduce_motion")
	var found := scene_with_speaker_change()
	check(not found.is_empty(), "a scene changes speaker")
	if found.is_empty():
		main.free()
		quit(2)
		return
	var scene: Dictionary = found["scene"]
	var stage: Control = main.find_child("StoryStage", true, false)
	var frame: Control = stage.find_child("PortraitFrame", true, false)
	var shaded := false
	for node in stage.find_children("*", "ColorRect", true, false):
		if node.material is ShaderMaterial and node.material.shader != null and node.material.shader.resource_path == "res://shaders/atmosphere.gdshader":
			shaded = node.material.get_shader_parameter("motion") > 0.0
	check(shaded, "the room atmosphere moves over the scene")
	# Fade in, never holding input.
	main.play_scene(str(scene["id"]))
	await process_frame
	check(stage.modulate.a < 0.99, "scene fades in")
	key(KEY_SPACE)
	await process_frame
	check(int(stage.line_index) == 1, "a key during the fade still reads one line")
	await wait(0.8)
	check(is_equal_approx(stage.modulate.a, 1.0), "fade completes")
	# Speaker change fades the portrait in and turns the page with sound.
	main.dismiss_story()
	main.play_scene(str(scene["id"]))
	await wait(0.8)
	for i in range(int(found["index"]) - 1):
		stage.advance()
	await wait(0.6)
	main.audio["paper"].stop()
	stage.advance()
	await process_frame
	check(int(stage.line_index) == int(found["index"]), "advanced to the new speaker")
	check(frame.modulate.a < 0.99, "a new speaker's portrait fades in")
	check(main.audio["paper"].playing, "turning a line plays the paper sound")
	await wait(0.6)
	check(is_equal_approx(frame.modulate.a, 1.0), "portrait fade completes")
	# Skip mid-fade leaves nothing running; the next scene starts clean.
	main.dismiss_story()
	main.play_scene(str(scene["id"]))
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(not stage.visible and not main.overlay.visible, "Escape mid-fade closes the scene")
	await wait(0.8)
	check(not stage.visible, "no fade reopens a skipped scene")
	# SFX zero silences the turn.
	main._setting_value_changed(0.0, "sfx")
	main.play_scene(str(scene["id"]))
	await wait(0.8)
	main.audio["paper"].stop()
	stage.advance()
	await process_frame
	check(not main.audio["paper"].playing or main.audio["paper"].volume_db <= -79.0, "SFX volume zero silences the line turn")
	main.dismiss_story()
	main._setting_value_changed(0.7, "sfx")
	# Reduced motion: immediate and still.
	main._setting_value_changed(true, "reduce_motion")
	main.play_scene(str(scene["id"]))
	await process_frame
	check(is_equal_approx(stage.modulate.a, 1.0), "reduced motion: no scene fade")
	for i in range(int(found["index"])):
		stage.advance()
	await process_frame
	check(is_equal_approx(frame.modulate.a, 1.0), "reduced motion: no portrait fade")
	for node in stage.find_children("*", "ColorRect", true, false):
		if node.material is ShaderMaterial and node.material.shader != null and node.material.shader.resource_path == "res://shaders/atmosphere.gdshader":
			check(node.material.get_shader_parameter("motion") == 0.0, "reduced motion stops the scene atmosphere")
	main.dismiss_story()
	main._setting_value_changed(false, "reduce_motion")
	main.free()
	print("SCENE_MOTION_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("SCENE_MOTION_PASS")
	quit(0 if failures.is_empty() else 2)
