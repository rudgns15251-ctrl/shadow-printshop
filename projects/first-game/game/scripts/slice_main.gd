extends Control
## C01 eight-puzzle playable slice. Legacy scenes/tests remain unchanged.
## Presentation handoff: slice_acceptance's heading/final text, contextual tooltips,
## focused activation/modal guards, quiet JSON, saves and audio timing are retained.
## Indicators derive only position/current solved status; they store no completion history.
## Coordinator QA: 2 resolutions x 3 font scales, label/slider bounds, core/input/save/
## audio gates, 60 leak trials and Windows export. Human review: Korean, hierarchy,
## palette and listening. Main layout risk: large text uses vertical scrolling.
## Feedback handoff: selection/rotation rim on stamp + AFTER; manual Next rim on
## all three new boards, each 0.20s. Board-owned clocks only draw; no action replay,
## transforms, SFX or delayed state work. Refresh/modal/settings/exit cancel them;
## reduced motion also cancels immediately, keeping selection/orientation text.
## Guidance derives zero-history/printed/preview-match/solved from each refresh.
## Exact buttons/tooltips, manual progression, audio and save contracts retained.
## Coordinator: rapidly select/rotate/print/undo/next, open/close every modal and
## exit mid-cue; compare state/history/hints/save before/after waiting. Toggle
## reduced motion mid-cue and repeat actions; inspect static feedback and final
## completion then undo/reset/load. Human review still required for these cues,
## guidance/learning, six viewport/font combinations, visual taste and listening.
const State = preload("res://scripts/slice_state.gd")
const Board = preload("res://scripts/slice_board.gd")
const StoryOrders = preload("res://data/story_orders.gd")
const StoryJournal = preload("res://scripts/story_journal.gd")
const SAVE_PATH := "user://c01_progress_v1.json"
const SAVE_BACKUP := "user://c01_progress_v1.bak"
const SETTINGS_PATH := "user://c01_settings_v1.json"
const PAPER := Color("#f4ebdd")
const INK := Color("#24211d")
const PANEL := Color("#e4d5be")
const ACCENT := Color("#8a3f24")
const GREEN := Color("#315d49")

var state = State.new()
var story_journal = StoryJournal.new()
var before_view: Control
var after_view: Control
var target_view: Control
var stamp_view: TextureRect
var stamp_mask_view: Control
var reaction_label: Label
var heading: Label
var subheading: Label
var feedback: Label
var detail: Label
var hint_label: Label
var progress_label: Label
var progress_indicators: Array[PanelContainer] = []
var progress_captions: Array[Label] = []
var print_button: Button
var undo_button: Button
var next_button: Button
var stamp_buttons: Array[Button] = []
var overlay: ColorRect
var dialog: VBoxContainer
var boards_grid: GridContainer
var title_navigation: BoxContainer
var title_area: VBoxContainer
var navigation: HBoxContainer
var popup_panel: PanelContainer
var popup_scroll: ScrollContainer
var dialog_back: Callable
var audio: Dictionary = {}
var reaction_time := 0.0
var reaction_kind := "print"
var text_controls: Array = []
var hint_levels: Array = [0, 0, 0, 0, 0, 0, 0, 0]
var settings: Dictionary = {"master": 0.8, "sfx": 0.7, "bgm": 0.3, "mute": false, "font_scale": 1.0, "reduce_motion": false}
var autosave_enabled := true
var game_active := false
var last_save_message := ""

func _ready() -> void:
	get_window().min_size = Vector2i(960, 540)
	_load_settings()
	_build_interface()
	_build_audio()
	set_process(false)
	resized.connect(_update_responsive)
	_update_responsive()
	_refresh()
	_open_start()

func _finish_reaction() -> void:
	reaction_time = 0.0
	set_process(false)
	if stamp_view != null:
		stamp_view.scale = Vector2.ONE
		stamp_view.modulate = Color.WHITE
		stamp_view.rotation = 0.0

func _clear_impression() -> void:
	if before_view == null:
		return
	before_view.clear_impression()
	before_view.clear_success()

func _clear_added_feedback() -> void:
	for view in [stamp_mask_view, before_view, after_view, target_view]:
		if view != null:
			view.clear_feedback()

func _selection_feedback(message: String) -> void:
	reaction_label.text = message
	if not bool(settings["reduce_motion"]):
		stamp_mask_view.animate_feedback()
		after_view.animate_feedback()

func _exit_tree() -> void:
	_clear_added_feedback()
	_finish_reaction()
	_clear_impression()
	# Disconnect deferred layout work before child controls leave the tree.
	if dialog != null and dialog.minimum_size_changed.is_connected(_fit_dialog):
		dialog.minimum_size_changed.disconnect(_fit_dialog)
	dialog_back = Callable()
	for player in audio.values():
		player.stop()
		player.stream = null
	audio.clear()
	text_controls.clear()
	stamp_buttons.clear()
	progress_indicators.clear()
	progress_captions.clear()
	state = null

