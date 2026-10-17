extends SceneTree
## Supplemental mixer measurement. Existing leak probes remain unchanged.
var scene: Node
var results: Array = []
var failed := false

func _initialize() -> void:
	call_deferred("run")

func measure(key: String, phase: String) -> void:
	# A real SFX must produce a non-silent bus peak while its player runs.
	# The deadline only reports failure; elapsed time is never a success condition.
	scene._play_sound(key)
	var peak := -200.0
	var mixed := false
	var deadline := Time.get_ticks_usec() + 2_000_000
	while scene.audio[key].playing and Time.get_ticks_usec() < deadline:
		await process_frame
		var current: float = maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0))
		peak = maxf(peak, current)
		mixed = mixed or current > -70.0
	var ok: bool = mixed and not scene.audio[key].playing
	results.append({"sound": key, "phase": phase, "peak_db": peak, "passed": ok})
	if not ok:
		failed = true
		printerr("ERROR: SFX mixer measurement failed: " + key + " " + phase)

func run() -> void:
	print("PLAYBACK_BEGIN " + JSON.stringify({"driver": AudioServer.get_driver_name(), "engine": Engine.get_version_info()["string"]}))
	if AudioServer.get_driver_name() != "WASAPI":
		printerr("ERROR: actual WASAPI required")
		quit(2)
		return
	scene = load("res://integrated_main.tscn").instantiate()
	scene.autosave_enabled = false
	root.add_child(scene)
	scene._new_game()
	scene.overlay.hide()
	scene._setting_value_changed(false, "mute")
	scene._setting_value_changed(0.8, "master")
	scene._setting_value_changed(0.7, "sfx")
	for key in ["print", "undo", "complete"]:
		await measure(key, "initial")
	scene._setting_value_changed(true, "mute")
	for key in ["print", "undo", "complete"]:
		scene._play_sound(key)
		if scene.audio[key].playing:
			failed = true
			printerr("ERROR: muted SFX started")
	scene._setting_value_changed(false, "mute")
	for key in ["print", "undo", "complete"]:
		await measure(key, "after_unmute")
	scene._setting_value_changed(0.0, "sfx")
	for key in ["print", "undo", "complete"]:
		scene._play_sound(key)
		if scene.audio[key].playing:
			failed = true
			printerr("ERROR: zero-volume SFX started")
	scene._setting_value_changed(0.7, "sfx")
	for key in ["print", "undo", "complete"]:
		await measure(key, "after_zero_volume")
	scene.free()
	scene = null
	print("PLAYBACK_RESULT " + JSON.stringify({"driver": AudioServer.get_driver_name(), "passed": not failed, "measurements": results}))
	quit(2 if failed else 0)
