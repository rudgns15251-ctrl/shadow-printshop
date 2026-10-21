extends "res://scripts/slice_main.gd"
## Campaign adapter: retain the slice renderer, controls, rules, settings and audio.
## Override lifecycle, progress I/O, archive callbacks and chapter-specific copy.
## Coordinator owns Godot QA/export; narrative and presentation need human review.
const CampaignState = preload("res://scripts/campaign_state.gd")
const CampaignSave = preload("res://scripts/campaign_save.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const StoryStage = preload("res://scripts/story_stage.gd")
const NIGHT_SCENE = preload("res://assets/art/scene_shop_night.svg")
const ATMOSPHERE = preload("res://shaders/atmosphere.gdshader")

var atmosphere: ColorRect
var title_backdrop: TextureRect
var document_panel_style: StyleBox

var campaign_save = CampaignSave.new()
var story_button: Button
var order_cue: Label
var order_card: Button
var story_stage: Control
var story_after := Callable()
var ending_scene_key: Button
var workbench_panel: Control
var dialog_hint: Label
var rotate_keys: Array = []
var hint_key: Button
var touch_mode := false
var reset_key: Button
var touch_bar: HBoxContainer
var touch_top: HBoxContainer
var touch_menu_key: Button
var _touch_homes: Array = []
const TOUCH_KEY := 84.0
var touch_backing: PanelContainer
var touch_titles: VBoxContainer
var _safe_side := 0
var _fit_passes := 0
static var _scene_rows: Array = []
var workbench_scroll: ScrollContainer
var ending_panel: Control
var environment_audio: AudioStreamPlayer
var environment_audio_exiting := false

func _ready() -> void:
	# project.godot names the product 음영 인쇄소 and pins user:// to the legacy
	# Godot/app_userdata/C01 - Shadow Printshop Slice directory, so saves stay put.
	get_window().title = "음영 인쇄소"
	print("CAMPAIGN_AUDIO_DRIVER ", AudioServer.get_driver_name())
	# Android Back must reach _go_back instead of closing the app.
	get_tree().set_quit_on_go_back(false)
	touch_mode = OS.has_feature("mobile")
	super._ready()
	set_touch_mode(touch_mode)

func get_environment_audio() -> AudioStreamPlayer:
	return environment_audio

func _build_audio() -> void:
	# Retain the inherited three-player SFX dictionary and its lifecycle. The
	# paper and chapter cues join that dictionary, so the inherited volume, mute
	# and exit cleanup own them too.
	super._build_audio()
	for key in ["paper", "chapter"]:
		var cue := AudioStreamPlayer.new()
		cue.name = {"paper": "PaperSfx", "chapter": "ChapterSfx"}[key]
		cue.stream = load({"paper": "res://assets/audio/menu_paper.wav", "chapter": "res://assets/audio/chapter_transition.wav"}[key])
		add_child(cue)
		audio[key] = cue
	var ambience: AudioStreamWAV = load("res://assets/audio/shop_ambience.wav").duplicate()
	ambience.loop_begin = 0
	ambience.loop_end = int(round(ambience.get_length() * ambience.mix_rate))
	ambience.loop_mode = AudioStreamWAV.LOOP_FORWARD
	environment_audio = AudioStreamPlayer.new()
	environment_audio.name = "ShopAmbience"
	environment_audio.stream = ambience
	add_child(environment_audio)
	_update_audio()

func _update_audio() -> void:
	super._update_audio()
	# The inherited builder updates SFX before this separate player exists.
	if environment_audio_exiting or not is_instance_valid(environment_audio):
		return
	if environment_audio.stream == null or not is_inside_tree():
		return
	var gain: float = 0.0 if bool(settings["mute"]) or not game_active else float(settings["master"]) * float(settings["bgm"])
	if gain <= 0.0:
		environment_audio.stop()
		environment_audio.volume_db = -80.0
	else:
		environment_audio.volume_db = linear_to_db(gain)
		if not environment_audio.playing:
			environment_audio.play()

func _exit_tree() -> void:
	environment_audio_exiting = true
	if is_instance_valid(environment_audio):
		environment_audio.stop()
		environment_audio.stream = null
	environment_audio = null
	super._exit_tree()

# The displayed puzzle is this inherited Control, with one authoritative state.
# Getters also keep the contract true after inherited callbacks replace state.
var session:
	get:
		return state
var puzzle_view: Control:
	get:
		return self

func _init() -> void:
	state = CampaignState.new()
	_reset_campaign_hints()
	# All campaign reading lives in session, never in the legacy archive writer.
	story_journal = null

func _reset_campaign_hints() -> void:
	hint_levels = []
	hint_levels.resize(session.puzzle_count())
	hint_levels.fill(0)

## Every inherited panel and button is built through these two hooks, so the
## campaign gets the shared paper/key look while the legacy slice keeps its own.
func _panel_style(color: Color, radius: int = 10, vertical_padding: int = 12) -> StyleBoxFlat:
	var style := UiTheme.surface(color, radius, vertical_padding)
	if color.get_luminance() < 0.2:
		# Ink-filled pieces (current progress chip, selection strip) keep an edge
		# against the dark room.
		style.border_color = Color(UiTheme.LAMP, 0.6)
	return style

func _style_button(item: Button, primary: bool = false) -> void:
	super._style_button(item, primary)
	var face: Color = ACCENT if primary else PAPER
	item.add_theme_stylebox_override("normal", UiTheme.key(face, INK))
	item.add_theme_stylebox_override("hover", UiTheme.key(Color("#6f301c") if primary else Color("#efe1cf"), INK))
	item.add_theme_stylebox_override("pressed", UiTheme.key(INK if primary else ACCENT, INK, true))
	item.add_theme_stylebox_override("hover_pressed", UiTheme.key(INK if primary else ACCENT, INK, true))
	item.add_theme_stylebox_override("disabled", UiTheme.key(Color("#ddd4c6"), Color("#9c917f"), true))

func _build_interface() -> void:
	super._build_interface()
	UiTheme.apply(theme)
	title_area.get_child(0).text = "음영 인쇄소"
	UiTheme.title_font(title_area.get_child(0))
	UiTheme.title_font(heading)
	story_button = _button(next_button.get_parent(), "이야기", _open_story, 100)
	order_cue = _label(heading.get_parent(), "", 15)
	order_cue.name = "CurrentOrderCue"
	heading.get_parent().move_child(order_cue, 1)
	# A nonmodal ending keeps Undo/Reset available. Use the existing scrolling
	# content and typography so long text remains reachable at every font size.
	var panel := PanelContainer.new()
	panel.name = "CampaignEnding"
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL))
	var content: Node = heading.get_parent().get_parent()
	content.add_child(panel)
	content.move_child(panel, 1)
	ending_panel = panel
	var column := _column(panel, 8)
	UiTheme.title_font(_label(column, "의뢰 18건 완료 · 아침의 서명", 21, GREEN))
	_button(column, "크레딧", show_credits, 130)
	_button(column, "처음부터 다시 하기", _ask_campaign_replay, 130)
	UiTheme.document_font(_label(column, UiTheme.keep_words(str(CampaignState.story_data()["events"]["C03_ENDING"]["text"])), 17))
	ending_panel.hide()
	_apply_player_labels()
	_build_workbench()
	# Last: every label the night scene recolours now exists.
	_build_night_scene()
	_build_title_backdrop()
	story_stage = StoryStage.new()
	story_stage.build(self)
	overlay.add_child(story_stage)
	story_stage.set_reduce_motion(bool(settings["reduce_motion"]))
	story_stage.advanced.connect(_play_sound.bind("paper"))
	story_stage.skipped.connect(_end_scene)
	ending_scene_key = _button(ending_panel.get_child(0), "결말 장면 보기", func(): play_scene(_scene_for("ending"), Callable(self, "_focus_ending_scene_key")), 130)
	ending_scene_key.tooltip_text = "마지막 장면을 다시 봅니다. 진행은 바뀌지 않습니다."
	_primary_button(ending_scene_key)
	_arrange_ending()
	_build_dialog_hint()

static func scene_rows() -> Array:
	if _scene_rows.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_scenes.json"))
		_scene_rows = parsed["scenes"] if parsed is Dictionary and parsed.get("scenes") is Array else []
	return _scene_rows

func _scene(id: String) -> Dictionary:
	for scene in scene_rows():
		if str(scene["id"]) == id:
			return scene
	return {}

func _scene_for(type: String, value: Variant = null) -> String:
	for scene in scene_rows():
		var trigger: Dictionary = scene["trigger"]
		# JSON numbers are floats; chapters compare as whole numbers.
		var key: Variant = trigger.get("puzzle_id", int(trigger.get("chapter", 0)))
		if str(trigger["type"]) == type and (value == null or str(key) == str(value)):
			return str(scene["id"])
	return ""

# The night passes by colour temperature: night, after midnight, dawn; the
# ledger close-up is for document scenes.
const SCENE_PLATES := {"night": NIGHT_SCENE, "midnight": preload("res://assets/art/scene_midnight.svg"),
	"dawn": preload("res://assets/art/scene_dawn.svg"), "ledger": preload("res://assets/art/scene_ledger.svg")}
const CHAPTER_PLATES := {1: "night", 2: "midnight", 3: "dawn"}

func _scene_background(scene_row: Dictionary) -> Texture2D:
	return SCENE_PLATES.get(str(scene_row.get("background", "night")), NIGHT_SCENE)

# Scenes use expression busts; order documents keep their framed record portraits.
const EXPRESSION_PORTRAITS := {
	"백인호": {"neutral": preload("res://assets/art/portrait_baek_neutral.svg"),
		"worried": preload("res://assets/art/portrait_baek_worried.svg"),
		"resolved": preload("res://assets/art/portrait_baek_resolved.svg")},
	"윤해린": {"record": preload("res://assets/art/portrait_yoon_record.svg"),
		"restored": preload("res://assets/art/portrait_yoon_restored.svg")},
	"0번 의뢰인": {"sealed": preload("res://assets/art/portrait_client_sealed.svg"),
		"signed": preload("res://assets/art/portrait_client_signed.svg")},
}