func _panel_style(color: Color, radius: int = 10, vertical_padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = INK
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.content_margin_top = vertical_padding
	style.content_margin_bottom = vertical_padding
	return style

func _label(parent: Node, caption: String, font_size: int = 18, color: Color = INK) -> Label:
	var item := Label.new()
	item.text = caption
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_color_override("font_color", color)
	item.add_theme_font_size_override("font_size", int(round(font_size * float(settings["font_scale"]))))
	item.set_meta("font_base", font_size)
	text_controls.append(item)
	parent.add_child(item)
	return item

func _button(parent: Node, caption: String, action: Callable, min_width: float = 0) -> Button:
	var item := Button.new()
	item.text = caption
	item.custom_minimum_size = Vector2(min_width, 46)
	item.focus_mode = Control.FOCUS_ALL
	_style_button(item)
	item.add_theme_font_size_override("font_size", int(round(16 * float(settings["font_scale"]))))
	item.set_meta("font_base", 16)
	text_controls.append(item)
	parent.add_child(item)
	item.pressed.connect(action)
	return item

func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color("#153f60")
	style.set_border_width_all(3)
	style.set_expand_margin_all(2)
	return style

func _primary_button(item: Button) -> void:
	_style_button(item, true)

func _style_button(item: Button, primary: bool = false) -> void:
	# Reapply both palettes so Next loses its emphasis on undo/reset/final boundary.
	for color_name in ["font_color", "font_focus_color", "font_hover_color"]:
		item.add_theme_color_override(color_name, PAPER if primary else INK)
	item.add_theme_color_override("font_pressed_color", PAPER)
	item.add_theme_color_override("font_hover_pressed_color", PAPER)
	item.add_theme_color_override("font_disabled_color", Color("#62584c"))
	item.add_theme_stylebox_override("normal", _panel_style(ACCENT if primary else PAPER, 6))
	item.add_theme_stylebox_override("hover", _panel_style(Color("#6f301c") if primary else Color("#efe1cf"), 6))
	item.add_theme_stylebox_override("pressed", _panel_style(INK if primary else ACCENT, 6))
	item.add_theme_stylebox_override("hover_pressed", _panel_style(INK if primary else ACCENT, 6))
	item.add_theme_stylebox_override("disabled", _panel_style(Color("#ddd4c6"), 6))
	item.add_theme_stylebox_override("focus", _focus_style())

func _flow(parent: Node) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	parent.add_child(flow)
	return flow

func _row(parent: Node, separation: int = 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	parent.add_child(row)
	return row

func _column(parent: Node, separation: int = 10) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", separation)
	parent.add_child(col)
	return col

func _build_interface() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 18
	for control_type in ["CheckBox", "HSlider"]:
		for color_name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			ui_theme.set_color(color_name, control_type, INK)
		ui_theme.set_stylebox("focus", control_type, _focus_style())
	theme = ui_theme
	var background := ColorRect.new()
	background.color = Color("#d8c7ad")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 16)
	add_child(margins)
	var layout := _column(margins, 6)
	title_navigation = BoxContainer.new()
	title_navigation.add_theme_constant_override("separation", 8)
	title_navigation.resized.connect(_update_header_layout)
	layout.add_child(title_navigation)
	title_area = _column(title_navigation, 1)
	title_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(title_area, "C01  /  음영 인쇄소", 30)
	subheading = _label(title_area, "종이 위에 도장을 찍어 목표 무늬를 완성하세요.", 15)
	navigation = _row(title_navigation, 8)
	navigation.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button(navigation, "의뢰서", _open_order, 98)
	_button(navigation, "기록함", _open_journal, 98)
	_button(navigation, "도움말", _open_help, 98)
	_button(navigation, "설정", _open_settings, 80)
	_button(navigation, "메뉴", _open_pause, 80)

	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := _column(scroll, 4)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := _column(content, 2)
	heading = _label(header, "", 21)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_label = _label(header, "", 18, GREEN)
	var progression := _flow(header)
	for i in range(state.puzzle_count()):
		var indicator := PanelContainer.new()
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		indicator.focus_mode = Control.FOCUS_NONE
		progression.add_child(indicator)
		progress_indicators.append(indicator)
		var caption := _label(indicator, str(i + 1), 15)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress_captions.append(caption)

	boards_grid = GridContainer.new()
	boards_grid.columns = 3
	boards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boards_grid.add_theme_constant_override("h_separation", 12)
	boards_grid.add_theme_constant_override("v_separation", 12)
	content.add_child(boards_grid)
	var boards: Node = boards_grid
	before_view = _board_card(boards, "CURRENT · 현재", "지금 인쇄된 종이", 0)
	after_view = _board_card(boards, "AFTER · 무료 미리보기", "인쇄 횟수에 포함되지 않아요", 1)
	target_view = _board_card(boards, "TARGET · 목표", "이 모양과 일치시키세요", 2)
	var note := _label(content, "0 = 밝은 종이   ·   1 = 검은 잉크   ·   테두리와 삼각형 = 이번에 바뀔 칸", 15)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL, 10, 4))
	content.add_child(panel)
	var controls := _row(panel, 12)
	var art_column := _column(controls, 6)
	art_column.custom_minimum_size.x = 150
	_label(art_column, "목판 / STAMP", 16)
	stamp_view = TextureRect.new()
	stamp_view.texture = load("res://assets/art/press_wood.svg")
	stamp_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stamp_view.stretch_mode = TextureRect.STRETCH_SCALE
	stamp_view.custom_minimum_size = Vector2(140, 116)
	stamp_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_column.add_child(stamp_view)
	stamp_mask_view = Board.new()
	stamp_mask_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stamp_mask_view.offset_left = 12
	stamp_mask_view.offset_right = -12
	stamp_mask_view.offset_top = 8
	stamp_mask_view.offset_bottom = -8
	stamp_view.add_child(stamp_mask_view)
	_label(art_column, "1 = 반전할 칸", 14)
	reaction_label = _label(art_column, "인쇄 준비", 16, ACCENT)
	var buttons := _column(controls, 2)
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selection := PanelContainer.new()
	selection.add_theme_stylebox_override("panel", _panel_style(INK, 6, 2))
	buttons.add_child(selection)
	detail = _label(selection, "", 19, PAPER)
	_label(buttons, "1  도장 선택 · 회전", 16, ACCENT)
	var select_row := _flow(buttons)
	stamp_buttons.append(_button(select_row, "1 · A (꺾임)", _select.bind(0), 135))
	stamp_buttons.append(_button(select_row, "2 · B (막대)", _select.bind(1), 135))
	_button(select_row, "Q · ↶ 90°", _rotate.bind(-1), 115)
	_button(select_row, "E · ↷ 90°", _rotate.bind(1), 115)
	_label(buttons, "2  미리보기 확인 · 인쇄", 16, ACCENT)
	var action_row := _flow(buttons)
	print_button = _button(action_row, "SPACE · 인쇄", _print, 150)
	_primary_button(print_button)
	undo_button = _button(action_row, "U / Z · 되돌리기", _undo, 170)
	_button(action_row, "R · 초기화", _ask_reset, 120)
	next_button = _button(action_row, "N · 다음 퍼즐", _next, 145)
	var extras := _flow(buttons)
	_button(extras, "힌트", _open_hint, 100)
	_button(extras, "진행 저장", _save_manually, 110)
	_button(extras, "저장 불러오기", _ask_load, 135)
	hint_label = _label(buttons, "힌트 사용 전", 16)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _panel_style(Color("#eee1ce"), 6))
	layout.add_child(footer)
	feedback = _label(footer, "", 17)

	overlay = ColorRect.new()
	overlay.color = Color(0.08, 0.07, 0.06, 0.80)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	popup_panel = PanelContainer.new()
	popup_panel.add_theme_stylebox_override("panel", _panel_style(PAPER, 14))
	center.add_child(popup_panel)
	popup_scroll = ScrollContainer.new()
	popup_scroll.follow_focus = true
	popup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	popup_panel.add_child(popup_scroll)
	dialog = _column(popup_scroll, 16)
	dialog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog.minimum_size_changed.connect(_fit_dialog, CONNECT_DEFERRED)
	overlay.hide()

