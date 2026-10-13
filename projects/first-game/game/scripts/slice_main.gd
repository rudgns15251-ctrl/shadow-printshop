extends Control
## C01 six-puzzle playable slice. Legacy scenes/tests remain unchanged.
const State = preload("res://scripts/slice_state.gd")
const Board = preload("res://scripts/slice_board.gd")
const SAVE_PATH := "user://c01_progress_v1.json"
const SAVE_BACKUP := "user://c01_progress_v1.bak"
const SETTINGS_PATH := "user://c01_settings_v1.json"
const PAPER := Color("#f4ebdd")
const INK := Color("#24211d")
const PANEL := Color("#e4d5be")
const ACCENT := Color("#8a3f24")
const GREEN := Color("#315d49")

var state = State.new()
var before_view: Control
var after_view: Control
var target_view: Control
var stamp_view: TextureRect
var heading: Label
var subheading: Label
var feedback: Label
var detail: Label
var hint_label: Label
var progress_label: Label
var print_button: Button
var undo_button: Button
var next_button: Button
var stamp_buttons: Array[Button] = []
var overlay: ColorRect
var dialog: VBoxContainer
var boards_grid: GridContainer
var dialog_back: Callable
var audio: Dictionary = {}
var animation: Tween
var text_controls: Array = []
var hint_levels: Array = [0, 0, 0, 0, 0, 0]
var settings: Dictionary = {"master": 0.8, "sfx": 0.7, "bgm": 0.3, "mute": false, "font_scale": 1.0, "reduce_motion": false}
var autosave_enabled := true
var game_active := false
var last_save_message := ""

func _ready() -> void:
	get_window().min_size = Vector2i(960, 540)
	_load_settings()
	_build_interface()
	_build_audio()
	resized.connect(_update_responsive)
	_update_responsive()
	_refresh()
	_open_start()

func _exit_tree() -> void:
	# Release an unfinished stamp reaction when the UI is freed or the game exits.
	if animation != null:
		# Finish both property tweeners while their target still exists,
		# even when shutdown happens before another animation tick.
		animation.custom_step(0.20)
		animation.kill()
		animation = null

func _panel_style(color: Color, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = INK
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
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
	item.add_theme_color_override("font_color", INK)
	item.add_theme_color_override("font_focus_color", INK)
	item.add_theme_color_override("font_hover_color", INK)
	item.add_theme_color_override("font_pressed_color", PAPER)
	item.add_theme_stylebox_override("normal", _panel_style(PAPER, 6))
	item.add_theme_stylebox_override("hover", _panel_style(Color("#efe1cf"), 6))
	item.add_theme_stylebox_override("pressed", _panel_style(ACCENT, 6))
	item.add_theme_stylebox_override("focus", _focus_style())
	item.add_theme_font_size_override("font_size", int(round(16 * float(settings["font_scale"]))))
	item.set_meta("font_base", 16)
	text_controls.append(item)
	parent.add_child(item)
	item.pressed.connect(action)
	return item

func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = ACCENT
	style.set_border_width_all(3)
	style.set_expand_margin_all(2)
	return style

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
	var background := ColorRect.new()
	background.color = PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 16)
	add_child(margins)
	var layout := _column(margins, 10)
	var top := _row(layout, 18)
	var title_area := _column(top, 1)
	title_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(title_area, "C01  /  음영 인쇄소", 28)
	subheading = _label(title_area, "종이 위에 도장을 찍어 목표 무늬를 완성하세요.", 15)
	_button(top, "도움말", _open_help, 98)
	_button(top, "설정", _open_settings, 80)
	_button(top, "메뉴", _open_pause, 80)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := _column(scroll, 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := _row(content, 16)
	heading = _label(header, "", 21)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_label = _label(header, "", 17, GREEN)

	boards_grid = GridContainer.new()
	boards_grid.columns = 3
	boards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boards_grid.add_theme_constant_override("h_separation", 12)
	boards_grid.add_theme_constant_override("v_separation", 12)
	content.add_child(boards_grid)
	var boards: Node = boards_grid
	before_view = _board_card(boards, "현재 무늬", "현재 종이", 0)
	after_view = _board_card(boards, "인쇄 후 미리보기", "적용 전 예상", 1)
	target_view = _board_card(boards, "목표 무늬", "이 모양과 일치시키세요", 2)
	var note := _label(content, "0 = 밝은 종이   ·   1 = 검은 잉크   ·   테두리와 삼각형 = 이번에 바뀔 칸", 15)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL))
	content.add_child(panel)
	var controls := _row(panel, 16)
	var art_column := _column(controls, 6)
	art_column.custom_minimum_size.x = 190
	_label(art_column, "도장 미리보기", 16)
	stamp_view = TextureRect.new()
	stamp_view.texture = load("res://assets/art/stamp_preview.svg")
	stamp_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stamp_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp_view.custom_minimum_size = Vector2(180, 84)
	stamp_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_column.add_child(stamp_view)
	var buttons := _column(controls, 9)
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail = _label(buttons, "", 18)
	var select_row := _row(buttons, 8)
	stamp_buttons.append(_button(select_row, "1 · A (꺾임)", _select.bind(0), 135))
	stamp_buttons.append(_button(select_row, "2 · B (막대)", _select.bind(1), 135))
	_button(select_row, "Q · ↶ 90°", _rotate.bind(-1), 115)
	_button(select_row, "E · ↷ 90°", _rotate.bind(1), 115)
	var action_row := _row(buttons, 8)
	print_button = _button(action_row, "SPACE · 인쇄", _print, 150)
	undo_button = _button(action_row, "U / Z · 되돌리기", _undo, 170)
	_button(action_row, "R · 초기화", _ask_reset, 120)
	next_button = _button(action_row, "N · 다음 퍼즐", _next, 145)
	var extras := _row(buttons, 8)
	_button(extras, "힌트", _open_hint, 100)
	_button(extras, "진행 저장", _save_manually, 110)
	_button(extras, "저장 불러오기", _ask_load, 135)
	hint_label = _label(buttons, "힌트 사용 전", 14)

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
	var popup := PanelContainer.new()
	popup.custom_minimum_size = Vector2(550, 0)
	popup.add_theme_stylebox_override("panel", _panel_style(PAPER, 14))
	center.add_child(popup)
	dialog = _column(popup, 16)
	overlay.hide()