func _scene_portrait(speaker: String, expression: String) -> Texture2D:
	return EXPRESSION_PORTRAITS.get(speaker, {}).get(expression, PORTRAITS.get(speaker))

func play_scene(id: String, then: Callable = Callable()) -> void:
	# Over an open dialog (a chapter record) the scene plays first and the dialog
	# waits beneath it; otherwise the scene is its own modal reading.
	var scene := _scene(id)
	if scene.is_empty():
		if then.is_valid():
			then.call()
		return
	_cancel_presentation_motion()
	if not overlay.visible or dialog.get_child_count() == 0:
		_clear_dialog()
		overlay.show()
	popup_panel.hide()
	story_after = then
	story_stage.atmosphere.material.set_shader_parameter("tube", 1.0 if str(scene.get("background", "night")) == "night" else 0.0)
	story_stage.play(scene, _scene_background(scene), _scene_portrait)

func _end_scene() -> void:
	story_stage.stop()
	popup_panel.show()
	var then := story_after
	story_after = Callable()
	if dialog.get_child_count() > 0:
		# The waiting record takes focus at its first action and first line.
		_confine_journal_focus()
		_scroll_dialog_to_top()
	else:
		dismiss_story()
	if then.is_valid():
		then.call()

func _scene_unlocked(source, scene: Dictionary) -> bool:
	var trigger: Dictionary = scene["trigger"]
	var reached: int = int(source.snapshot()["puzzle"])
	match str(trigger["type"]):
		"opening":
			return true
		"ending":
			return source.is_finished()
		"chapter":
			for index in range(source.puzzle_count()):
				if int(source.puzzle_data()[index]["chapter"]) == int(trigger["chapter"]):
					return reached >= index
		"enter":
			for index in range(source.puzzle_count()):
				if str(source.puzzle_data()[index]["id"]) == str(trigger["puzzle_id"]):
					return reached >= index
	return false

func _begin_campaign() -> void:
	start_new()
	play_scene(_scene_for("opening"))

func _build_title_backdrop() -> void:
	# The start screen alone shows the night shop behind its menu, inside the
	# existing overlay so it blocks input exactly like every other dialog.
	title_backdrop = TextureRect.new()
	title_backdrop.name = "TitleBackdrop"
	title_backdrop.texture = NIGHT_SCENE
	title_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	title_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_backdrop.focus_mode = Control.FOCUS_NONE
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.SHADOW, 0.38)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_backdrop.add_child(shade)
	overlay.add_child(title_backdrop)
	overlay.move_child(title_backdrop, 0)
	title_backdrop.hide()
	document_panel_style = popup_panel.get_theme_stylebox("panel")