func _fit_dialog() -> void:
	if not is_inside_tree() or popup_panel == null:
		return
	popup_panel.custom_minimum_size.x = minf(720.0, size.x - 64.0)
	popup_scroll.custom_minimum_size.y = minf(dialog.get_combined_minimum_size().y, size.y - 96.0)

func _update_responsive() -> void:
	_fit_dialog.call_deferred()
	_update_header_layout.call_deferred()
	if boards_grid != null:
		boards_grid.columns = 3 if size.x >= 1170.0 and float(settings["font_scale"]) <= 1.25 else 2

func _update_header_layout() -> void:
	if not is_inside_tree() or title_navigation == null or title_area == null or navigation == null:
		return
	# Measure complete lines at the current font size, independent of prior wrapping.
	var title_width := 0.0
	for label in title_area.get_children():
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		title_width = maxf(title_width, ceilf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x))
	var required_width: float = title_width + navigation.get_combined_minimum_size().x + title_navigation.get_theme_constant("separation")
	title_navigation.vertical = required_width > title_navigation.size.x

func _board_card(parent: Node, title: String, description: String, index: int) -> Control:
	var outer := PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _panel_style(Color("#f9f3e9"), 8, 4))
	parent.add_child(outer)
	var col := _column(outer, 4)
	var ribbon := PanelContainer.new()
	ribbon.add_theme_stylebox_override("panel", _panel_style([INK, ACCENT, GREEN][index], 4, 2))
	col.add_child(ribbon)
	var title_label := _label(ribbon, title, 18, PAPER)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var view := Board.new()
	view.custom_minimum_size = Vector2(156, 156)
	view.frame_color = [INK, ACCENT, GREEN][index]
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(view)
	var description_label := _label(col, description, 16, INK)
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return view