func _update_responsive() -> void:
	if boards_grid != null:
		boards_grid.columns = 3 if size.x >= 1170.0 and float(settings["font_scale"]) <= 1.25 else 2

func _board_card(parent: Node, title: String, description: String, index: int) -> Control:
	var outer := PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _panel_style(Color("#f9f3e9"), 8))
	parent.add_child(outer)
	var col := _column(outer, 6)
	var title_label := _label(col, title, 19)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var view := Board.new()
	view.custom_minimum_size = Vector2(175, 175)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(view)
	var description_label := _label(col, description, 14, ACCENT)
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

func _react() -> void:
	if bool(settings["reduce_motion"]):
		return
	if animation != null and animation.is_running():
		animation.kill()
	stamp_view.pivot_offset = stamp_view.size / 2.0
	stamp_view.scale = Vector2(0.91, 0.91)
	stamp_view.modulate = Color("#bd8a6e")
	animation = create_tween().set_parallel(true)
	animation.tween_property(stamp_view, "scale", Vector2.ONE, 0.14)
	animation.tween_property(stamp_view, "modulate", Color.WHITE, 0.20)

func _refresh() -> void:
	var data: Dictionary = state.snapshot()
	var idx: int = data["puzzle"]
	heading.text = "퍼즐 %d / %d     ·     %s" % [idx + 1, state.puzzle_count(), data["title"]]
	progress_label.text = "인쇄 %d회  |  다른 칸 %d개" % [data["moves"], state.mismatch_count()]
	var affected: Array = [] if data["solved"] else state.get_mask()
	before_view.show_cells(state.get_board(), affected)
	after_view.show_cells(state.preview(), affected)
	target_view.show_cells(state.get_target())
	detail.text = "도장 %s  ·  회전 %d°  ·  미리보기는 횟수에 포함되지 않음" % ["A" if data["selected_mask"] == 0 else "B", data["rotation"] * 90]
	var allowed: Array = state.puzzle_data()[idx]["allowed_masks"]
	for i in range(stamp_buttons.size()):
		stamp_buttons[i].disabled = not i in allowed
		stamp_buttons[i].text = ("1 · A (꺾임)" if i == 0 else "2 · B (막대)") + (" ✓ 선택" if i == data["selected_mask"] else "")
	print_button.disabled = data["solved"]
	undo_button.disabled = data["history_size"] == 0
	next_button.disabled = not state.can_advance()
	hint_label.text = "힌트 %d / 3단계 사용" % hint_levels[idx] if hint_levels[idx] > 0 else "힌트 사용 전"
	if data["solved"]:
		feedback.text = "✓ 목표 일치! N 또는 '다음 퍼즐'로 진행하세요. U / Z로 완료를 되돌릴 수 있습니다." if state.can_advance() else "✓ 6개 퍼즐을 모두 해결했습니다! 메뉴에서 다시 시작할 수 있습니다."
	else:
		feedback.text = "현재와 목표를 비교해 도장을 고르세요. 색과 숫자 0/1을 함께 확인할 수 있습니다."
	if not last_save_message.is_empty():
		feedback.text += "   |   " + last_save_message