func _set_title_look(enabled: bool) -> void:
	if title_backdrop == null or popup_panel == null:
		return
	title_backdrop.visible = enabled
	if not enabled:
		popup_panel.add_theme_stylebox_override("panel", document_panel_style)
		return
	var style := UiTheme.surface(Color(UiTheme.NIGHT, 0.88), 14, 20)
	style.border_color = Color(UiTheme.LAMP, 0.55)
	style.set_content_margin_all(22)
	popup_panel.add_theme_stylebox_override("panel", style)
	var title_label: Label = dialog.get_child(0)
	title_label.text = "음영 인쇄소"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_meta("font_base", 48)
	title_label.add_theme_font_size_override("font_size", int(round(48 * float(settings["font_scale"]))))
	title_label.add_theme_color_override("font_color", UiTheme.LAMP)
	UiTheme.title_font(title_label)
	_room_outline(title_label)
	var subtitle := _label(dialog, "1998년 11월 17일 밤", 19, UiTheme.PAPER)
	subtitle.name = "TitleSubtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.document_font(subtitle)
	dialog.move_child(subtitle, 1)
	var body: Label = dialog.get_child(2)
	# How to play lives in 도움말; the title keeps one short line.
	body.text = "세 장, 의뢰 18건, 하나의 결말"
	body.add_theme_color_override("font_color", Color(UiTheme.PAPER, 0.86))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The start actions become a centred menu column of equal-width keys.
	var menu: VBoxContainer = dialog.get_child(dialog.get_child_count() - 1)
	menu.name = "TitleMenu"
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.custom_minimum_size.x = 380
	# 처음부터 and 이어하기 stay full-width; the other actions share a two-column
	# grid inside the same column, so tree order (and focus wrapping) is unchanged.
	var keys: Array = menu.get_children()
	var grid := GridContainer.new()
	grid.name = "TitleMenuGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	menu.add_child(grid)
	for index in range(keys.size()):
		var button: Button = keys[index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("focus", _title_focus_style())
		if (index >= 2 or touch_mode) and (touch_mode or index < keys.size() - 1):
			button.reparent(grid)
	# 종료 keeps its own full-width row instead of sitting alone in the grid.
	if not touch_mode:
		menu.move_child(keys[keys.size() - 1], menu.get_child_count() - 1)
	_fit_dialog.call_deferred()

func _title_focus_style() -> StyleBoxFlat:
	# The inherited dark-blue ring vanishes on the night panel; use lamp light.
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = UiTheme.LAMP
	style.set_border_width_all(3)
	style.set_expand_margin_all(3)
	style.set_corner_radius_all(8)
	return style

func _update_responsive() -> void:
	super._update_responsive()
	if boards_grid != null:
		boards_grid.columns = 3 if size.x >= 1100.0 else 2
	# Sheets shrink only as far as the larger text needs; digits keep their size.
	var edge: float = 156.0 if float(settings["font_scale"]) <= 1.0 else (136.0 if float(settings["font_scale"]) <= 1.25 else 112.0)
	if touch_mode:
		# The bench is gone on phones: the sheets take the room it left.
		edge = 220.0 if float(settings["font_scale"]) <= 1.0 else (196.0 if float(settings["font_scale"]) <= 1.25 else 150.0)
	for view in [before_view, after_view, target_view]:
		if view != null:
			view.custom_minimum_size = Vector2(edge, edge)
	if touch_mode and title_navigation != null:
		# A rotation can move the notch: read the display again.
		apply_safe_area(_display_safe_area())
		# Measured after layout, over a few frames (growth only, so it settles).
		_fit_passes = 4
		if is_inside_tree() and not get_tree().process_frame.is_connected(_fit_touch_sheets):
			get_tree().process_frame.connect(_fit_touch_sheets)

func _fit_touch_sheets() -> void:
	# Grow the three sheets until the empty desk above the touch bar is a small
	# gap, never wider than the row allows and never pushing the bar away.
	_fit_passes -= 1
	var grown := false
	var scroll: Control = find_child("WorkbenchScroll", true, false)
	if touch_mode and touch_bar != null and touch_bar.is_visible_in_tree() and boards_grid != null and after_view != null and scroll != null:
		var edge: float = after_view.custom_minimum_size.x
		# Everything in the workbench (sheets, captions, legend) must still fit unscrolled.
		var band: float = scroll.size.y - scroll.get_child(0).get_combined_minimum_size().y - 8.0
		var columns: int = maxi(1, boards_grid.columns)
		var gap: float = float(boards_grid.get_theme_constant("h_separation"))
		var chrome: float = (boards_grid.get_combined_minimum_size().x - gap * (columns - 1)) / columns - edge
		# The window, not the scroll (whose width follows its content), bounds the row.
		var padding: float = scroll.get_combined_minimum_size().x - boards_grid.get_combined_minimum_size().x
		var room: float = size.x - 32.0 - 2.0 * _safe_side - maxf(0.0, padding) - 4.0
		var widest: float = (room - gap * (columns - 1)) / columns - chrome
		var target: float = floorf(clampf(edge + band, edge, widest))
		if target > edge + 0.5:
			grown = true
			for view in [before_view, after_view, target_view]:
				view.custom_minimum_size = Vector2(target, target)
	if _fit_passes <= 0 or (not grown and _fit_passes < 3):
		get_tree().process_frame.disconnect(_fit_touch_sheets)

func _update_header_layout() -> void:
	# One arrangement per window width, never per text length, so the header
	# does not jump between orders.
	if title_navigation != null:
		title_navigation.vertical = size.x < 1000.0

func _style_chips(data: Dictionary) -> void:
	# Status chips, not keys: flat outlines, the current one filled.
	for i in range(progress_indicators.size()):
		var current: bool = i == int(data["puzzle"])
		var chip := StyleBoxFlat.new()
		chip.set_corner_radius_all(4)
		chip.set_border_width_all(1)
		chip.set_content_margin_all(5)
		chip.content_margin_top = 1
		chip.content_margin_bottom = 1
		if current:
			chip.bg_color = GREEN if bool(data["solved"]) else INK
			chip.border_color = UiTheme.LAMP
		else:
			chip.bg_color = Color(UiTheme.PAPER, 0.14 if i < int(data["puzzle"]) else 0.0)
			chip.border_color = Color(UiTheme.PAPER, 0.45)
		progress_indicators[i].add_theme_stylebox_override("panel", chip)
		progress_captions[i].add_theme_color_override("font_color", UiTheme.PAPER)

func _arrange_ending() -> void:
	# The ending reads first; its keys share one row under the text.
	var column: VBoxContainer = ending_panel.get_child(0)
	var keys := HBoxContainer.new()
	keys.name = "EndingKeys"
	keys.add_theme_constant_override("separation", 8)
	var buttons: Array = column.get_children().filter(func(node): return node is Button)
	var text: Label = column.get_children().filter(func(node): return node is Label).back()
	column.add_child(keys)
	for key in buttons:
		key.reparent(keys)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.move_child(ending_scene_key, 0)
	column.move_child(text, 1)

func _focus_ending_scene_key() -> void:
	if ending_scene_key != null and ending_scene_key.is_visible_in_tree():
		ending_scene_key.grab_focus()

func _open_story_at(title: String) -> void:
	# Returning from a replayed scene puts focus back on that scene's entry.
	_open_story()
	for node in dialog.find_children("*", "Button", true, false):
		if node.text == "장면 · " + title:
			node.grab_focus()
			# After the dialog's own deferred scroll-to-top, bring the entry into view.
			popup_scroll.call_deferred("ensure_control_visible", node)
			break

func _build_dialog_hint() -> void:
	# Long documents say how to read on and leave, outside the scrolling text.
	var frame := VBoxContainer.new()
	frame.name = "DialogFrame"
	popup_panel.add_child(frame)
	popup_scroll.reparent(frame)
	dialog_hint = _label(frame, "", 14, GREEN)
	dialog_hint.name = "DialogHint"
	dialog_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dialog_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	dialog_hint.hide()

func _fit_dialog() -> void:
	super._fit_dialog()
	if dialog_hint != null and popup_scroll != null and is_inside_tree():
		var overflow: bool = dialog.get_combined_minimum_size().y > size.y - 96.0 and not (title_backdrop != null and title_backdrop.visible)
		if touch_mode:
			dialog_hint.text = "↓ 밀어서 더 읽기"
		else:
			dialog_hint.text = "↓ 더 읽기 [PageDown]  ·  닫기 [Esc]" if dialog_back.is_valid() else "↓ 더 읽기 [PageDown]"
		dialog_hint.visible = overflow
		if overflow:
			popup_scroll.custom_minimum_size.y = maxf(120.0, size.y - 96.0 - dialog_hint.get_combined_minimum_size().y - 4.0)
	if title_backdrop != null and title_backdrop.visible and popup_panel != null:
		# A narrower title panel leaves more of the night workshop visible.
		popup_panel.custom_minimum_size.x = minf(560.0, size.x - 64.0 - 2.0 * _safe_side)

const PORTRAITS := {"백인호": preload("res://assets/art/portrait_baek_neutral.svg"),
	"윤해린": preload("res://assets/art/portrait_yoon_record.svg"), "0번 의뢰인": preload("res://assets/art/portrait_client_sealed.svg")}

func _build_workbench() -> void:
	# The puzzle as a desk: paper sheets lie on a dark Workbench, the stamp and its
	# keys on a wood StampBench, and the current order is a card pinned beside the
	# heading. Nodes are only regrouped; every member keeps its behaviour.
	var header: VBoxContainer = heading.get_parent()
	var content: VBoxContainer = header.get_parent()
	workbench_scroll = content.get_parent()
	workbench_scroll.name = "WorkbenchScroll"
	# Header: the order card replaces the order line; the print count joins the
	# heading line so the progress chips keep a full row.
	# The header lies on a dark backing so it reads over every room plate.
	var backing := PanelContainer.new()
	backing.name = "HeaderBacking"
	var night := UiTheme.surface(Color(UiTheme.NIGHT, 0.84), 10, 4)
	night.border_color = Color(UiTheme.LAMP, 0.22)
	backing.add_theme_stylebox_override("panel", night)
	content.add_child(backing)
	content.move_child(backing, header.get_index())
	var top := HBoxContainer.new()
	top.name = "DeskHeader"
	top.add_theme_constant_override("separation", 12)
	backing.add_child(top)
	header.reparent(top)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order_cue.hide()
	var title_line := _row(header, 16)
	header.move_child(title_line, 0)
	heading.reparent(title_line)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# One line that never breaks inside a word; a too-long title ends in an ellipsis.
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.clip_text = true
	# Compact chips keep all eighteen on one row at every text size.
	var progression: Control = progress_captions[0].get_parent().get_parent()
	progression.add_theme_constant_override("h_separation", 6)
	for caption in progress_captions:
		caption.set_meta("font_base", 13)
		caption.add_theme_font_size_override("font_size", int(round(13 * float(settings["font_scale"]))))
	order_card = _button(top, "", _open_order, 250)
	order_card.name = "OrderCard"
	order_card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	order_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	order_card.add_theme_constant_override("icon_max_width", 40)
	order_card.add_theme_constant_override("h_separation", 10)
	order_card.tooltip_text = "지금 의뢰의 의뢰서를 엽니다. 읽어도 진행은 바뀌지 않습니다."
	# Workbench: the three sheets and their legend on the dark bench.
	var bench := PanelContainer.new()
	bench.name = "Workbench"
	var bench_style := UiTheme.surface(Color("#2a211b", 0.86), 10, 8)
	bench_style.border_color = Color(UiTheme.LAMP, 0.28)
	bench.add_theme_stylebox_override("panel", bench_style)
	workbench_panel = bench
	content.add_child(bench)
	content.move_child(bench, boards_grid.get_index())
	var sheets := _column(bench, 4)
	var note: Label = content.get_child(boards_grid.get_index() + 1)
	boards_grid.reparent(sheets)
	note.reparent(sheets)
	note.add_theme_color_override("font_color", UiTheme.PAPER)
	_room_outline(note)
	note.set_meta("font_base", 13)
	note.add_theme_font_size_override("font_size", int(round(13 * float(settings["font_scale"]))))
	bench_style.content_margin_top = 4
	bench_style.content_margin_bottom = 4
	for view in [before_view, after_view, target_view]:
		var caption: Label = view.get_parent().get_child(view.get_parent().get_child_count() - 1)
		caption.set_meta("font_base", 14)
		caption.add_theme_font_size_override("font_size", int(round(14 * float(settings["font_scale"]))))
	for item in stamp_buttons[0].get_parent().get_children():
		if item is Button and (str(item.text).contains("[Q]") or str(item.text).contains("[E]")):
			rotate_keys.append(item)
	# StampBench: the inherited control panel becomes a wood bench; save and hint
	# keys move to their own column so the print row stays above the fold.
	var stamp_bench: PanelContainer = stamp_view.get_parent().get_parent().get_parent()
	stamp_bench.name = "StampBench"
	var wood := UiTheme.surface(UiTheme.WOOD, 10, 6)
	wood.border_color = Color("#6b4a30")
	wood.set_border_width_all(2)
	stamp_bench.add_theme_stylebox_override("panel", wood)
	var controls: HBoxContainer = stamp_view.get_parent().get_parent()
	var tools := _column(controls, 6)
	tools.name = "BenchTools"
	tools.custom_minimum_size.x = 150
	var extras: Control = hint_label.get_parent().get_child(hint_label.get_index() - 1)
	extras.reparent(tools)
	for key in extras.get_children():
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.reparent(tools)
	# The print count sits with the selection strip, where the player acts.
	var selection: Control = detail.get_parent()
	var strip := HBoxContainer.new()
	strip.name = "SelectionStrip"
	strip.add_theme_constant_override("separation", 12)
	selection.get_parent().add_child(strip)
	selection.get_parent().move_child(strip, selection.get_index())
	selection.reparent(strip)
	selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_label.reparent(strip)
	progress_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	progress_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_label.add_theme_color_override("font_color", UiTheme.INK)
	# The strip and the footer already say what to do; the step captions only
	# cost height at larger text. Bench text is ink on wood for contrast.
	for node in stamp_bench.find_children("*", "Label", true, false):
		if node.text in ["도장 고르기", "미리보기를 견본과 비교하고 찍기"]:
			node.hide()
	reaction_label.add_theme_color_override("font_color", UiTheme.INK)
	# The stamp art needs no caption, and the hint state rides on the hint key, so
	# the bench ends with the print row instead of half-cut status lines.
	for node in stamp_bench.find_children("*", "Label", true, false):
		if node.text == "목판":
			node.hide()
	hint_label.hide()
	for node in tools.find_children("*", "Button", true, false):
		if str(node.text) == "힌트":
			hint_key = node
	stamp_view.custom_minimum_size = Vector2(124, 100)
	# A smaller play-screen title leaves room for the work.
	var title_label: Label = title_area.get_child(0)
	title_label.set_meta("font_base", 24)
	title_label.add_theme_font_size_override("font_size", int(round(24 * float(settings["font_scale"]))))

const BOARD_NAMES := [["지금 종이", "지금 인쇄된 종이"], ["찍으면 · 미리보기", "인쇄 횟수에 포함되지 않아요"], ["견본", "이 모양과 같게 찍으세요"]]
const CAPTIONS := {"Q · ↶ 90°": "↶ 왼쪽으로 [Q]", "E · ↷ 90°": "↷ 오른쪽으로 [E]", "R · 초기화": "초기화 [R]",
	"1  도장 선택 · 회전": "도장 고르기", "2  미리보기 확인 · 인쇄": "미리보기를 견본과 비교하고 찍기",
	"목판 / STAMP": "목판", "1 = 반전할 칸": "1 = 뒤집힐 칸"}

func _apply_player_labels() -> void:
	# Campaign only: player-facing Korean with the shortcut as a bracketed hint.
	# The legacy prototype scene (protected tests) keeps its original captions.
	for index in range(3):
		var view: Control = [before_view, after_view, target_view][index]
		var card: Node = view.get_parent()
		card.get_child(0).get_child(0).text = BOARD_NAMES[index][0]
		card.get_child(card.get_child_count() - 1).text = BOARD_NAMES[index][1]
	print_button.text = "인쇄 [Space]"
	undo_button.text = "되돌리기 [U]"
	next_button.text = "다음 의뢰 [N]"
	for node in find_children("*", "Button", true, false):
		if node.text == "R · 초기화":
			reset_key = node
	var stack: Array = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if (node is Label or node is Button) and CAPTIONS.has(node.text):
			node.text = CAPTIONS[node.text]
		stack.append_array(node.get_children())

func _stamp_name(index: int) -> String:
	return "꺾임" if index == 0 else "막대"

func _player_terms(text: String) -> String:
	# The authored hint data predates the player-facing names; translate at display
	# time only so the story data keeps its original text.
	for pair in [["TARGET", "견본"], ["CURRENT", "지금 종이"], ["AFTER", "미리보기"]]:
		text = text.replace(pair[0], pair[1])
	var stamp := RegEx.create_from_string("(?<![A-Za-z])([AB])(?![A-Za-z])(와|는|를|가)?")
	var particles := {"": "", "와": "과", "는": "은", "를": "을", "가": "이"}
	var out := ""
	var at := 0
	for found in stamp.search_all(text):
		out += text.substr(at, found.get_start() - at)
		out += _stamp_name(0 if found.get_string(1) == "A" else 1) + " 도장" + particles[found.get_string(2)]
		at = found.get_end()
	return out + text.substr(at)

func _select(index: int) -> void:
	if not game_active or overlay.visible:
		return
	if session.select_mask(index):
		_refresh()
		_selection_feedback("%s 도장 선택" % _stamp_name(index))

func _react(kind: String = "print") -> void:
	super._react(kind)
	if kind == "solve":
		reaction_label.text = "✓ 견본 일치"

func _build_night_scene() -> void:
	# The inherited daylight backdrop becomes the night workshop; an atmosphere
	# layer sits between it and the UI. Neither takes input.
	var scene: TextureRect = get_node("ShopBackground")
	scene.name = "NightScene"
	scene.texture = NIGHT_SCENE
	atmosphere = ColorRect.new()
	atmosphere.name = "Atmosphere"
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atmosphere.focus_mode = Control.FOCUS_NONE
	var material := ShaderMaterial.new()
	material.shader = ATMOSPHERE
	atmosphere.material = material
	add_child(atmosphere)
	move_child(atmosphere, scene.get_index() + 1)
	_update_atmosphere()
	# Text that sits directly on the dark room is lit by the lamp; everything on
	# paper or wood panels keeps its ink colour.
	var on_room: Array = [subheading, order_cue]
	for child in heading.get_parent().get_parent().get_children():
		if child is Label:
			on_room.append(child)
	for label in [title_area.get_child(0), heading]:
		label.add_theme_color_override("font_color", UiTheme.LAMP)
		_room_outline(label)
	for label in on_room:
		label.add_theme_color_override("font_color", UiTheme.PAPER)
		_room_outline(label)

func _room_outline(label: Label) -> void:
	# A carved dark edge keeps room text readable over any part of the scene,
	# including the lamp glow and the lit bench at 125/150% font sizes.
	label.add_theme_color_override("font_outline_color", Color(UiTheme.SHADOW, 0.92))
	label.add_theme_constant_override("outline_size", 7)

func _update_atmosphere() -> void:
	if atmosphere != null:
		atmosphere.material.set_shader_parameter("motion", 0.0 if bool(settings["reduce_motion"]) else 1.0)
	if story_stage != null:
		story_stage.set_reduce_motion(bool(settings["reduce_motion"]))

func _setting_value_changed(value: Variant, key: String) -> void:
	super._setting_value_changed(value, key)
	if key == "reduce_motion":
		_update_atmosphere()

func start_new() -> void:
	# Direct public entry is immediately playable; intro is available in 이야기.
	dismiss_story()
	state = CampaignState.new()
	_reset_campaign_hints()
	game_active = true
	_update_audio()
	last_save_message = ""
	_autosave()
	if heading != null:
		_refresh()

func save_campaign() -> bool:
	return campaign_save.save(session, hint_levels)

func load_campaign() -> bool:
	# No published state, hints, focus or modal changes on failed validation.
	var restored: Dictionary = campaign_save.load_candidate()
	if restored.is_empty():
		return false
	# Publish into the existing object only after complete candidate validation.
	# References held by the puzzle view and other callers remain authoritative.
	if not session.import_progress(restored["session"].export_progress()):
		return false
	hint_levels = restored["hints"].duplicate()
	game_active = true
	_update_audio()
	last_save_message = "진행 복원 완료"
	dismiss_story()
	if heading != null:
		_refresh()
	return true

func advance() -> void:
	# Keep explicit Next, solved checks, input gates and the available final boundary.
	var before: int = int(session.snapshot()["puzzle"])
	super._next()
	var after: int = int(session.snapshot()["puzzle"])
	if after != before and int(session.puzzle_data()[after]["chapter"]) != int(session.puzzle_data()[before]["chapter"]):
		var chapter := int(session.puzzle_data()[after]["chapter"])
		_show_chapter_transition(chapter)
		play_scene(_scene_for("chapter", chapter))
	elif after != before:
		play_scene(_scene_for("enter", session.puzzle_data()[after]["id"]))

func _show_chapter_transition(chapter_number: int) -> void:
	# The finished chapter's record and the new chapter's opening, read once at
	# the boundary the player chose to cross. Progress was already saved by Next;
	# reading and closing change nothing. Both remain replayable in 이야기.
	var outro_id: String = CampaignState.CHAPTERS[chapter_number - 2]["outro_event"]
	var intro_id: String = CampaignState.CHAPTERS[chapter_number - 1]["intro_event"]
	_show_dialog(CampaignState.CHAPTERS[chapter_number - 1]["title"], session.event_text(outro_id), [
		{"label": "작업 시작", "call": Callable(self, "_noop")},
	])
	UiTheme.document_font(dialog.get_child(1))
	# Two sections, record first: each event title is its own accent heading,
	# larger than the body text it introduces and kept above the buttons.
	var record_heading := _label(dialog, session.event_title(outro_id), 21, ACCENT)
	UiTheme.title_font(record_heading)
	dialog.move_child(record_heading, 1)
	var opening_heading := _label(dialog, session.event_title(intro_id), 21, ACCENT)
	UiTheme.title_font(opening_heading)
	var opening_body := _label(dialog, session.event_text(intro_id), 17)
	UiTheme.document_font(opening_body)
	dialog.move_child(opening_heading, dialog.get_child_count() - 3)
	dialog.move_child(opening_body, dialog.get_child_count() - 2)
	_play_sound("chapter")

func is_finished() -> bool:
	return session.is_finished()

func show_credits() -> void:
	# Public callers can open credits while an ending reading is still visible.
	if overlay != null and overlay.get_meta("campaign_event_id", "") == "C03_ENDING":
		_show_ending_credits()
		return
	_open_credits(Callable(self, "_noop"), "결말로 돌아가기")

func _show_ending_credits() -> void:
	# Dialog actions clear event metadata before dispatch, so bind the origin
	# explicitly instead of relying on metadata surviving dialog replacement.
	_open_credits(Callable(self, "_replay_event").bind("C03_ENDING"), "결말 기록으로 돌아가기")

const CREDITS_PAGE := "음영 인쇄소\n1998년 11월 17일 밤, 한 인쇄소의 야간 작업 기록\n\n게임 엔진 · Godot Engine 4 (Godot Engine 기여자들, MIT 라이선스)\n규칙 · 겹쳐 찍으면 뒤집히는 3×3 도장 인쇄\n글꼴 · 나눔고딕, 나눔명조 (SIL Open Font License 1.1)\n그림·글·소리 · 대부분 이 게임을 위해 AI 도구(OpenAI Codex, Anthropic Claude Code)로 새로 만든 원본입니다. 일부 기존 자산은 제작자가 확인되지 않았습니다. 파일별 출처와 허가, 사람의 권리 검토 대기 상태는 ‘자산 출처·라이선스’에서 볼 수 있습니다.\n\n세 장, 열여덟 의뢰의 기록을 읽어 주셔서 감사합니다."

func _open_credits(back: Callable, back_caption: String) -> void:
	if not is_finished() or not game_active:
		return
	_show_dialog("크레딧", CREDITS_PAGE, [
		{"label": back_caption, "call": back},
		{"label": "자산 출처·라이선스", "call": Callable(self, "_show_asset_licenses").bind(back, back_caption)},
		{"label": "엔진·글꼴 라이선스 전문", "call": Callable(self, "_show_credit_notices").bind(back, back_caption)},
	])

func _show_asset_licenses(back: Callable, back_caption: String) -> void:
	if not is_finished() or not game_active:
		return
	# The dialog renders plain text; drop Markdown heading markers from the file.
	var attribution := RegEx.create_from_string("(?m)^#{1,6}[ \\t]+").sub(FileAccess.get_file_as_string("res://CREDITS_KO.md"), "", true)
	_show_dialog("자산 출처·라이선스", attribution.strip_edges() + "\n\n" + _asset_license_text(FileAccess.get_file_as_string("res://ASSET_LICENSES.json")), [
		{"label": "크레딧으로 돌아가기", "call": Callable(self, "_open_credits").bind(back, back_caption)},
	])

func _asset_license_text(raw: String) -> String:
	# Attribution and permission fields only; synthesis/audit metadata stays in the
	# file. Unreadable data is reported plainly and nothing is filled in for it.
	var failure := "자산 대장(ASSET_LICENSES.json)을 읽을 수 없습니다. 기록이 없거나 형식이 올바르지 않아 자산의 출처와 허가를 표시하지 않습니다."
	var parser := JSON.new()
	if raw.strip_edges().is_empty() or parser.parse(raw) != OK or not parser.data is Array or parser.data.is_empty():
		return failure
	var sections: Array[String] = ["게임에 포함된 자산과 기록된 출처·허가입니다. NOASSERTION은 기록된 허가 없음을 뜻하며, 권리 상태는 사람의 검토가 필요합니다."]
	for row in parser.data:
		if not row is Dictionary or not row.has("path") or not row.has("license"):
			return failure
		var license := str(row["license"])
		var lines: Array[String] = [str(row["path"])]
		if row.has("dependency"):
			# The license belongs to the third-party dependency used at this path,
			# never to the project file itself.
			lines = ["대상: " + str(row["dependency"]), "사용 위치: " + str(row["path"])]
		lines.append("허가: " + license + (" (기록된 허가 없음)" if license == "NOASSERTION" else ""))
		for field in [["creator", "제작"], ["origin", "출처"], ["rights_evidence", "권리 기록"]]:
			if row.has(field[0]):
				lines.append(field[1] + ": " + str(row[field[0]]))
		if row.has("license_text"):
			lines.append("허가 원문:\n" + str(row["license_text"]))
		sections.append("\n".join(lines))
	return "\n\n".join(sections)

func _show_credit_notices(back: Callable, back_caption: String) -> void:
	if not is_finished() or not game_active:
		return
	_show_dialog("엔진·글꼴 라이선스 고지", _engine_credits(), [
		{"label": "크레딧으로 돌아가기", "call": Callable(self, "_open_credits").bind(back, back_caption)},
	])

func _engine_credits() -> String:
	# Read notices from the running engine, including its actual bundled fonts.
	var sections: Array[String] = [
		# The theme default is the UI face; headings carry a Myeongjo override.
		"실행 시 기본 글꼴: " + theme.default_font.get_font_name(),
		"제목·문서 글꼴: " + heading.get_theme_font("font").get_font_name(),
		"ThemeDB 대체 글꼴: " + ThemeDB.fallback_font.get_font_name(),
		"실행 엔진 · Godot Engine\n" + Engine.get_license_text(),
	]
	var notices: Array = Engine.get_copyright_info()
	var licenses: Dictionary = Engine.get_license_info()
	var shown: Array[String] = []
	for dependency in notices:
		if not str(dependency["name"]).to_lower().contains("font"):
			continue
		sections.append(str(dependency["name"]))
		for part in dependency["parts"]:
			sections.append("\n".join(part["copyright"]) + "\n" + "\n".join(part["files"]) + "\n" + str(part["license"]))
			var license_id := str(part["license"])
			if licenses.has(license_id) and not shown.has(license_id):
				shown.append(license_id)
				sections.append(str(licenses[license_id]))
	return "\n\n".join(sections)

func dismiss_story() -> void:
	if not is_inside_tree() or overlay == null:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	overlay.hide()
	_clear_dialog()
	if heading != null:
		_refresh()

func _disconnect_dialog_actions(node: Node) -> void:
	for signal_name in ["pressed", "toggled", "value_changed"]:
		if node.has_signal(signal_name):
			for connection in node.get_signal_connection_list(signal_name):
				node.disconnect(signal_name, connection["callable"])
	for child in node.get_children():
		_disconnect_dialog_actions(child)

func _clear_dialog() -> void:
	# Every other dialog, settings included, keeps the paper document look.
	_set_title_look(false)
	dialog_back = Callable()
	if overlay != null and overlay.has_meta("campaign_event_id"):
		overlay.remove_meta("campaign_event_id")
	if story_stage != null and story_stage.visible:
		story_stage.stop()
		story_after = Callable()
		popup_panel.show()
	if dialog != null:
		if is_inside_tree():
			var focus: Control = get_viewport().gui_get_focus_owner()
			if focus != null and dialog.is_ancestor_of(focus):
				focus.release_focus()
		_disconnect_dialog_actions(dialog)
		super._clear_dialog()

func _cancel_presentation_motion() -> void:
	# Modals block input; a print/undo flourish must not keep animating behind them.
	_finish_reaction()
	_clear_impression()

func _show_dialog(title: String, message: String, options: Array) -> void:
	_cancel_presentation_motion()
	super._show_dialog(title, message, options)
	UiTheme.title_font(dialog.get_child(0))
	var buttons: Node = dialog.get_child(dialog.get_child_count() - 1)
	for index in range(options.size()):
		var button: Button = buttons.get_child(index)
		button.disabled = bool(options[index].get("disabled", false))
		button.tooltip_text = str(options[index].get("tooltip", ""))
	_confine_journal_focus()
	_scroll_dialog_to_top()
	if touch_mode:
		_strip_key_hints(dialog)
		_touch_controls(dialog)

func _touch_controls(node: Node) -> void:
	for child in node.get_children():
		if child is CheckBox or child is Slider:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, 64.0)
		elif child is Button:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, TOUCH_KEY)
			child.custom_minimum_size.x = maxf(child.custom_minimum_size.x, 140.0)
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_touch_controls(child)

