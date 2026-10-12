extends SceneTree

# Harness-owned diagnostic input probe. This tests that keyboard events can be
# dispatched to a live scene without script errors. It does not prove gameplay
# correctness, win conditions, or visual quality.
const KEYS = [KEY_1, KEY_2, KEY_Q, KEY_E, KEY_SPACE, KEY_U, KEY_Z, KEY_R]

func _initialize() -> void:
    call_deferred("_run")

func _press(key: Key) -> void:
    var down := InputEventKey.new()
    down.keycode = key
    down.pressed = true
    Input.parse_input_event(down)
    await process_frame
    var up := InputEventKey.new()
    up.keycode = key
    up.pressed = false
    Input.parse_input_event(up)
    await process_frame

func _label_text(node: Node) -> String:
    var out := ""
    if node is Label:
        out += (node as Label).text + "\n"
    for child in node.get_children():
        out += _label_text(child)
    return out

func _run() -> void:
    var scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
    if scene_path.is_empty():
        push_error("Harness scene probe: main_scene not configured")
        quit(13)
        return
    var packed := load(scene_path) as PackedScene
    if packed == null:
        push_error("Harness scene probe: main scene could not load")
        quit(14)
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    var before := _label_text(scene)
    for key in KEYS:
        await _press(key)
    var after := _label_text(scene)
    print("HARNESS_INPUT_LABELS_CHANGED=" + str(before != after))
    print("HARNESS_QA_SCENE_PASS")
    quit(0)
