extends SceneTree
## Additional acceptance coverage. Run only with isolated user:// storage.
const Scene = preload("res://integrated_main.tscn")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SAVE SETTINGS FAIL: " + message)

func put(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "isolated fixture writable")
	if file != null:
		file.store_string(text)
		file.close()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var view = Scene.instantiate()
	view.autosave_enabled = false
	root.add_child(view)
	view._new_game()
	view.overlay.hide()
	var defaults: Dictionary = {"master": 0.8, "sfx": 0.7, "bgm": 0.3, "mute": false,
		"font_scale": 1.0, "reduce_motion": false}
	for malformed in ["", "{", "invalid json", "{\"mute\":", "null", "[]", "42", "true"]:
		view.settings = defaults.duplicate(true)
		put(view.SETTINGS_PATH, malformed)
		view._load_settings()
		check(view.settings == defaults, "malformed/non-object settings retain defaults")
	for scale in [1.0, 1.25, 1.5]:
		view.settings = defaults.duplicate(true)
		put(view.SETTINGS_PATH, JSON.stringify({"master": -1, "sfx": 2.5, "bgm": 0.6,
			"mute": true, "reduce_motion": true, "font_scale": scale}))
		view._load_settings()
		check(view.settings["master"] == 0.0 and view.settings["sfx"] == 1.0, "numeric clamp")
		check(view.settings["bgm"] == 0.6, "legacy bgm field retained")
		check(view.settings["mute"] and view.settings["reduce_motion"], "boolean settings retained")
		check(view.settings["font_scale"] == scale, "supported font scale retained")
	for invalid_scale in [0, 1.1, 2, "1.25", null, false]:
		view.settings = defaults.duplicate(true)
		put(view.SETTINGS_PATH, JSON.stringify({"master": "0.2", "sfx": true, "bgm": null,
			"mute": 1, "reduce_motion": "true", "font_scale": invalid_scale}))
		view._load_settings()
		check(view.settings == defaults, "wrong types and unsupported font scales rejected")
	view.settings = defaults.duplicate(true)
	view._print()
	view.hint_levels = [1, 2, 3, 0, 1, 2, 0, 0]
	var primary: Dictionary = view._serialize_progress().duplicate(true)
	check(view._save_progress(), "valid primary save")
	view._print()
	view.hint_levels = [3, 1, 2, 3, 0, 1, 2, 0]
	var other: Dictionary = view._serialize_progress().duplicate(true)
	put(view.SAVE_BACKUP, JSON.stringify(other))
	check(view._load_progress(), "valid primary loads")
	check(view._serialize_progress() == primary, "primary wins over different valid backup including hints/history")
	put(view.SAVE_PATH, "{truncated")
	check(view._load_progress(), "invalid primary falls back")
	check(view._serialize_progress() == other, "backup restores exact hints/state/history")
	put(view.SAVE_BACKUP, "{invalid")
	var retained: Dictionary = view._serialize_progress().duplicate(true)
	check(not view._load_progress(), "two invalid files rejected")
	check(view._serialize_progress() == retained, "failed load preserves exact hints/state/history")
	check(FileAccess.get_file_as_string(view.SAVE_PATH) == "{truncated", "failed load preserves invalid primary")
	check(FileAccess.get_file_as_string(view.SAVE_BACKUP) == "{invalid", "failed load preserves invalid backup")
	for invalid in ["", "{", "null", "[]", "0", "{\"schema_version\":1}"]:
		put(view.SAVE_PATH, invalid)
		check(view._read_valid_progress(view.SAVE_PATH) == null, "invalid progress rejected quietly")
	view.free()
	if failures == 0:
		print("SAVE_SETTINGS_PASS checks=%d" % checks)
		quit(0)
	else:
		printerr("SAVE_SETTINGS_FAIL checks=%d failures=%d" % [checks, failures])
		quit(2)