func _scroll_dialog_to_top() -> void:
	# Every dialog opens at its first line, even after paging a previous one;
	# the deferred reset follows any focus-follow scroll queued this frame.
	popup_scroll.scroll_vertical = 0
	popup_scroll.set_deferred("scroll_vertical", 0)

func _input(event: InputEvent) -> void:
	# Reading keys for long dialogs: scroll only. Focus, the dialog, progress and
	# gameplay are untouched; with no dialog open the keys do nothing at all.
	if event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
		if overlay != null and overlay.visible and not event.echo:
			var page := int(popup_scroll.size.y)
			match event.keycode:
				KEY_PAGEUP:
					popup_scroll.scroll_vertical -= page
				KEY_PAGEDOWN:
					popup_scroll.scroll_vertical += page
				KEY_HOME:
					popup_scroll.scroll_vertical = 0
				KEY_END:
					popup_scroll.scroll_vertical = int(ceil(popup_scroll.get_v_scroll_bar().max_value))
		get_viewport().set_input_as_handled()
		return
	if story_stage != null and story_stage.is_playing() and event is InputEventKey and event.pressed and not event.echo:
		var focus: Control = get_viewport().gui_get_focus_owner()
		if event.keycode == KEY_ESCAPE:
			story_stage.skip()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not (focus is Button and story_stage.is_ancestor_of(focus)):
			story_stage.advance()
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _confine_journal_focus() -> void:
	# Include nested sliders, checkboxes and font buttons; skip locked chapters.
	var controls: Array[Control] = []
	_collect_dialog_controls(dialog, controls)
	for index in range(controls.size()):
		var previous: NodePath = controls[(index + controls.size() - 1) % controls.size()].get_path()
		var following: NodePath = controls[(index + 1) % controls.size()].get_path()
		controls[index].focus_previous = previous
		controls[index].focus_next = following
		controls[index].focus_neighbor_top = previous
		controls[index].focus_neighbor_bottom = following
		# Leave slider Left/Right to its native keyboard value adjustment.
		if not controls[index] is Slider:
			controls[index].focus_neighbor_left = previous
			controls[index].focus_neighbor_right = following
	var focus: Control = get_viewport().gui_get_focus_owner()
	if not controls.is_empty() and not controls.has(focus):
		controls[0].grab_focus()

