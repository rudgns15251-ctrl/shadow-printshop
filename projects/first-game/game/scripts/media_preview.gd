extends "res://scripts/main.gd"
## 기존 게임 규칙을 상속하며 성공한 상태 변화에만 미디어를 덧붙인다.

var sfx: Dictionary = {}
var stamp_art: TextureRect
var reaction: Tween

func _ready() -> void:
	super._ready()
	var panel := HBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = -94
	panel.offset_bottom = -10
	panel.add_theme_constant_override("separation", 16)
	add_child(panel)
	stamp_art = TextureRect.new()
	stamp_art.texture = preload("res://assets/art/stamp_preview.svg")
	stamp_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stamp_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp_art.custom_minimum_size = Vector2(180, 80)
	stamp_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stamp_art)
	for key in ["print", "undo", "complete"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/%s.wav" % key)
		player.volume_db = linear_to_db(0.6)
		add_child(player)
		sfx[key] = player
		var controls := VBoxContainer.new()
		controls.custom_minimum_size.x = 180
		panel.add_child(controls)
		var mute := CheckBox.new()
		mute.text = "%s SFX: mute" % key
		mute.focus_mode = Control.FOCUS_NONE
		controls.add_child(mute)
		var volume := HSlider.new()
		volume.min_value = 0.0
		volume.max_value = 1.0
		volume.step = 0.01
		volume.value = 0.6
		volume.focus_mode = Control.FOCUS_NONE
		volume.tooltip_text = "%s volume (0–100%%)" % key
		controls.add_child(volume)
		var update_volume := func():
			player.volume_db = -80.0 if mute.button_pressed or volume.value <= 0.0 else linear_to_db(volume.value)
			if mute.button_pressed or volume.value <= 0.0:
				player.stop()
		mute.toggled.connect(func(_enabled): update_volume.call())
		volume.value_changed.connect(func(_value): update_volume.call())

func _play(key: String) -> void:
	var player: AudioStreamPlayer = sfx.get(key)
	if player != null and player.volume_db > -80.0:
		player.play()

func _react(complete: bool = false) -> void:
	if reaction != null:
		reaction.kill()
	stamp_art.pivot_offset = stamp_art.size / 2.0
	stamp_art.scale = Vector2(0.88, 0.88)
	stamp_art.modulate = Color(1.0, 0.8, 0.65) if not complete else Color(0.75, 1.0, 0.85)
	reaction = create_tween().set_parallel(true)
	reaction.tween_property(stamp_art, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reaction.tween_property(stamp_art, "modulate", Color.WHITE, 0.30)

func _print() -> void:
	var old_moves: int = state.snapshot()["moves"]
	super._print()
	if state.snapshot()["moves"] > old_moves:
		_play("print")
		_react(state.is_solved())
		if state.is_solved():
			_play("complete")

func _undo() -> void:
	var old_history: int = state.snapshot()["history_size"]
	super._undo()
	if state.snapshot()["history_size"] < old_history:
		_play("undo")
		_react()
