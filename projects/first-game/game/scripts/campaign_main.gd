extends "res://scripts/slice_main.gd"
## Campaign adapter: retain the slice renderer, controls, rules, settings and audio.
## Override lifecycle, progress I/O, archive callbacks and chapter-specific copy.
## Coordinator owns Godot QA/export; narrative and presentation need human review.
const CampaignState = preload("res://scripts/campaign_state.gd")
const CampaignSave = preload("res://scripts/campaign_save.gd")

var campaign_save = CampaignSave.new()
var story_button: Button
var ending_panel: Control

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

func _build_interface() -> void:
	super._build_interface()
	title_area.get_child(0).text = "음영 인쇄소 · 야간 의뢰"
	story_button = _button(next_button.get_parent(), "이야기", _open_story, 100)
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
	_label(column, "18개 퍼즐 완료 · 아침의 서명", 21, GREEN)
	_button(column, "크레딧", show_credits, 130)
	_label(column, str(CampaignState.story_data()["events"]["C03_ENDING"]["text"]), 17)
	ending_panel.hide()

func start_new() -> void:
	# Direct public entry is immediately playable; intro is available in 이야기.
	dismiss_story()
	state = CampaignState.new()
	_reset_campaign_hints()
	game_active = true
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
	last_save_message = "진행 복원 완료"
	dismiss_story()
	if heading != null:
		_refresh()
	return true

func advance() -> void:
	# Keep explicit Next, solved checks, input gates and the available final boundary.
	super._next()

func is_finished() -> bool:
	return session.is_finished()

func show_credits() -> void:
	if not is_finished() or not game_active:
		return
	var credits: Dictionary = CampaignState.story_data()["credits"]
	_show_dialog(credits["title"], credits["text"], [
		{"label": "결말로 돌아가기", "call": Callable(self, "_noop")},
	])

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
	dialog_back = Callable()
	if overlay != null and overlay.has_meta("campaign_event_id"):
		overlay.remove_meta("campaign_event_id")
	if dialog != null:
		if is_inside_tree():
			var focus: Control = get_viewport().gui_get_focus_owner()
			if focus != null and dialog.is_ancestor_of(focus):
				focus.release_focus()
		_disconnect_dialog_actions(dialog)
		super._clear_dialog()

func _show_dialog(title: String, message: String, options: Array) -> void:
	super._show_dialog(title, message, options)
	var buttons: Node = dialog.get_child(dialog.get_child_count() - 1)
	for index in range(options.size()):
		var button: Button = buttons.get_child(index)
		button.disabled = bool(options[index].get("disabled", false))
		button.tooltip_text = str(options[index].get("tooltip", ""))
	_confine_journal_focus()

func _confine_journal_focus() -> void:
	# Disabled future chapters never receive keyboard focus behind a modal.
	var buttons: Array[Control] = []
	for column in dialog.get_children():
		if column is VBoxContainer:
			for child in column.get_children():
				if child is Button and not child.disabled:
					buttons.append(child)
	for index in range(buttons.size()):
		var previous: NodePath = buttons[(index + buttons.size() - 1) % buttons.size()].get_path()
		var following: NodePath = buttons[(index + 1) % buttons.size()].get_path()
		buttons[index].focus_previous = previous
		buttons[index].focus_next = following
		for edge in ["left", "top"]:
			buttons[index].set("focus_neighbor_" + edge, previous)
		for edge in ["right", "bottom"]:
			buttons[index].set("focus_neighbor_" + edge, following)
	if not buttons.is_empty():
		buttons[0].grab_focus()

func _settings_close() -> void:
	dismiss_story()
	if not game_active:
		_open_start()

func _dialog_action(command: Callable) -> void:
	dismiss_story()
	if command.is_valid():
		command.call()