func _collect_dialog_controls(node: Node, controls: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree():
			if (child is BaseButton and not child.disabled) or (child is Slider and child.editable):
				child.focus_mode = Control.FOCUS_ALL
				controls.append(child)
		_collect_dialog_controls(child, controls)

func _open_settings() -> void:
	_cancel_presentation_motion()
	super._open_settings()
	_open_settings_marks()
	if touch_mode:
		_touch_controls(dialog)
	_confine_journal_focus()
	_scroll_dialog_to_top()

func _open_settings_marks() -> void:
	for node in dialog.find_children("*", "Button", true, false):
		for value in [1.0, 1.25, 1.5]:
			var caption := "%d%%" % int(value * 100.0)
			if str(node.text).begins_with(caption):
				node.text = caption + (" ✓" if is_equal_approx(float(settings["font_scale"]), value) else "")
	for node in dialog.find_children("*", "Label", true, false):
		if str(node.text) == "설정은 로컬에 저장됩니다.":
			node.text = "설정은 이 기기에 저장됩니다." if touch_mode else "설정은 이 컴퓨터에 저장됩니다."

func _set_font_scale(value: float) -> void:
	super._set_font_scale(value)
	if overlay != null and overlay.visible:
		_open_settings_marks()

func _open_pause() -> void:
	if not touch_mode:
		super._open_pause()
		return
	_show_dialog("메뉴", "진행은 자동 저장됩니다.", [
		{"label": "계속", "call": Callable(self, "_noop")},
		{"label": "이야기", "call": Callable(self, "_open_story")},
		{"label": "기록함", "call": Callable(self, "_open_journal")},
		{"label": "도움말", "call": Callable(self, "_open_help")},
		{"label": "설정", "call": Callable(self, "_open_settings")},
		{"label": "의뢰 초기화", "call": Callable(self, "_ask_reset_from_menu")},
		{"label": "진행 저장", "call": Callable(self, "_save_manually")},
		{"label": "저장 불러오기", "call": Callable(self, "_ask_load_from_menu")},
		{"label": "시작 화면", "call": Callable(self, "_open_start")},
	])

func _ask_reset_from_menu() -> void:
	# The menu closes first, so the inherited guard against open dialogs passes.
	_ask_reset()

func _ask_load_from_menu() -> void:
	_ask_load()

func _move_for_touch(node: Control, parent: Node) -> void:
	# Remember where a node lived so the desktop arrangement can be restored exactly.
	_touch_homes.append([node, node.get_parent(), node.get_index(), node.custom_minimum_size, node.size_flags_horizontal])
	node.reparent(parent)

func _touch_key(node: Control) -> void:
	node.custom_minimum_size.y = TOUCH_KEY
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if node is Button:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _arrange_for_touch(enabled: bool) -> void:
	if print_button == null:
		return
	if touch_bar == null:
		var layout: VBoxContainer = title_navigation.get_parent()
		touch_backing = PanelContainer.new()
		touch_backing.name = "TouchTopBacking"
		var night := UiTheme.surface(Color(UiTheme.NIGHT, 0.84), 10, 4)
		night.border_color = Color(UiTheme.LAMP, 0.22)
		touch_backing.add_theme_stylebox_override("panel", night)
		layout.add_child(touch_backing)
		layout.move_child(touch_backing, 0)
		touch_top = HBoxContainer.new()
		touch_top.name = "TouchTopBar"
		touch_top.add_theme_constant_override("separation", 10)
		touch_backing.add_child(touch_top)
		# The backing shows exactly when the bar does.
		touch_top.visibility_changed.connect(func() -> void: touch_backing.visible = touch_top.visible)
		touch_menu_key = _button(touch_top, "≡ 메뉴", _open_pause, 140)
		touch_menu_key.name = "TouchMenuKey"
		touch_menu_key.custom_minimum_size.y = TOUCH_KEY
		touch_bar = HBoxContainer.new()
		touch_bar.name = "TouchBar"
		touch_bar.add_theme_constant_override("separation", 8)
		layout.add_child(touch_bar)
		layout.move_child(touch_bar, layout.get_child_count() - 2)
		touch_titles = VBoxContainer.new()
		touch_titles.name = "TouchTitles"
		touch_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		touch_titles.alignment = BoxContainer.ALIGNMENT_CENTER
		touch_titles.add_theme_constant_override("separation", 2)
		touch_top.add_child(touch_titles)
		touch_top.hide()
		touch_bar.hide()
	if enabled and _touch_homes.is_empty():
		# Heading and the instruction line share the top bar; the hint key and
		# the order card sit after them.
		for node in [heading, subheading]:
			_move_for_touch(node, touch_titles)
		for node in [hint_key, order_card]:
			if node != null:
				_move_for_touch(node, touch_top)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for node in [hint_key, order_card]:
			if node != null:
				node.custom_minimum_size.y = TOUCH_KEY
				node.size_flags_horizontal = Control.SIZE_SHRINK_END
		if hint_key != null:
			hint_key.custom_minimum_size.x = 150
		for node in [stamp_buttons[0], stamp_buttons[1]] + rotate_keys + [print_button, undo_button, next_button]:
			_move_for_touch(node, touch_bar)
			_touch_key(node)
		# The chosen stamp, turned as it will print, leads the bar: the bench is
		# gone, but the shape with its 1 = 뒤집힐 칸 cells stays in view.
		_move_for_touch(stamp_view, touch_bar)
		touch_bar.move_child(stamp_view, 0)
		stamp_view.custom_minimum_size = Vector2(80, 72)
		title_navigation.hide()
		find_child("StampBench", true, false).hide()
		touch_top.show()
		touch_bar.show()
		if ending_panel != null:
			for node in ending_panel.find_children("*", "Button", true, false):
				node.custom_minimum_size.y = TOUCH_KEY
	elif not enabled and not _touch_homes.is_empty():
		touch_top.hide()
		touch_bar.hide()
		for i in range(_touch_homes.size() - 1, -1, -1):
			var home: Array = _touch_homes[i]
			var node: Control = home[0]
			node.reparent(home[1])
			home[1].move_child(node, home[2])
			node.custom_minimum_size = home[3]
			node.size_flags_horizontal = home[4]
			if node is Button and node != order_card:
				node.autowrap_mode = TextServer.AUTOWRAP_OFF
		_touch_homes.clear()
		title_navigation.show()
		find_child("StampBench", true, false).show()
		if ending_panel != null:
			for node in ending_panel.find_children("*", "Button", true, false):
				node.custom_minimum_size.y = 46
	if is_inside_tree():
		_update_responsive()
		apply_safe_area(_display_safe_area())

func _display_safe_area() -> Rect2i:
	# The phone's notch and rounded corners, in this viewport's coordinates.
	var view := get_viewport_rect()
	if not touch_mode or not OS.has_feature("mobile"):
		return Rect2i(Vector2i.ZERO, Vector2i(view.size))
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(get_window().size)
	if window.x <= 0 or window.y <= 0:
		return Rect2i(Vector2i.ZERO, Vector2i(view.size))
	var scale := view.size / window
	return Rect2i(Vector2i(Vector2(safe.position) * scale), Vector2i(Vector2(safe.size) * scale))

func apply_safe_area(area: Rect2i) -> void:
	# Keep every key clear of the notch: the screen margins grow by the insets.
	var margins: MarginContainer = title_navigation.get_parent().get_parent()
	var view := get_viewport_rect().size
	# Both long edges keep the larger inset, so a half turn of the phone
	# (which moves the notch without a resize) never puts keys under it.
	var side := maxi(0, maxi(area.position.x, int(view.x) - area.end.x))
	var ends := maxi(0, maxi(area.position.y, int(view.y) - area.end.y))
	for edge in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + edge, 16 + side)
	for edge in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 16 + ends)
	_safe_side = side
	if story_stage != null:
		story_stage.set_safe_inset(side, ends)
	_fit_dialog.call_deferred()

