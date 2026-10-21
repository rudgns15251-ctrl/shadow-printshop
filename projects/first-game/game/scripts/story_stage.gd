extends Control
## Story scene player inside the campaign's modal overlay: background, portrait,
## name plate, line kind and the line itself. The player advances every line;
## the host decides what follows. Reading never touches puzzle state or saves.

const UiTheme = preload("res://scripts/ui_theme.gd")
const ATMOSPHERE = preload("res://shaders/atmosphere.gdshader")
const SCENE_FADE := 0.35
const PORTRAIT_FADE := 0.3
const KIND_TEXT := {"live": "직접 말함", "document": "남겨진 문서", "narration": "기록"}

signal advanced
signal skipped

var scene_id := ""
var line_index := 0
var lines: Array = []
var background: TextureRect
var portrait_frame: PanelContainer
var portrait: TextureRect
var name_plate: Label
var line_kind: Label
var box: PanelContainer
var text: Label
var advance_key: Button
var skip_key: Button
var portrait_for: Callable
var atmosphere: ColorRect
var reduce_motion := false
var touch_mode := false
var _fades: Array[Tween] = []
var _portrait_fade: Tween

func build(host: Control) -> void:
	# Labels and keys come from the host so font scaling and key styling match
	# every other control in the campaign.
	name = "StoryStage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	background = TextureRect.new()
	background.name = "SceneBackground"
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	# The room's fluorescent flicker and paper grain also lie over the scenes.
	atmosphere = ColorRect.new()
	atmosphere.name = "SceneAtmosphere"
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = ATMOSPHERE
	atmosphere.material = material
	add_child(atmosphere)
	set_reduce_motion(false)
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.SHADOW, 0.30)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 28)
	add_child(margins)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	margins.add_child(column)
	# A portrait stands on the bench behind the dialogue paper.
	portrait_frame = PanelContainer.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := UiTheme.surface(UiTheme.PAPER, 6, 8)
	frame.set_content_margin_all(8)
	portrait_frame.add_theme_stylebox_override("panel", frame)
	column.add_child(portrait_frame)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(180, 210)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(portrait)
	box = PanelContainer.new()
	box.name = "DialogueBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := UiTheme.surface(UiTheme.PAPER, 10, 16)
	paper.border_color = Color(UiTheme.LAMP, 0.7)
	paper.set_border_width_all(2)
	paper.set_content_margin_all(20)
	box.add_theme_stylebox_override("panel", paper)
	column.add_child(box)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)
	var plate_row := HBoxContainer.new()
	plate_row.add_theme_constant_override("separation", 12)
	inner.add_child(plate_row)
	name_plate = host._label(plate_row, "", 22, UiTheme.VERMILION)
	name_plate.name = "NamePlate"
	name_plate.autowrap_mode = TextServer.AUTOWRAP_OFF
	UiTheme.title_font(name_plate)
	line_kind = host._label(plate_row, "", 14, UiTheme.GREEN)
	line_kind.name = "LineKind"
	line_kind.autowrap_mode = TextServer.AUTOWRAP_OFF
	line_kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text = host._label(inner, "", 20)
	text.name = "DialogueText"
	UiTheme.document_font(text)
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_END
	keys.add_theme_constant_override("separation", 8)
	inner.add_child(keys)
	skip_key = host._button(keys, "건너뛰기 [Esc]", skip, 150)
	skip_key.name = "SkipKey"
	skip_key.tooltip_text = "이 장면을 끝까지 넘깁니다. 이야기에서 다시 볼 수 있습니다."
	advance_key = host._button(keys, "다음 [Space]", advance, 150)
	advance_key.name = "AdvanceKey"
	host._primary_button(advance_key)
	advance_key.tooltip_text = "다음 줄을 읽습니다. Space · Enter · 클릭"
	# The two keys are the only focus stops while a scene plays (sibling paths,
	# valid before the stage enters the tree).
	for pair in [[advance_key, "../SkipKey"], [skip_key, "../AdvanceKey"]]:
		var other := NodePath(pair[1])
		for side in ["focus_neighbor_left", "focus_neighbor_right", "focus_next", "focus_previous"]:
			pair[0].set(side, other)
		pair[0].focus_neighbor_top = NodePath(".")
		pair[0].focus_neighbor_bottom = NodePath(".")
	hide()

func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	if enabled:
		_stop_fades()
	atmosphere.material.set_shader_parameter("motion", 0.0 if enabled else 1.0)

func play(scene: Dictionary, scene_texture: Texture2D, portraits: Callable) -> void:
	_stop_fades()
	scene_id = str(scene["id"])
	lines = scene["lines"]
	line_index = 0
	portrait_for = portraits
	background.texture = scene_texture
	show()
	_show_line()
	advance_key.grab_focus()
	# Cosmetic only: keys read on at once even while the scene fades in.
	_fade(self, SCENE_FADE)

func set_touch_mode(enabled: bool) -> void:
	# Fingers tap the keys or the scene itself; keyboard hints are for desktops.
	touch_mode = enabled
	skip_key.text = "건너뛰기" if enabled else "건너뛰기 [Esc]"
	advance_key.tooltip_text = "다음 줄을 읽습니다. 화면 어디를 눌러도 됩니다." if enabled else "다음 줄을 읽습니다. Space · Enter · 클릭"
	if is_playing():
		_show_line()

func stop() -> void:
	_stop_fades()
	scene_id = ""
	lines = []
	line_index = 0
	hide()

func is_playing() -> bool:
	return visible and not scene_id.is_empty()

func advance() -> void:
	if not is_playing():
		return
	if line_index + 1 < lines.size():
		line_index += 1
		_show_line()
		advanced.emit()
	else:
		skipped.emit()

func skip() -> void:
	if is_playing():
		skipped.emit()

func _show_line() -> void:
	var line: Dictionary = lines[line_index]
	var speaker := str(line["speaker"])
	text.text = UiTheme.keep_words(str(line["text"]))
	text.visible_ratio = 1.0
	name_plate.text = speaker
	name_plate.visible = not speaker.is_empty()
	line_kind.text = KIND_TEXT.get(str(line["kind"]), "")
	var texture: Texture2D = portrait_for.call(speaker, str(line.get("expression", ""))) if not speaker.is_empty() else null
	var arrives: bool = texture != null and line_index > 0 and speaker != str(lines[line_index - 1]["speaker"])
	portrait.texture = texture
	portrait_frame.visible = texture != null
	if arrives:
		_fade(portrait_frame, PORTRAIT_FADE)
	var key := "" if touch_mode else " [Space]"
	advance_key.text = ("다음" if line_index + 1 < lines.size() else "닫기") + key

func _fade(item: CanvasItem, seconds: float) -> void:
	item.modulate.a = 1.0
	if reduce_motion:
		return
	item.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(item, "modulate:a", 1.0, seconds)
	_fades.append(tween)
	if item == portrait_frame:
		# A quick second speaker change restarts the portrait fade cleanly.
		if _portrait_fade != null and _portrait_fade.is_valid():
			_portrait_fade.kill()
		_portrait_fade = tween

func _stop_fades() -> void:
	# A skipped or replaced scene leaves no fade running and nothing half-faded.
	for tween in _fades:
		if tween.is_valid():
			tween.kill()
	_fades.clear()
	modulate.a = 1.0
	if portrait_frame != null:
		portrait_frame.modulate.a = 1.0

func _gui_input(event: InputEvent) -> void:
	# A click anywhere on the scene reads on, like the advance key.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()