func _new_game() -> void:
	start_new()

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
	var found: bool = _has_valid_save()
	_show_dialog("음영 인쇄소 · 캠페인", "1998년 11월 17일 밤, 음영 인쇄소의 야간 작업을 맡았습니다.\n3장, 모두 %d개 퍼즐과 하나의 결말입니다. 각 목표를 완성할 때마다 다음 버튼 또는 N으로 직접 진행하세요.\n의뢰서와 기록함에서 문서를 읽고, 이야기에서 열린 장의 시작과 마침을 다시 볼 수 있습니다." % session.puzzle_count(), [
		{"label": "처음부터", "call": Callable(self, "_ask_new_game")},
		{"label": "이어하기" if found else "이어하기 (저장 없음)", "call": Callable(self, "_continue_game") if found else Callable(self, "_open_start")},
		{"label": "기록함", "call": Callable(self, "_open_journal")},
		{"label": "이야기 · 장 선택", "call": Callable(self, "_open_story")},
		{"label": "도움말", "call": Callable(self, "_open_help")},
		{"label": "설정", "call": Callable(self, "_open_settings")},
		{"label": "종료", "call": Callable(self, "_quit_game")},
	])
	# Escape on the start screen must not silently start a new game.
	dialog_back = Callable()
	_primary_button(get_viewport().gui_get_focus_owner() as Button)
	_confine_journal_focus()

func _ask_new_game() -> void:
	if _has_valid_save():
		_show_dialog("새 캠페인", "제1장을 처음부터 시작하고 캠페인 저장을 교체할까요?", [
			{"label": "취소", "call": Callable(self, "_open_start")},
			{"label": "처음부터 시작", "call": Callable(self, "_new_game")},
		])
	else:
		start_new()

func _open_help() -> void:
	_show_dialog("캠페인 · 플레이 방법", "밝은 종이 0 / 검은 잉크 1. 도장에 표시된 칸은 인쇄할 때 0↔1로 반전됩니다. 같은 도장·방향으로 다시 찍으면 원래대로 돌아갑니다.\n1/2 선택 · Q/E 회전 · Space/Enter 인쇄 · U/Z 되돌리기 · R 초기화 · N 다음\nAFTER는 무료 미리보기입니다. 선택·회전·힌트는 인쇄 횟수를 늘리지 않습니다. 각 의뢰에서 허용된 도장만 선택할 수 있습니다.\n3장, 모두 %d개 퍼즐입니다. 장의 마지막 목표를 완성해도 다음 버튼으로 직접 진행합니다. 이야기와 의뢰서 읽기는 퍼즐을 진행하지 않습니다. 마지막 완성 후 결말과 크레딧을 볼 수 있습니다. 되돌리기나 초기화로 마지막 퍼즐을 다시 열 수 있습니다." % session.puzzle_count(), [
		{"label": "돌아가기", "call": Callable(self, "_return_from_help")},
	])

func _open_story() -> void:
	var source = _story_source()
	var options: Array = [{"label": "퍼즐로" if game_active else "시작 화면으로", "call": Callable(self, "_close_journal")}]
	var summaries: Array[String] = []
	for chapter in CampaignState.CHAPTERS:
		summaries.append(chapter["title"] + "\n" + chapter["summary"])
		var intro_available: bool = source.event_available(chapter["intro_event"])
		var outro_available: bool = source.event_available(chapter["outro_event"])
		options.append({"label": chapter["title"] + " · 시작 읽기", "call": Callable(self, "_replay_event").bind(chapter["intro_event"]),
			"disabled": not intro_available, "tooltip": "장의 시작을 다시 읽습니다." if intro_available else "다음 버튼으로 이 장의 첫 퍼즐에 들어가면 읽을 수 있습니다."})
		options.append({"label": chapter["title"] + " · 마침 기록 읽기", "call": Callable(self, "_replay_event").bind(chapter["outro_event"]),
			"disabled": not outro_available, "tooltip": "장의 마침 기록을 다시 읽습니다." if outro_available else "이 장의 마지막 퍼즐을 완성하면 읽을 수 있습니다."})
	_show_dialog("이야기 · 장 선택", "\n\n".join(summaries), options)

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
	_show_dialog(source.event_title(id), source.event_text(id), [
		{"label": "장 선택으로", "call": Callable(self, "_open_story")},
	])
	overlay.set_meta("campaign_event_id", id)

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
	var kind := "현재 현장에서 하는 말" if row["delivery"] == "live_speech" else "보관된 문서 · 현재의 발화가 아님"
	var chronology := "제%d장 · 만남 순서 %d · %s" % [int(row["chapter"]), int(row["encounter_sequence"]), row["encounter_date"]]
	if row.has("encounter_time"):
		chronology += " " + row["encounter_time"]
	_show_dialog("의뢰서 · %s" % row["id"], "%s\n%s\n%s 날짜: %s\n기록 명의: %s\n\n%s" % [
		chronology, kind, "발화" if row["delivery"] == "live_speech" else "문서", row["document_date"], row["speaker"], row["text"]], [
		{"label": caption, "call": back},
	])
	_confine_journal_focus()

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
				options.append({"label": "%s · %s" % [id, row["speaker"]], "call": Callable(self, "_replay_order").bind(id)})
	var message := "아직 읽은 의뢰서가 없습니다. 의뢰서를 열면 캠페인 기록함에 보관됩니다."
	if not ids.is_empty():
		message = "읽은 의뢰서를 선택해 전문을 다시 볼 수 있습니다.\n읽은 순서: " + " → ".join(ids)
	_show_dialog("캠페인 · 기록함", message, options)
	_confine_journal_focus()