func _ask_reset() -> void:
	if not game_active or overlay.visible:
		return
	_show_dialog("의뢰 초기화", "지금 의뢰의 인쇄와 되돌리기 기록을 지울까요?", [
		{"label": "취소", "call": Callable(self, "_noop")},
		{"label": "초기화", "call": Callable(self, "_reset_confirmed")},
	])

func _settings_close() -> void:
	dismiss_story()
	if not game_active:
		_open_start()

func _dialog_action(command: Callable) -> void:
	dismiss_story()
	if command.is_valid():
		command.call()

func _new_game() -> void:
	_begin_campaign()

func _next() -> void:
	advance()

func _serialize_progress() -> Dictionary:
	return campaign_save.envelope(session, hint_levels)

func _valid_progress(data: Variant) -> bool:
	return campaign_save.validate(data)

func _save_progress() -> bool:
	return save_campaign()

func _load_progress() -> bool:
	return load_campaign()

func _read_valid_progress(path: String) -> Variant:
	return campaign_save.read_valid(path)

func _has_valid_save() -> bool:
	return campaign_save.has_save()

func _open_start() -> void:
	game_active = false
	_update_audio()
	var found: bool = _has_valid_save()
	_show_dialog("음영 인쇄소", "1998년 11월 17일 밤, 음영 인쇄소의 야간 작업을 맡았습니다.\n세 장, 의뢰 18건과 하나의 결말. 견본을 맞추면 다음 의뢰 [N]로 넘어갑니다.\n의뢰서와 기록함에서 문서를 읽고, 이야기에서 열린 장과 장면을 다시 볼 수 있습니다.", [
		{"label": "처음부터", "call": Callable(self, "_ask_new_game")},
		{"label": "이어하기" if found else "이어하기 (저장 없음)", "call": Callable(self, "_continue_game") if found else Callable(self, "_open_start"),
			"disabled": not found, "tooltip": "" if found else "저장된 진행이 없습니다. 처음부터 시작하세요."},
		{"label": "기록함", "call": Callable(self, "_open_journal")},
		{"label": "이야기 다시 읽기", "call": Callable(self, "_open_story")},
		{"label": "도움말", "call": Callable(self, "_open_help")},
		{"label": "설정", "call": Callable(self, "_open_settings")},
	] + ([] if touch_mode else [{"label": "종료", "call": Callable(self, "_quit_game")}]))
	# Escape on the start screen must not silently start a new game.
	dialog_back = Callable()
	_primary_button(get_viewport().gui_get_focus_owner() as Button)
	_set_title_look(true)
	_confine_journal_focus()

func _ask_new_game() -> void:
	if game_active and overlay != null and overlay.get_meta("campaign_event_id", "") == "C03_ENDING":
		_ask_ending_replay()
		return
	if game_active or _has_valid_save():
		_confirm_new_campaign(Callable(self, "_noop") if game_active else Callable(self, "_open_start"))
	else:
		_begin_campaign()

func _ask_campaign_replay() -> void:
	if not game_active or not is_finished():
		return
	_confirm_new_campaign(Callable(self, "_noop"))

func _ask_ending_replay() -> void:
	if not game_active or not is_finished():
		return
	_confirm_new_campaign(Callable(self, "_replay_event").bind("C03_ENDING"))

func _confirm_new_campaign(back: Callable) -> void:
	# First option is also Escape. Opening/cancelling only changes the dialog;
	# the affirmative action alone enters the existing new-campaign lifecycle.
	_show_dialog("처음부터 다시 하기", "제1장 첫 의뢰부터 의뢰 18건을 모두 다시 시작합니다. 지금까지의 진행과 저장을 새 진행으로 바꿉니다. 인쇄·되돌리기 기록, 힌트와 읽은 의뢰서 기록도 지워집니다. 설정은 그대로입니다.\n\n처음부터 다시 할까요?", [
		{"label": "취소", "call": back},
		{"label": "처음부터 시작", "call": Callable(self, "_new_game")},
	])

func _open_help() -> void:
	_show_dialog("작업 방법", "밝은 종이 0 / 검은 잉크 1. 도장에 표시된 칸은 인쇄할 때 0↔1로 뒤집힙니다. 같은 도장·방향으로 다시 찍으면 원래대로 돌아갑니다.\n세 장의 종이: 지금 종이(지금 인쇄된 상태) · 찍으면(무료 미리보기) · 견본(맞춰야 할 모양).\n꺾임 도장 [1] · 막대 도장 [2] · 돌리기 [Q]·[E] · 인쇄 [Space]·[Enter] · 되돌리기 [U]·[Z] · 초기화 [R] · 다음 의뢰 [N]\n창이 열려 있을 때 PageUp/PageDown으로 한 화면씩, Home/End로 글의 처음과 끝으로 이동하며 긴 글을 읽을 수 있습니다. 포커스와 진행은 바뀌지 않습니다.\n미리보기는 무료입니다. 선택·회전·힌트는 인쇄 횟수를 늘리지 않습니다. 의뢰마다 쓸 수 있는 도장이 정해져 있습니다.\n세 장, 의뢰 18건입니다. 장의 마지막 견본을 맞춰도 다음 의뢰 [N]를 눌러야 넘어갑니다. 이야기와 의뢰서를 읽어도 진행은 바뀌지 않습니다. 마지막 의뢰를 마치면 결말과 크레딧을 볼 수 있고, 되돌리기나 초기화로 마지막 의뢰를 다시 열 수 있습니다.", [
		{"label": "돌아가기", "call": Callable(self, "_return_from_help")},
	])

func _open_story() -> void:
	var source = _story_source()
	var options: Array = [{"label": "닫기" if game_active else "시작 화면으로", "call": Callable(self, "_close_journal")}]
	var summaries: Array[String] = []
	for chapter in CampaignState.CHAPTERS:
		summaries.append(chapter["title"] + "\n" + chapter["summary"])
		var intro_available: bool = source.event_available(chapter["intro_event"])
		var outro_available: bool = source.event_available(chapter["outro_event"])
		options.append({"label": chapter["title"] + " · 시작 읽기", "call": Callable(self, "_replay_event").bind(chapter["intro_event"]),
			"disabled": not intro_available, "tooltip": "장의 시작을 다시 읽습니다." if intro_available else "다음 의뢰 [N]로 이 장의 첫 의뢰에 들어가면 읽을 수 있습니다."})
		options.append({"label": chapter["title"] + " · 마침 기록 읽기", "call": Callable(self, "_replay_event").bind(chapter["outro_event"]),
			"disabled": not outro_available, "tooltip": "장의 마침 기록을 다시 읽습니다." if outro_available else "이 장의 마지막 의뢰를 마치면 읽을 수 있습니다."})
	for scene in scene_rows():
		var open: bool = _scene_unlocked(source, scene)
		options.append({"label": "장면 · " + str(scene["title"]), "call": Callable(self, "play_scene").bind(str(scene["id"]), Callable(self, "_open_story_at").bind(str(scene["title"]))),
			"disabled": not open, "tooltip": "이 장면을 다시 봅니다." if open else "이야기가 이 장면까지 진행되면 볼 수 있습니다."})
	_show_dialog("이야기 다시 읽기", "열린 장의 기록과 장면을 다시 읽습니다. 의뢰를 고르거나 진행을 바꾸지 않습니다.\n\n" + "\n\n".join(summaries), options)

