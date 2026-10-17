extends SceneTree
const Scene = preload("res://integrated_main.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var view = Scene.instantiate()
	view.autosave_enabled = false
	root.add_child(view)
	view._new_game()
	view.overlay.hide()
	for repetition in range(100):
		view._play_sound("print")
		view._play_sound("undo")
		view._play_sound("complete")
		if repetition % 4 == 0:
			view._setting_value_changed(true, "mute")
			view._setting_value_changed(false, "mute")
	view.free()
	print("RAPID_SFX_IMMEDIATE_EXIT")
	quit(0)