func _replay_order(id: String) -> void:
	if not _journal_read_ids().has(id):
		return
	for row in CampaignState.story_data()["orders"]:
		if row["id"] == id:
			_show_order(row, Callable(self, "_open_journal"), "기록함으로")
			return

func _open_hint() -> void:
	if not game_active or overlay.visible:
		return
	var puzzle: int = session.snapshot()["puzzle"]
	var puzzle_id: String = session.puzzle_data()[puzzle]["id"]
	var contextual: Dictionary = CampaignState.story_data().get("hints", {}).get(puzzle_id, {})
	# Original eight: inherited presentation. Level three: inherited BFS from
	# the live board, including allowed masks and the solved-board response.
	if contextual.is_empty() or int(hint_levels[puzzle]) >= 2:
		super._open_hint()
		return
	hint_levels[puzzle] = mini(3, int(hint_levels[puzzle]) + 1)
	var level: int = hint_levels[puzzle]
	var message: String = str(contextual["observation"] if level == 1 else contextual["comparison"])
	if session.is_solved():
		message = "이미 목표와 일치합니다."
	# Persist only the existing hint slot; never select, rotate or print here.
	_autosave()
	_refresh()
	_show_dialog("힌트 %d / 3" % level, message + "\n힌트는 보드나 인쇄 횟수를 변경하지 않습니다.", [
		{"label": "닫기", "call": Callable(self, "_noop")},
		{"label": "다음 힌트", "call": Callable(self, "_hint_again")},
	])

func _guidance(data: Dictionary, preview_cells: Array) -> String:
	if is_finished():
		return "✓ %d개 퍼즐을 모두 해결했습니다! 다음 퍼즐이 없습니다. 아침의 서명과 크레딧을 확인하세요. U/Z 되돌리기 · R 초기화 · 메뉴에서 처음부터." % session.puzzle_count()
	if bool(data["solved"]) and int(data["puzzle"]) in [7, 12]:
		return "✓ 장의 목표 완성! 이야기에서 마침 기록을 읽거나 N · 다음 퍼즐로 다음 장에 직접 진행하세요. U/Z로 완료를 되돌릴 수 있습니다."
	return super._guidance(data, preview_cells)

func _refresh() -> void:
	super._refresh()
	var chapter: Dictionary = CampaignState.CHAPTERS[int(session.puzzle_data()[int(session.snapshot()["puzzle"])]["chapter"]) - 1]
	heading.text = chapter["title"] + " · " + heading.text
	if story_button != null:
		story_button.tooltip_text = "진행에 따라 열린 장의 시작과 마침 기록을 다시 읽습니다. 읽기나 닫기는 퍼즐을 진행하지 않습니다."
	if ending_panel != null:
		var newly_finished: bool = is_finished() and not ending_panel.visible
		ending_panel.visible = is_finished()
		if newly_finished:
			# Bring the ending heading and its credits control into view once.
			var scroll: ScrollContainer = heading.get_parent().get_parent().get_parent()
			scroll.set_deferred("scroll_vertical", 0)
	if is_finished():
		subheading.text = "3장 · 18개 의뢰 완료 · 아침의 서명"
		next_button.tooltip_text = "18개 퍼즐을 모두 완성했습니다. 다음 퍼즐이 없습니다."
	elif session.is_solved() and int(session.snapshot()["puzzle"]) in [7, 12]:
		subheading.text = chapter["title"] + " 완료 · 다음 버튼 또는 N으로 다음 장에 직접 진행하세요."
		next_button.tooltip_text = "다음 장의 첫 퍼즐로 직접 진행합니다. (N)"