func _story_source():
	if game_active:
		return session
	var restored: Dictionary = campaign_save.load_candidate()
	return restored["session"] if not restored.is_empty() else CampaignState.new()

func _replay_event(id: String) -> void:
	var source = _story_source()
	if not source.event_available(id):
		return
	# First presentation and every replay use the same immutable event text.
	# Reading/dismissal never saves, marks completion or unlocks a chapter.
	var options: Array = [{"label": "이야기 목록으로", "call": Callable(self, "_open_story")}]
	if id == "C03_ENDING" and game_active and is_finished():
		options.append({"label": "크레딧", "call": Callable(self, "_show_ending_credits")})
		options.append({"label": "처음부터 다시 하기", "call": Callable(self, "_ask_ending_replay")})
	_show_dialog(source.event_title(id), source.event_text(id), options)
	UiTheme.document_font(dialog.get_child(1))
	overlay.set_meta("campaign_event_id", id)
	_play_sound("paper")

func _open_order() -> void:
	if not game_active or overlay.visible:
		return
	var puzzle_id: String = session.puzzle_data()[int(session.snapshot()["puzzle"])]["id"]
	for row in CampaignState.story_data()["orders"]:
		if row["puzzle_id"] == puzzle_id:
			if not session.read_ids().has(row["id"]):
				if not session.mark_read(row["id"]):
					return
				_autosave()
				_refresh()
			_show_order(row, Callable(self, "_noop"), "닫기")
			if not last_save_message.is_empty():
				_label(dialog, last_save_message, 15)
			return

func _show_order(row: Dictionary, back: Callable, caption: String) -> void:
	var when := _date_ko(str(row["encounter_date"])) + (" " + str(row["encounter_time"]) if row.has("encounter_time") else "")
	var origin := "%s 직접 건넨 말" % _subject(str(row["speaker"])) if row["delivery"] == "live_speech" else "%s에 남겨진 문서 · %s" % [_date_ko(str(row["document_date"])), _filed_as(row)]
	_show_dialog("의뢰서 · 의뢰 %d" % _order_number(row), "제%d장 · %s\n%s\n\n%s" % [int(row["chapter"]), when, origin, row["text"]], [
		{"label": caption, "call": back},
	])
	UiTheme.document_font(dialog.get_child(1))
	_add_order_portrait(row)
	_confine_journal_focus()
	_play_sound("paper")

# Phrases that only make sense with a keyboard become touch phrases; then any
# remaining bracketed key hint is dropped.
const TOUCH_PHRASES := [
	["창이 열려 있을 때 PageUp/PageDown으로 한 화면씩, Home/End로 글의 처음과 끝으로 이동하며 긴 글을 읽을 수 있습니다. 포커스와 진행은 바뀌지 않습니다.",
		"긴 글은 손가락으로 밀어 올려 읽을 수 있습니다. 읽어도 진행은 바뀌지 않습니다."],
	["꺾임 도장 [1] · 막대 도장 [2] · 돌리기 [Q]·[E] · 인쇄 [Space]·[Enter] · 되돌리기 [U]·[Z] · 초기화 [R] · 다음 의뢰 [N]",
		"도장 고르기·돌리기·인쇄·되돌리기·다음 의뢰는 화면 아래 버튼으로 합니다. 의뢰 초기화·진행 저장·저장 불러오기는 ≡ 메뉴에 있습니다. 뒤로 가기는 창을 닫거나 메뉴를 엽니다."],
	["돌리기는 [Q]·[E]입니다.", "돌리기는 ↶·↷ 버튼으로 합니다."],
]
var _key_hint := RegEx.create_from_string(" ?\\[(Space|Enter|Esc|Q|E|U|Z|N|R|1|2|PageDown|PageUp|Home|End)\\](·\\[(Enter|Z|E)\\]|/\\[(2|E)\\])?| ?\\((N|U/Z|Space/Enter|Enter|Esc|R|Q/E|1/2)\\)")

func set_touch_mode(enabled: bool) -> void:
	# Phones speak to fingers; the desktop keeps its keyboard hints.
	touch_mode = enabled
	if story_stage != null:
		story_stage.set_touch_mode(enabled)
	_arrange_for_touch(enabled)
	if popup_scroll != null:
		# A dead zone keeps a tap on a key from turning into a scroll.
		popup_scroll.scroll_deadzone = 12 if enabled else 0
	if print_button != null:
		print_button.text = _touch_text("인쇄 [Space]")
		undo_button.text = _touch_text("되돌리기 [U]")
		next_button.text = _touch_text("다음 의뢰 [N]")
		if reset_key != null:
			reset_key.text = _touch_text("초기화 [R]")
	if heading != null:
		_refresh()
	if enabled and overlay != null and overlay.visible:
		_strip_key_hints(dialog)

func _touch_text(text: String) -> String:
	if not touch_mode:
		return text
	for pair in TOUCH_PHRASES:
		text = text.replace(pair[0], pair[1])
	return _key_hint.sub(text, "", true)

func _strip_key_hints(node: Node, skip: Node = null) -> void:
	for child in node.get_children():
		if child == skip:
			continue
		if child is Label or child is Button:
			child.text = _touch_text(child.text)
			child.tooltip_text = _touch_text(child.tooltip_text)
		_strip_key_hints(child, skip)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		# The phone may close a paused app: keep the night's work and quiet the room.
		if game_active:
			_autosave()
		if environment_audio != null:
			environment_audio.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if environment_audio != null:
			environment_audio.stream_paused = false
		_update_audio()
		if touch_mode:
			apply_safe_area(_display_safe_area())
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and touch_mode and title_navigation != null:
		apply_safe_area(_display_safe_area())

func _go_back() -> void:
	# The Android back gesture is Escape: skip a scene, close a dialog, else the menu.
	if story_stage != null and story_stage.is_playing():
		story_stage.skip()
	elif overlay != null and overlay.visible:
		if dialog_back.is_valid():
			_dialog_action(dialog_back)
	elif game_active:
		_open_pause()

func _date_ko(date: String) -> String:
	var parts := date.split("-")
	return "%s년 %d월 %d일" % [parts[0], int(parts[1]), int(parts[2])] if parts.size() == 3 else date

func _order_number(row: Dictionary) -> int:
	for index in range(session.puzzle_count()):
		if session.puzzle_data()[index]["id"] == row["puzzle_id"]:
			return index + 1
	return 0

func _subject(name: String) -> String:
	# Subject particle by the last syllable: 가 after a vowel, 이 after a final consonant.
	var code := name.unicode_at(name.length() - 1)
	return name + ("이" if code >= 0xAC00 and code <= 0xD7A3 and (code - 0xAC00) % 28 != 0 else "가")

func _filed_as(row: Dictionary) -> String:
	# Where a retained document comes from; the 0번 bundle also holds 백인호's
	# statement, so it is never presented as 0번 의뢰인's own writing.
	return "윤해린의 교정 기록" if str(row["speaker"]) == "윤해린" else "0번 의뢰 묶음에 보관됨"

func _order_kind(row: Dictionary) -> String:
	return "직접 건넨 말" if row["delivery"] == "live_speech" else "남겨진 문서"

func _add_order_portrait(row: Dictionary) -> void:
	# Current orders and archive replay share this presentation-only mapping.
	var texture: Texture2D
	var caption: String
	match str(row["speaker"]):
		"백인호":
			texture = PORTRAITS["백인호"]
			caption = "백인호 · 인쇄소 주인"
		"윤해린":
			texture = PORTRAITS["윤해린"]
			caption = "윤해린 · 남겨진 기록 사진"
		"0번 의뢰인":
			texture = PORTRAITS["0번 의뢰인"]
			caption = "0번 의뢰 묶음의 문서"
		_:
			return
	var row_view := _row(dialog, 12)
	row_view.name = "OrderPortrait"
	row_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_view.focus_mode = Control.FOCUS_NONE
	dialog.move_child(row_view, 1)
	var portrait := TextureRect.new()
	portrait.texture = texture
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(96, 112)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.focus_mode = Control.FOCUS_NONE
	row_view.add_child(portrait)
	var description := _label(row_view, caption, 15)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.focus_mode = Control.FOCUS_NONE
	_fit_dialog.call_deferred()

func _journal_read_ids() -> Array:
	if game_active:
		return session.read_ids()
	# Title-screen browsing is read-only and does not publish saved progress.
	# Use the same primary/backup validation as Continue, including replay checks.
	var restored: Dictionary = campaign_save.load_candidate()
	if restored.is_empty():
		return []
	return restored["session"].read_ids()

func _open_journal() -> void:
	var ids: Array = _journal_read_ids()
	var options: Array = [{"label": "닫기", "call": Callable(self, "_close_journal")}]
	for id in ids:
		for row in CampaignState.story_data()["orders"]:
			if row["id"] == id:
				options.append({"label": "의뢰 %d · %s" % [_order_number(row), row["speaker"]], "call": Callable(self, "_replay_order").bind(id)})
	var message := "아직 읽은 의뢰서가 없습니다. 의뢰서를 열면 기록함에 보관됩니다."
	if not ids.is_empty():
		var order_names: Array = []
		for id in ids:
			for row in CampaignState.story_data()["orders"]:
				if row["id"] == id:
					order_names.append("의뢰 %d" % _order_number(row))
		message = "읽은 의뢰서를 골라 전문을 다시 볼 수 있습니다.\n읽은 순서: " + " → ".join(order_names)
	_show_dialog("기록함", message, options)
	_confine_journal_focus()
	_play_sound("paper")

