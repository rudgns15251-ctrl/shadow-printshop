# Optional GUI observation test; does not certify game counters/history/undo.
extends SceneTree

class FocusObserver:
	extends Node

	 var target: Button
	 var active_key: int = 0
	 var signal_count: int = 0
	 var echo_count: int = 0
	 var started_ms: int = 0
	 var awaiting_release_check: bool = false

	 func observe_button() -> void:
		 target.pressed.connect(_on_button_pressed)
		 target.grab_focus()
		 print("ITER-002: focus=", target.get_path(), "; manually try Space/Enter separately.")
		 print("Button signal counts are not actual PRINT/history/undo assertions.")

	 func _on_button_pressed() -> void:
		 if active_key != 0:
			 signal_count += 1

	 func _input(event: InputEvent) -> void:
		 if not event is InputEventKey:
			 return
		 var key_event := event as InputEventKey
		 var key := int(key_event.keycode)
		 if key != KEY_SPACE and key != KEY_ENTER:
			 return
		 if key_event.pressed:
			 if active_key == 0:
				 if key_event.echo or not target.has_focus():
					 push_error("ITER-002: invalid initial event/focus; reset and retry.")
					 return
				 active_key = key
				 signal_count = 0
				 echo_count = 0
				 started_ms = Time.get_ticks_msec()
			 elif active_key != key or awaiting_release_check:
				 push_error("ITER-002: overlapping input; this observation is invalid.")
			 elif key_event.echo:
				 echo_count += 1
		 elif active_key == key and not awaiting_release_check:
			 awaiting_release_check = true
			 _check_release(Time.get_ticks_msec() - started_ms)

	 func _check_release(held_ms: int) -> void:
		 await get_tree().process_frame
		 print("ITER-002 key=", active_key, " held_ms=", held_ms,
			 " echoes=", echo_count, " button_signals=", signal_count)
		 if signal_count != 1:
			 push_error("ITER-002: expected exactly one button signal for this physical press.")
		 print("Verify actual PRINT delta=1, history delta=1, and one undo restores initial state.")
		 active_key = 0
		 awaiting_release_check = false

func _initialize() -> void:
	call_deferred("_open_game")

func _open_game() -> void:
	var scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if scene_path.is_empty():
		push_error("ITER-002: no configured main_scene; run the manual checklist.")
		quit(1)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("ITER-002: main_scene cannot be loaded.")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var candidates: Array[Button] = []
	_find_print_buttons(game, candidates)
	if candidates.size() != 1:
		push_error("ITER-002: expected one identifiable PRINT Button; use manual checklist.")
		quit(1)
		return
	var observer := FocusObserver.new()
	observer.target = candidates[0]
	root.add_child(observer)
	observer.observe_button()

func _find_print_buttons(node: Node, candidates: Array[Button]) -> void:
	if node is Button:
		var button := node as Button
		if button.text.contains("인쇄") or button.text.to_lower().contains("print"):
			candidates.append(button)
	for child in node.get_children():
		_find_print_buttons(child, candidates)