func _select(index: int) -> void:
	if not game_active or overlay.visible:
		return
	if state.select_mask(index):
		_refresh()

func _rotate(direction: int) -> void:
	if not game_active or overlay.visible:
		return
	state.rotate(direction)
	_refresh()

func _print() -> void:
	if not game_active or overlay.visible:
		return
	if state.print_mask():
		_react()
		_play_sound("complete" if state.is_solved() else "print")
		_autosave()
		_refresh()

func _undo() -> void:
	if not game_active or overlay.visible:
		return
	if state.undo():
		_play_sound("undo")
		_autosave()
		_refresh()

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
	_clear_dialog()
	overlay.show()
	dialog_back = Callable()
	if title != "음영 인쇄소  ·  C01 수직 슬라이스" and not options.is_empty():
		dialog_back = options[0]["call"]
	_label(dialog, title, 27)
	_label(dialog, message, 17)
	var buttons := _row(dialog, 10)
	for i in range(options.size()):
		var option: Dictionary = options[i]
		var command: Callable = option["call"]
		var btn := _button(buttons, option["label"], _dialog_action.bind(command), 130)
		if i == 0:
			btn.grab_focus()

func _dialog_action(command: Callable) -> void:
	overlay.hide()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	command.call()

func _open_start() -> void:
	game_active = false
	var found: bool = _has_valid_save()
	_show_dialog("음영 인쇄소  ·  C01 수직 슬라이스", "도장 A/B를 고르고 회전해 종이의 명암을 반전시키세요.\n6개 퍼즐과 간단한 사운드·저장 기능을 시험할 수 있습니다.", [
		{"label": "처음부터", "call": Callable(self, "_ask_new_game")},
		{"label": "이어하기" if found else "이어하기 (저장 없음)", "call": Callable(self, "_continue_game") if found else Callable(self, "_open_start")},
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
	hint_levels = [0, 0, 0, 0, 0, 0]
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

func _open_help() -> void:
	_show_dialog("플레이 방법", "밝은 종이 0 / 검은 잉크 1. 도장에 표시된 칸은 찍을 때 0↔1로 바뀝니다.\n1/2 선택 · Q/E 회전 · Space/Enter 인쇄 · U/Z 되돌리기 · R 초기화 · N 다음\n미리보기·도장 선택·회전은 인쇄 횟수에 포함되지 않습니다.\n3·4번 퍼즐은 B 도장만 허용됩니다. 완료 후 다음 퍼즐로 직접 진행하세요.", [
		{"label": "돌아가기", "call": Callable(self, "_return_from_help")},
	])

func _return_from_help() -> void:
	if not game_active:
		_open_start()

func _open_settings() -> void:
	_clear_dialog()
	overlay.show()
	dialog_back = Callable(self, "_settings_close")
	_label(dialog, "환경 설정", 27)
	_label(dialog, "설정은 로컬에 저장됩니다. BGM은 이번 시범에 포함되지 않았습니다.", 15)
	for key in ["master", "sfx"]:
		var row := _row(dialog, 12)
		_label(row, "전체 음량" if key == "master" else "효과음", 17)
		var slider := HSlider.new()
		slider.custom_minimum_size.x = 285
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
	var reduce := CheckBox.new()
	reduce.text = "모션 축소 (도장 반응 애니메이션 끄기)"
	reduce.button_pressed = bool(settings["reduce_motion"])
	reduce.toggled.connect(_setting_value_changed.bind("reduce_motion"))
	dialog.add_child(reduce)
	var font_row := _row(dialog, 9)
	_label(font_row, "글자 크기", 17)
	for value in [1.0, 1.25, 1.5]:
		_button(font_row, "%d%%" % int(value * 100.0), _set_font_scale.bind(value), 90)
	_button(dialog, "돌아가기", _settings_close, 150).grab_focus()

func _settings_close() -> void:
	overlay.hide()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	if not game_active:
		_open_start()

func _setting_value_changed(value: Variant, key: String) -> void:
	settings[key] = value
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
	if data["hints"].size() != 6:
		return false
	for value in data["hints"]:
		if not ((typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value == floorf(float(value)) and value >= 0 and value <= 3):
			return false
	var candidate = State.new()
	return candidate.import_progress(data)

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
	var verify: Variant = JSON.parse_string(FileAccess.get_file_as_string(temporary))
	if not _valid_progress(verify):
		return false
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_BACKUP):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_BACKUP))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_BACKUP)) != OK:
			return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(SAVE_PATH)) != OK:
		if FileAccess.file_exists(SAVE_BACKUP) and not FileAccess.file_exists(SAVE_PATH):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_BACKUP), ProjectSettings.globalize_path(SAVE_PATH))
		return false
	return true

func _read_valid_progress(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
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
	return true

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(settings))
		file.close()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
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