func _build_audio() -> void:
	for sound_name in ["print", "undo", "complete"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/slice_%s.wav" % sound_name)
		add_child(player)
		audio[sound_name] = player
	_update_audio()

func _update_audio() -> void:
	var volume: float = 0.0 if bool(settings["mute"]) else float(settings["master"]) * float(settings["sfx"])
	for key in audio.keys():
		var player: AudioStreamPlayer = audio[key]
		if volume <= 0.0:
			player.stop()
			player.volume_db = -80.0
		else:
			player.volume_db = linear_to_db(volume)

func _play_sound(key: String) -> void:
	if bool(settings["mute"]) or float(settings["master"]) <= 0.0 or float(settings["sfx"]) <= 0.0:
		return
	var player: AudioStreamPlayer = audio.get(key)
	if player != null:
		player.play()

func _react(kind: String = "print") -> void:
	reaction_label.text = {"print": "● 인쇄 완료", "undo": "↶ 되돌림 완료", "solve": "✓ 목표 일치"}[kind]
	_finish_reaction()
	stamp_view.scale = Vector2.ONE
	stamp_view.modulate = Color.WHITE
	if bool(settings["reduce_motion"]):
		return
	stamp_view.pivot_offset = stamp_view.size / 2.0
	reaction_kind = kind
	reaction_time = 0.0
	set_process(true)
	_update_reaction_pose()
	if kind == "solve":
		before_view.animate_success()

func _process(delta: float) -> void:
	reaction_time += delta
	if reaction_time >= (0.22 if reaction_kind == "undo" else 0.24):
		_finish_reaction()
	else:
		_update_reaction_pose()

func _update_reaction_pose() -> void:
	if reaction_kind == "undo":
		# Lift and unwind with a gentle ease out.
		var lift: float = 1.0 - sin(clampf(reaction_time / 0.22, 0.0, 1.0) * PI / 2.0)
		stamp_view.scale = Vector2.ONE * (1.0 - 0.04 * lift)
		stamp_view.rotation = -0.045 * lift
	else:
		# A quick press followed by a slower release, using the existing wood.
		var pressure: float
		if reaction_time < 0.06:
			pressure = 1.0 - pow(1.0 - reaction_time / 0.06, 2.0)
		else:
			pressure = 1.0 - sin(clampf((reaction_time - 0.06) / 0.18, 0.0, 1.0) * PI / 2.0)
		stamp_view.scale = Vector2(1.0 + 0.035 * pressure, 1.0 - 0.10 * pressure)
		stamp_view.modulate = Color.WHITE.lerp(Color("#d8c7ad"), pressure)

func _refresh() -> void:
	_clear_added_feedback()
	_finish_reaction()
	_clear_impression()
	var data: Dictionary = state.snapshot()
	var idx: int = data["puzzle"]
	heading.text = "퍼즐 %d / %d     ·     %s" % [idx + 1, state.puzzle_count(), data["title"]]
	progress_label.text = "인쇄 %d회  |  다른 칸 %d개" % [data["moves"], state.mismatch_count()]
	for i in range(progress_indicators.size()):
		var current: bool = i == idx
		var solved: bool = current and bool(data["solved"])
		var fill: Color = GREEN if solved else (INK if current else (PANEL if i < idx else PAPER))
		var style := _panel_style(fill, 4)
		style.set_content_margin_all(8)
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		progress_indicators[i].add_theme_stylebox_override("panel", style)
		# '지남' describes position, never a claim about saved completion history.
		progress_captions[i].text = str(i + 1) + (" · 완료" if solved else (" · 현재" if current else (" · 지남" if i < idx else "")))
		progress_captions[i].add_theme_color_override("font_color", PAPER if current else INK)
	var affected: Array = [] if data["solved"] else state.get_mask()
	before_view.show_cells(state.get_board(), affected)
	var preview_cells: Array = state.preview()
	after_view.show_cells(preview_cells, affected)
	target_view.show_cells(state.get_target())
	detail.text = "선택: 도장 %s  ·  회전 %d°" % ["A" if data["selected_mask"] == 0 else "B", data["rotation"] * 90]
	stamp_mask_view.show_cells(state.get_mask())
	stamp_view.tooltip_text = "현재 선택·회전을 반영한 도장. 1인 칸을 반전합니다. 미리보기는 인쇄 횟수에 포함되지 않습니다."
	reaction_label.text = "✓ 목표 일치" if data["solved"] else "인쇄 준비"
	before_view.set_completed(data["solved"])
	var allowed: Array = state.puzzle_data()[idx]["allowed_masks"]
	for i in range(stamp_buttons.size()):
		stamp_buttons[i].disabled = not i in allowed
		var selected: bool = i == data["selected_mask"]
		var stamp_style := _panel_style(Color("#d8e8de") if selected else PAPER, 6)
		if selected:
			stamp_style.border_color = GREEN
			stamp_style.set_border_width_all(3)
		stamp_buttons[i].add_theme_stylebox_override("normal", stamp_style)
		stamp_buttons[i].text = ("1 · A (꺾임)" if i == 0 else "2 · B (막대)") + (" · 사용 불가" if stamp_buttons[i].disabled else (" ✓ 선택" if selected else ""))
	print_button.disabled = data["solved"]
	undo_button.disabled = data["history_size"] == 0
	next_button.disabled = not state.can_advance()
	_style_button(next_button, not next_button.disabled)
	print_button.tooltip_text = "이미 목표 무늬를 완성했습니다." if data["solved"] else "선택한 도장의 표시된 칸을 반전해 인쇄합니다. (Space/Enter)"
	undo_button.tooltip_text = "되돌릴 인쇄 기록이 없습니다." if data["history_size"] == 0 else "마지막 인쇄를 되돌립니다. (U/Z)"
	if not next_button.disabled:
		next_button.tooltip_text = "다음 퍼즐로 직접 진행합니다. (N)"
	elif data["solved"]:
		next_button.tooltip_text = "8개 퍼즐을 모두 완성했습니다. 다음 퍼즐이 없습니다."
	else:
		next_button.tooltip_text = "현재 퍼즐을 먼저 완성해야 다음 퍼즐로 진행할 수 있습니다."
	hint_label.text = "힌트 %d / 3단계 사용" % hint_levels[idx] if hint_levels[idx] > 0 else "힌트 사용 전"
	feedback.add_theme_color_override("font_color", GREEN if data["solved"] else INK)
	feedback.text = _guidance(data, preview_cells)
	# Derive guidance from the same snapshot as the boards, including undo/load/reset.
	if idx == 0:
		subheading.text = "목표 완성! NEXT(다음 퍼즐) 버튼 또는 N을 눌러 직접 진행하세요." if data["solved"] else "첫 퍼즐 · 표시된 칸은 인쇄할 때 0↔1로 반전됩니다. AFTER는 무료 미리보기입니다."
	else:
		subheading.text = "종이 위에 도장을 찍어 목표 무늬를 완성하세요."
	_update_header_layout.call_deferred()
	if not last_save_message.is_empty():
		feedback.text += "   |   " + last_save_message

func _guidance(data: Dictionary, preview_cells: Array) -> String:
	# Read-only, with no learned/mastery flags or remembered completion messages.
	if data["solved"]:
		if int(data["puzzle"]) + 1 < state.puzzle_count():
			return "✓ 목표 일치! N 또는 '다음 퍼즐'로 진행하세요. U / Z로 완료를 되돌릴 수 있습니다."
		return "✓ 8개 퍼즐을 모두 해결했습니다! 다음 퍼즐이 없습니다. 메뉴에서 다시 시작할 수 있습니다(시작 화면 → 처음부터). U / Z로 완료를 되돌릴 수 있습니다."
	var selection := "도장 %s · %d°" % ["A" if data["selected_mask"] == 0 else "B", int(data["rotation"]) * 90]
	var message := "인쇄 기록 없음 · " if data["history_size"] == 0 and data["moves"] == 0 else "인쇄 %d회 · " % data["moves"]
	if preview_cells == data["target"]:
		message += "%s의 AFTER가 TARGET과 일치합니다. SPACE로 인쇄하면 완성됩니다." % selection
	else:
		message += "%s의 AFTER와 TARGET을 비교하세요. 1/2 선택 · Q/E 회전 · SPACE 인쇄." % selection
	if data["puzzle"] == 0:
		message += " 같은 도장·방향으로 다시 인쇄하면 그 칸은 원래대로 돌아갑니다. U/Z 되돌리기 · 도움말/힌트."
	elif data["history_size"] > 0:
		message += " U/Z로 마지막 인쇄를 되돌릴 수 있습니다."
	return message

func _select(index: int) -> void:
	if not game_active or overlay.visible:
		return
	if state.select_mask(index):
		_refresh()
		_selection_feedback("도장 %s 선택" % ("A" if index == 0 else "B"))

func _rotate(direction: int) -> void:
	if not game_active or overlay.visible:
		return
	state.rotate(direction)
	_refresh()
	_selection_feedback("%s %d° 회전" % ["↶" if direction < 0 else "↷", int(state.snapshot()["rotation"]) * 90])

func _print() -> void:
	if not game_active or overlay.visible:
		return
	var printed_cells: Array = state.get_mask()
	if state.print_mask():
		_play_sound("complete" if state.is_solved() else "print")
		_autosave()
		_refresh()
		_react("solve" if state.is_solved() else "print")
		if not bool(settings["reduce_motion"]):
			before_view.animate_impression(printed_cells)

func _undo() -> void:
	if not game_active or overlay.visible:
		return
	var previous_cells: Array = state.get_board()
	if state.undo():
		_play_sound("undo")
		_autosave()
		_refresh()
		_react("undo")
		if not bool(settings["reduce_motion"]):
			var changed: Array = []
			var restored: Array = state.get_board()
			for i in range(9):
				changed.append(1 if previous_cells[i] != restored[i] else 0)
			before_view.animate_impression(changed, true)

func _ask_reset() -> void:
	if not game_active or overlay.visible:
		return
	_show_dialog("퍼즐 초기화", "현재 퍼즐의 인쇄와 되돌리기 기록을 지울까요?", [
		{"label": "취소", "call": Callable(self, "_noop")},
		{"label": "초기화", "call": Callable(self, "_reset_confirmed")},
	])

func _reset_confirmed() -> void:
	state.reset()
	_autosave()
	_refresh()

func _next() -> void:
	if not game_active or overlay.visible:
		return
	if state.next_puzzle():
		_autosave()
		_refresh()
		reaction_label.text = "퍼즐 %d 준비" % (int(state.snapshot()["puzzle"]) + 1)
		if not bool(settings["reduce_motion"]):
			for view in [before_view, after_view, target_view]:
				view.animate_feedback(true)

func _noop() -> void:
	pass

func _input(event: InputEvent) -> void:
	# Stop OS autorepeat before focused Button receives Space/Enter.
	if event is InputEventKey and event.pressed and event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		return
	# Esc is reserved for dialogs and the pause/menu flow.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if overlay.visible:
			if dialog_back.is_valid():
				_dialog_action(dialog_back)
			get_viewport().set_input_as_handled()
			return
		if game_active:
			_open_pause()
			get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not game_active or overlay.visible or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER:
		# Focused GUI buttons process activation themselves; no duplicate global PRINT.
		if get_viewport().gui_get_focus_owner() != null:
			return
		_print()
	elif key == KEY_1:
		_select(0)
	elif key == KEY_2:
		_select(1)
	elif key == KEY_Q:
		_rotate(-1)
	elif key == KEY_E:
		_rotate(1)
	elif key == KEY_U or key == KEY_Z:
		_undo()
	elif key == KEY_R:
		_ask_reset()
	elif key == KEY_N:
		_next()
	else:
		return
	get_viewport().set_input_as_handled()

func _clear_dialog() -> void:
	for child in dialog.get_children():
		dialog.remove_child(child)
		child.queue_free()

func _show_dialog(title: String, message: String, options: Array) -> void:
	_clear_added_feedback()
	_clear_dialog()
	overlay.show()
	dialog_back = Callable()
	if title != "음영 인쇄소  ·  C01 수직 슬라이스" and not options.is_empty():
		dialog_back = options[0]["call"]
	_label(dialog, title, 27)
	_label(dialog, message, 17)
	var buttons := _column(dialog, 8)
	for i in range(options.size()):
		var option: Dictionary = options[i]
		var command: Callable = option["call"]
		var btn := _button(buttons, option["label"], _dialog_action.bind(command), 130)
		if i == 0:
			if title in ["음영 인쇄소  ·  C01 수직 슬라이스", "일시정지"]:
				_primary_button(btn)
			btn.grab_focus()
	_fit_dialog.call_deferred()

func _dialog_action(command: Callable) -> void:
	overlay.hide()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	command.call()

func _open_start() -> void:
	game_active = false
	var found: bool = _has_valid_save()
	_show_dialog("음영 인쇄소  ·  C01 수직 슬라이스", "1998년 11월 17일 밤, 임시 인쇄공으로 음영 인쇄소의 야간 작업을 맡았습니다. 의뢰서에서 이번 작업의 기록을 읽으세요.\n도장 A/B를 고르고 회전해 종이의 명암을 반전시키세요. 8개 퍼즐의 목표 무늬를 완성한 뒤 다음 퍼즐로 직접 진행하세요.", [
		{"label": "처음부터", "call": Callable(self, "_ask_new_game")},
		{"label": "이어하기" if found else "이어하기 (저장 없음)", "call": Callable(self, "_continue_game") if found else Callable(self, "_open_start")},
		{"label": "기록함", "call": Callable(self, "_open_journal")},
		{"label": "도움말", "call": Callable(self, "_open_help")},
		{"label": "설정", "call": Callable(self, "_open_settings")},
		{"label": "종료", "call": Callable(self, "_quit_game")},
	])

func _ask_new_game() -> void:
	if _has_valid_save():
		_show_dialog("새 시험", "저장된 기존 진행 상황을 덮어씁니다. 계속할까요?", [
			{"label": "취소", "call": Callable(self, "_open_start")},
			{"label": "새 시험 시작", "call": Callable(self, "_new_game")},
		])
	else:
		_new_game()

func _new_game() -> void:
	state = State.new()
	hint_levels = [0, 0, 0, 0, 0, 0, 0, 0]
	game_active = true
	_autosave()
	_refresh()

func _continue_game() -> void:
	if _load_progress():
		game_active = true
		last_save_message = "진행 복원 완료"
		_refresh()
	else:
		_show_dialog("불러오기 실패", "저장 데이터가 없거나 유효하지 않습니다. 자동 초기화하지 않았습니다.", [
			{"label": "메뉴", "call": Callable(self, "_open_start")},
		])

func _open_pause() -> void:
	_show_dialog("일시정지", "진행은 자동 저장됩니다. 저장 오류가 있으면 화면 아래에 표시됩니다.", [
		{"label": "계속", "call": Callable(self, "_noop")},
		{"label": "도움말", "call": Callable(self, "_open_help")},
		{"label": "설정", "call": Callable(self, "_open_settings")},
		{"label": "진행 저장", "call": Callable(self, "_save_manually")},
		{"label": "시작 화면", "call": Callable(self, "_open_start")},
	])

func _open_order() -> void:
	if not game_active or overlay.visible:
		return
	var puzzle_id: String = state.puzzle_data()[int(state.snapshot()["puzzle"])]["id"]
	for row in StoryOrders.ORDERS:
		if row["puzzle_id"] != puzzle_id:
			continue
		# Only this explicit order-reading path writes the independent archive.
		_show_dialog("의뢰서 · %s" % row["id"], "날짜: %s\n기록 명의: %s\n\n%s" % [row["date"], row["speaker"], row["text"]], [
			{"label": "닫기", "call": Callable(self, "_noop")},
		])
		if not story_journal.mark_read(row["id"]):
			_label(dialog, "기록함에 저장하지 못했습니다. 의뢰서를 다시 열어 재시도해 주세요.", 15)
		# Keep keyboard navigation inside this one-action modal, including Tab.
		var close_button: Control = get_viewport().gui_get_focus_owner()
		close_button.focus_next = close_button.get_path()
		close_button.focus_previous = close_button.get_path()
		for edge in ["left", "top", "right", "bottom"]:
			close_button.set("focus_neighbor_" + edge, close_button.get_path())
		return

func _open_journal() -> void:
	var ids: Array = story_journal.read_ids()
	var options: Array = [{"label": "닫기", "call": Callable(self, "_close_journal")}]
	# Build visible controls only from read IDs, in their first-read order.
	for id in ids:
		for row in StoryOrders.ORDERS:
			if row["id"] == id:
				options.append({"label": "%s · %s" % [id, row["speaker"]], "call": Callable(self, "_replay_order").bind(id)})
	var message := "읽은 의뢰서를 선택하면 전문을 다시 볼 수 있습니다."
	if ids.is_empty():
		message = "아직 읽은 의뢰서가 없습니다. 의뢰서를 열면 이곳에 보관됩니다."
	else:
		message += "\n\n읽은 순서: " + " → ".join(ids)
	_show_dialog("기록함", message, options)
	_confine_journal_focus()

func _close_journal() -> void:
	if not game_active:
		_open_start()

func _replay_order(id: String) -> void:
	if not story_journal.read_ids().has(id):
		return
	for row in StoryOrders.ORDERS:
		if row["id"] != id:
			continue
		_show_dialog("의뢰서 · %s" % row["id"], "날짜: %s\n기록 명의: %s\n\n%s" % [row["date"], row["speaker"], row["text"]], [
			{"label": "기록함으로", "call": Callable(self, "_open_journal")},
		])
		_confine_journal_focus()
		return

func _confine_journal_focus() -> void:
	# Keep Tab and directional focus inside the archive rather than behind it.
	var buttons: Array[Control] = []
	for column in dialog.get_children():
		if column is VBoxContainer:
			for child in column.get_children():
				if child is Button:
					buttons.append(child)
	for i in range(buttons.size()):
		var previous: NodePath = buttons[(i + buttons.size() - 1) % buttons.size()].get_path()
		var following: NodePath = buttons[(i + 1) % buttons.size()].get_path()
		buttons[i].focus_previous = previous
		buttons[i].focus_next = following
		for edge in ["left", "top"]:
			buttons[i].set("focus_neighbor_" + edge, previous)
		for edge in ["right", "bottom"]:
			buttons[i].set("focus_neighbor_" + edge, following)

func _open_help() -> void:
	_show_dialog("플레이 방법", "밝은 종이 0 / 검은 잉크 1. 도장에 표시된 칸은 찍을 때 0↔1로 바뀝니다. 같은 도장·방향으로 다시 찍으면 그 칸은 원래대로 돌아갑니다.\n1/2 선택 · Q/E 회전 · Space/Enter 인쇄 · U/Z 되돌리기 · R 초기화 · N 다음\nAFTER는 무료 미리보기입니다. 미리보기·도장 선택·회전은 인쇄 횟수에 포함되지 않습니다. 막히면 힌트 버튼에서 단계별 도움을 확인하세요.\n3·4번 퍼즐은 B 도장만 허용됩니다. 완료 후 다음 퍼즐로 직접 진행하세요.", [
		{"label": "돌아가기", "call": Callable(self, "_return_from_help")},
	])

func _return_from_help() -> void:
	if not game_active:
		_open_start()

func _open_settings() -> void:
	_clear_added_feedback()
	_clear_dialog()
	overlay.show()
	dialog_back = Callable(self, "_settings_close")
	_label(dialog, "환경 설정", 27)
	_label(dialog, "설정은 로컬에 저장됩니다. BGM은 이번 시범에 포함되지 않았습니다.", 15)
	for key in ["master", "sfx"]:
		# Separate vertical slots guarantee readable, single-line names at 150%.
		# An unwrapped label contributes its full natural width to the dialog.
		var row := _column(dialog, 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := _label(row, "전체 음량" if key == "master" else "효과음", 17)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(285, 32)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_ALL
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = settings[key]
		slider.value_changed.connect(_setting_value_changed.bind(key))
		row.add_child(slider)
	var mute := CheckBox.new()
	mute.text = "모든 소리 음소거"
	mute.button_pressed = bool(settings["mute"])
	mute.toggled.connect(_setting_value_changed.bind("mute"))
	dialog.add_child(mute)
	_register_setting_text(mute)
	var reduce := CheckBox.new()
	reduce.text = "모션 축소 (도장·전환 효과 끄기)"
	reduce.button_pressed = bool(settings["reduce_motion"])
	reduce.toggled.connect(_setting_value_changed.bind("reduce_motion"))
	dialog.add_child(reduce)
	_register_setting_text(reduce)
	var font_label := _label(dialog, "글자 크기", 17)
	font_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	font_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var font_row := _flow(dialog)
	for value in [1.0, 1.25, 1.5]:
		var scale_button := _button(font_row, "%d%%" % int(value * 100.0), _set_font_scale.bind(value), 90)
		scale_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_button(dialog, "돌아가기", _settings_close, 150).grab_focus()
	_fit_dialog.call_deferred()

func _register_setting_text(item: CheckBox) -> void:
	item.set_meta("font_base", 17)
	item.add_theme_font_size_override("font_size", int(round(17 * float(settings["font_scale"]))))
	text_controls.append(item)

func _settings_close() -> void:
	overlay.hide()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	if not game_active:
		_open_start()

func _setting_value_changed(value: Variant, key: String) -> void:
	settings[key] = value
	if key == "reduce_motion" and bool(value):
		_clear_added_feedback()
		_clear_impression()
		_finish_reaction()
		stamp_view.scale = Vector2.ONE
		stamp_view.modulate = Color.WHITE
	_update_audio()
	_save_settings()

func _set_font_scale(value: float) -> void:
	settings["font_scale"] = value
	for element in text_controls:
		if is_instance_valid(element):
			element.add_theme_font_size_override("font_size", int(round(int(element.get_meta("font_base")) * value)))
	_save_settings()
	_update_responsive()

func _open_hint() -> void:
	if not game_active or overlay.visible:
		return
	var puzzle: int = state.snapshot()["puzzle"]
	hint_levels[puzzle] = mini(3, hint_levels[puzzle] + 1)
	var level: int = hint_levels[puzzle]
	var message := "도장에 포함된 칸이 반전됩니다. 같은 칸을 두 번 바꾸면 원래대로 돌아옵니다."
	if level == 2:
		message = "현재 목표와 다른 칸은 %d개입니다. 목표의 0/1을 한 칸씩 비교해 보세요." % state.mismatch_count()
	if level == 3:
		var hint: Dictionary = _find_next_move()
		if state.is_solved():
			message = "이미 목표와 일치합니다."
		elif hint.is_empty():
			message = "이 상태의 짧은 해답을 찾지 못했습니다. 인쇄를 취소하거나 초기화해 보세요."
		else:
			message = "제안: %s 도장을 시계 방향 %d°로 돌리고 인쇄해 보세요." % ["A" if int(hint["stamp"]) == 0 else "B", int(hint["rotation"]) * 90]
	_autosave()
	_refresh()
	_show_dialog("힌트 %d / 3" % level, message + "\n힌트는 보드나 인쇄 횟수를 변경하지 않습니다.", [
		{"label": "닫기", "call": Callable(self, "_noop")},
		{"label": "다음 힌트", "call": Callable(self, "_hint_again")} if level < 3 else {"label": "퍼즐로", "call": Callable(self, "_noop")},
	])

func _hint_again() -> void:
	_open_hint()

func _board_key(board: Array) -> int:
	var value := 0
	for bit in board:
		value = value * 2 + int(bit)
	return value

func _find_next_move() -> Dictionary:
	# BFS over at most 512 binary boards. No gameplay rules are modified.
	var start: Array = state.get_board()
	var target_key: int = _board_key(state.get_target())
	var source_key: int = _board_key(start)
	if source_key == target_key:
		return {}
	var masks: Array = []
	var helper = State.new()
	for stamp in state.puzzle_data()[state.snapshot()["puzzle"]]["allowed_masks"]:
		for rotation in range(4):
			helper.select_mask(stamp)
			helper.set_rotation(rotation)
			masks.append({"stamp": stamp, "rotation": rotation, "bits": _board_key(helper.get_mask())})
	var queue: Array = [source_key]
	var visited: Dictionary = {}
	visited[source_key] = true
	var first_moves: Dictionary = {}
	var at := 0
	while at < queue.size():
		var current: int = queue[at]
		at += 1
		for action in masks:
			var candidate: int = current ^ int(action["bits"])
			if visited.has(candidate):
				continue
			visited[candidate] = true
			first_moves[candidate] = action if current == source_key else first_moves[current]
			if candidate == target_key:
				return first_moves[candidate]
			queue.append(candidate)
	return {}

func _ask_load() -> void:
	if not game_active or overlay.visible:
		return
	_show_dialog("저장된 진행 불러오기", "현재 진행을 저장 데이터로 교체합니다. 취소하면 변하지 않습니다.", [
		{"label": "취소", "call": Callable(self, "_noop")},
		{"label": "불러오기", "call": Callable(self, "_load_confirmed")},
	])

func _load_confirmed() -> void:
	if not _load_progress():
		last_save_message = "저장 파일을 복원할 수 없습니다"
	else:
		last_save_message = "저장된 진행 복원 완료"
	_refresh()

func _save_manually() -> void:
	if not game_active:
		return
	last_save_message = "저장 성공" if _save_progress() else "저장 실패 — 현재 진행 유지"
	_refresh()

func _autosave() -> void:
	if not autosave_enabled:
		return
	last_save_message = "" if _save_progress() else "자동 저장 실패 — 현재 진행 유지"

func _serialize_progress() -> Dictionary:
	var data: Dictionary = state.export_progress()
	data["hints"] = hint_levels.duplicate()
	return data

func _valid_progress(data: Variant) -> bool:
	if not data is Dictionary or not data.has("hints") or not data["hints"] is Array:
		return false
	if data["hints"].size() != state.puzzle_count() and not (data["hints"].size() == 6 and State._whole(data.get("puzzle"), 0, 5)):
		return false
	for value in data["hints"]:
		if not ((typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value == floorf(float(value)) and value >= 0 and value <= 3):
			return false
	var candidate = State.new()
	return candidate.import_progress(data)

func _parse_json_quietly(content: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(content) != OK:
		return null
	return parser.data

func _save_progress() -> bool:
	var content: Dictionary = _serialize_progress()
	if not _valid_progress(content):
		return false
	var temporary := SAVE_PATH + ".tmp"
	var handle := FileAccess.open(temporary, FileAccess.WRITE)
	if handle == null:
		return false
	handle.store_string(JSON.stringify(content))
	handle.flush()
	handle.close()
	var verify: Variant = _parse_json_quietly(FileAccess.get_file_as_string(temporary))
	if not _valid_progress(verify):
		return false
	# All save rotation operations stay inside Godot's user:// directory.
	var save_dir := DirAccess.open("user://")
	if save_dir == null:
		return false
	var save_name := SAVE_PATH.get_file()
	var backup_name := SAVE_BACKUP.get_file()
	var temporary_name := temporary.get_file()
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_BACKUP):
			if save_dir.remove(backup_name) != OK:
				return false
		if save_dir.rename(save_name, backup_name) != OK:
			return false
	if save_dir.rename(temporary_name, save_name) != OK:
		if FileAccess.file_exists(SAVE_BACKUP) and not FileAccess.file_exists(SAVE_PATH):
			save_dir.rename(backup_name, save_name)
		return false
	return true

func _read_valid_progress(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = _parse_json_quietly(FileAccess.get_file_as_string(path))
	return data if _valid_progress(data) else null

func _has_valid_save() -> bool:
	return _read_valid_progress(SAVE_PATH) != null or _read_valid_progress(SAVE_BACKUP) != null

func _load_progress() -> bool:
	var data: Variant = _read_valid_progress(SAVE_PATH)
	if data == null:
		data = _read_valid_progress(SAVE_BACKUP)
	if data == null:
		return false
	var candidate = State.new()
	if not candidate.import_progress(data):
		return false
	state = candidate
	hint_levels = []
	for level in data["hints"]:
		hint_levels.append(int(level))
	while hint_levels.size() < state.puzzle_count():
		hint_levels.append(0)
	return true

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(settings))
		file.close()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var data: Variant = _parse_json_quietly(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not data is Dictionary:
		return
	for key in ["master", "sfx", "bgm"]:
		if data.has(key) and (typeof(data[key]) == TYPE_INT or typeof(data[key]) == TYPE_FLOAT):
			settings[key] = clampf(float(data[key]), 0.0, 1.0)
	for key in ["mute", "reduce_motion"]:
		if data.has(key) and typeof(data[key]) == TYPE_BOOL:
			settings[key] = data[key]
	if data.has("font_scale") and (typeof(data["font_scale"]) == TYPE_INT or typeof(data["font_scale"]) == TYPE_FLOAT):
		if float(data["font_scale"]) in [1.0, 1.25, 1.5]:
			settings["font_scale"] = float(data["font_scale"])

func _quit_game() -> void:
	get_tree().quit()