func _replay_order(id: String) -> void:
	if not _journal_read_ids().has(id):
		return
	for row in CampaignState.story_data()["orders"]:
		if row["id"] == id:
			_show_order(row, Callable(self, "_open_journal"), "돌아가기")
			return

func _open_hint() -> void:
	if not game_active or overlay.visible:
		return
	var puzzle: int = session.snapshot()["puzzle"]
	var puzzle_id: String = session.puzzle_data()[puzzle]["id"]
	var contextual: Dictionary = CampaignState.story_data().get("hints", {}).get(puzzle_id, {})
	hint_levels[puzzle] = mini(3, int(hint_levels[puzzle]) + 1)
	var level: int = hint_levels[puzzle]
	# Levels one and two: authored notes for the new puzzles, the general rule and
	# mismatch count for the original eight. Level three: the inherited search from
	# the live board, including allowed masks. Same steps as before, player names.
	var message := "도장에 표시된 칸은 인쇄할 때 뒤집힙니다. 같은 칸을 두 번 뒤집으면 원래대로 돌아옵니다."
	if level == 2:
		message = "지금 종이는 견본과 %d칸 다릅니다. 견본의 0/1을 한 칸씩 비교해 보세요." % session.mismatch_count()
	if not contextual.is_empty() and level < 3:
		message = _player_terms(str(contextual["observation"] if level == 1 else contextual["comparison"]))
	if level == 3:
		var hint: Dictionary = _find_next_move()
		if hint.is_empty():
			message = "이 상태의 짧은 해답을 찾지 못했습니다. 되돌리기 [U]나 초기화 [R]를 써 보세요."
		else:
			message = "제안: %s 도장을 %d°로 맞춘 뒤 인쇄해 보세요. 돌리기는 [Q]·[E]입니다." % [_stamp_name(int(hint["stamp"])), int(hint["rotation"]) * 90]
	if session.is_solved():
		message = "이미 견본과 일치합니다."
	# Persist only the existing hint slot; never select, rotate or print here.
	_autosave()
	_refresh()
	_show_dialog("힌트 %d / 3" % level, message + "
힌트는 종이나 인쇄 횟수를 바꾸지 않습니다.", [
		{"label": "닫기", "call": Callable(self, "_noop")},
		{"label": "다음 힌트", "call": Callable(self, "_hint_again")} if level < 3 else {"label": "의뢰로", "call": Callable(self, "_noop")},
	])

func _guidance(data: Dictionary, preview_cells: Array) -> String:
	if is_finished():
		return "✓ 의뢰 %d건을 모두 마쳤습니다. 다음 의뢰는 없습니다. 아침의 서명과 크레딧을 확인하세요. 되돌리기 [U] · 초기화 [R] · 결말에서 처음부터 다시 할 수 있습니다." % session.puzzle_count()
	if bool(data["solved"]) and int(data["puzzle"]) in [7, 12]:
		return "✓ 이 장의 마지막 견본을 맞췄습니다. 다음 의뢰 [N]를 누르면 장의 마침 기록과 다음 장의 시작을 읽고 넘어갑니다. 되돌리기 [U]로 완료를 취소할 수 있습니다."
	if bool(data["solved"]):
		return "✓ 견본과 일치합니다. 다음 의뢰 [N]로 넘어가세요. 되돌리기 [U]로 완료를 취소할 수 있습니다."
	var selection := "%s 도장 · %d°" % [_stamp_name(int(data["selected_mask"])), int(data["rotation"]) * 90]
	var message := "인쇄 기록 없음 · " if int(data["history_size"]) == 0 and int(data["moves"]) == 0 else "인쇄 %d회 · " % int(data["moves"])
	if preview_cells == data["target"]:
		message += "%s의 미리보기가 견본과 같습니다. 인쇄 [Space]로 완성하세요." % selection
	else:
		# Keys already carry their shortcuts; guidance stays one line at 1280x720.
		message += "%s의 미리보기를 견본과 비교하세요." % selection
	if int(data["puzzle"]) == 0:
		message += " 같은 도장·방향으로 다시 찍으면 그 칸은 원래대로 돌아갑니다."
	elif int(data["history_size"]) > 0:
		message += " 되돌리기 [U]로 취소할 수 있습니다."
	return message

func _refresh() -> void:
	super._refresh()
	var data: Dictionary = session.snapshot()
	var puzzle: Dictionary = session.puzzle_data()[int(data["puzzle"])]
	var chapter: Dictionary = CampaignState.CHAPTERS[int(puzzle["chapter"]) - 1]
	# The original eight keep their protected English data titles; show Korean
	# display names from story data. Later puzzles already carry Korean titles.
	var title: String = str(CampaignState.story_data().get("display_titles", {}).get(puzzle["id"], puzzle["title"]))
	heading.text = "%s · 의뢰 %d / %d · %s" % [chapter["title"], int(data["puzzle"]) + 1, session.puzzle_count(), title]
	# The room behind the workbench follows the chapter's time of night.
	var room := get_node_or_null("NightScene") as TextureRect
	if room != null:
		room.texture = SCENE_PLATES[CHAPTER_PLATES.get(int(puzzle["chapter"]), "night")]
	if atmosphere != null:
		atmosphere.material.set_shader_parameter("tube", 1.0 if int(puzzle["chapter"]) == 1 else 0.0)
	_style_chips(data)
	# Context only: never open an order or mark it read during refresh.
	if order_cue != null:
		for row in CampaignState.story_data()["orders"]:
			if row["puzzle_id"] == puzzle["id"]:
				order_cue.text = "지금 의뢰 %d · %s · %s" % [_order_number(row), row["speaker"], _order_kind(row)]
				if order_card != null:
					order_card.text = "의뢰서 · 의뢰 %d\n%s · %s" % [_order_number(row), row["speaker"], _order_kind(row)]
					order_card.icon = PORTRAITS.get(str(row["speaker"]))
				break
	if int(data["puzzle"]) == 0 and not bool(data["solved"]):
		if int(data["history_size"]) == 0:
			subheading.text = "미리보기를 견본과 비교한 뒤 인쇄하세요."
		else:
			subheading.text = "지금 종이는 견본과 %d칸 다릅니다. 다음 인쇄를 미리 보거나 되돌리기 [U]를 쓰세요." % session.mismatch_count()
	elif int(data["puzzle"]) == 0:
		subheading.text = "견본 완성! 다음 의뢰 [N]로 직접 넘어가세요."
	else:
		subheading.text = "종이에 도장을 찍어 견본과 같은 무늬를 만드세요."
	if bool(data["solved"]):
		reaction_label.text = "✓ 견본 일치"
	for caption in progress_captions:
		caption.text = caption.text.replace(" · 지남", "✓").replace(" · 완료", "✓")
	detail.text = "선택: %s 도장  ·  회전 %d°" % [_stamp_name(int(data["selected_mask"])), int(data["rotation"]) * 90]
	var compact: bool = float(settings["font_scale"]) >= 1.5
	for index in range(stamp_buttons.size()):
		var state_cue: String = " · 사용 불가" if stamp_buttons[index].disabled else (" ✓ 선택" if index == int(data["selected_mask"]) else "")
		stamp_buttons[index].text = "%s%s [%d]%s" % [_stamp_name(index), "" if compact else " 도장", index + 1, state_cue]
	if rotate_keys.size() == 2:
		rotate_keys[0].text = "↶ 왼쪽 [Q]" if compact else "↶ 왼쪽으로 [Q]"
		rotate_keys[1].text = "↷ 오른쪽 [E]" if compact else "↷ 오른쪽으로 [E]"
	if not next_button.disabled:
		next_button.tooltip_text = "다음 의뢰로 직접 넘어갑니다. (N)"
	elif not bool(data["solved"]):
		next_button.tooltip_text = "지금 의뢰의 견본을 먼저 완성해야 다음 의뢰로 넘어갈 수 있습니다."
	if story_button != null:
		story_button.tooltip_text = "열린 장의 시작과 마침 기록, 장면을 다시 읽습니다. 읽어도 진행은 바뀌지 않습니다."
	if ending_panel != null:
		var newly_finished: bool = is_finished() and not ending_panel.visible
		ending_panel.visible = is_finished()
		# The finished sheets stay on the desk only while undo can reopen them.
		if workbench_panel != null:
			workbench_panel.visible = not is_finished()
		if newly_finished:
			# Bring the ending heading and its credits control into view once.
			workbench_scroll.set_deferred("scroll_vertical", 0)
	if is_finished():
		subheading.text = "3장 · 의뢰 18건 완료 · 아침의 서명"
		next_button.tooltip_text = "의뢰 18건을 모두 마쳤습니다. 다음 의뢰는 없습니다."
	elif session.is_solved() and int(session.snapshot()["puzzle"]) in [7, 12]:
		subheading.text = chapter["title"] + " 완료 · 다음 의뢰 [N]로 다음 장에 직접 넘어가세요."
		next_button.tooltip_text = "이 장의 마침 기록과 다음 장의 시작을 보여 주고 다음 장의 첫 의뢰로 넘어갑니다. [N]"
	# The inherited prototype screen still names 목표/반전 in these tooltips.
	print_button.tooltip_text = "이미 견본을 맞췄습니다. 되돌리기 [U]로 다시 찍을 수 있습니다." if session.is_solved() else "선택한 도장의 표시된 칸을 뒤집어 인쇄합니다. [Space]·[Enter]"
	stamp_view.tooltip_text = "지금 고른 도장과 방향입니다. 1로 표시된 칸이 인쇄할 때 뒤집힙니다. 미리보기는 인쇄 횟수에 들어가지 않습니다."
	if hint_key != null:
		var used: int = int(hint_levels[int(data["puzzle"])])
		hint_key.text = "힌트" if used == 0 else "힌트 · %d/3단계" % used
	if touch_mode:
		feedback.text = _touch_text(feedback.text.replace(char(0x2060), ""))
		subheading.text = _touch_text(subheading.text.replace(char(0x2060), ""))
		_strip_key_hints(self, overlay)
	# Korean words stay whole when the status lines wrap at larger text.
	feedback.text = UiTheme.keep_words(feedback.text)
	subheading.text = UiTheme.keep_words(subheading.text)
