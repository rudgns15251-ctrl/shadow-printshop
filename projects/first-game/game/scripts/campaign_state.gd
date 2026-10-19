extends "res://scripts/slice_state.gd"
## Chapter one reuses the original eight rows and every SliceState rule/API.
## Later chapters are framing only; no future revelations are unlocked here.
const CHAPTER_IDS := ["C01", "C02", "C03"]
const EVENT_IDS := ["C01_INTRO", "C01_OUTRO", "C02_INTRO", "C02_OUTRO", "C03_INTRO", "C03_ENDING"]
const CHAPTERS := [
	{"id": "C01", "title": "제1장 · 야간 의뢰", "available": true,
		"intro_event": "C01_INTRO", "outro_event": "C01_OUTRO",
		"summary": "의뢰서와 원본, 작업 대장의 날짜를 대조하는 여덟 번의 야간 작업."},
	{"id": "C02", "title": "제2장 · 교정 흔적", "available": false,
		"intro_event": "C02_INTRO", "outro_event": "C02_OUTRO",
		"summary": "추후 공개 · 자정의 교정 흔적을 따라, 해린이 서명 없이 남긴 이름 복원 의뢰를 대조한다."},
	{"id": "C03", "title": "제3장 · 남겨진 이름", "available": false,
		"intro_event": "C03_INTRO", "outro_event": "C03_ENDING",
		"summary": "추후 공개 · 가족의 기억을 지키려 했던 백인호의 사정을 확인한다. 두 인쇄공의 서명이 남는 하나의 아침 결말로 이어진다."},
]
const INTRO := "1998년 11월 17일 밤, 임시 인쇄공으로 음영 인쇄소의 야간 작업을 맡았다. 의뢰서와 원본을 대조하며 오늘의 표본을 인쇄한다."
const OUTRO := "백인호가 밝힌 윤해린의 퇴사일은 1998-11-12다. 하지만 작업 대장에는 ‘작업일 1998-11-16, 야간 교정 담당 윤해린’이 남아 있다. 퇴사일 나흘 뒤의 작업 기록을 확인했다. 그 이유는 아직 알 수 없다."
const ENDING := "제1장의 야간 작업은 여기까지입니다. 제2장과 제3장, 이야기의 최종 결말은 추후 공개될 콘텐츠입니다."

var _read_ids: Array = []

func chapter_id() -> String:
	return CHAPTER_IDS[0]

func is_finished() -> bool:
	# This means the available chapter-one milestone, not the entire story.
	return int(snapshot()["puzzle"]) == puzzle_count() - 1 and is_solved()

func read_ids() -> Array:
	return _read_ids.duplicate()

func event_available(id: String) -> bool:
	# Availability is derived, never restored from an unchecked unlock flag.
	return id == "C01_INTRO" or (id == "C01_OUTRO" and is_finished())

func event_title(id: String) -> String:
	match id:
		"C01_INTRO":
			return "제1장 · 야간 의뢰 · 시작"
		"C01_OUTRO":
			return "제1장 · 야간 의뢰 · 작업 기록"
	return ""

func event_text(id: String) -> String:
	match id:
		"C01_INTRO":
			return INTRO
		"C01_OUTRO":
			return OUTRO + "\n\n" + ENDING
	return ""

func mark_read(id: String) -> bool:
	var found := false
	for index in range(_puzzle_index + 1):
		if puzzle_data()[index]["id"] == id:
			found = true
			break
	if not found:
		return false
	if not _read_ids.has(id):
		_read_ids.append(id)
	return true

func export_progress() -> Dictionary:
	var progress: Dictionary = super.export_progress()
	progress["read_ids"] = read_ids()
	return progress

func import_progress(data: Variant) -> bool:
	if not data is Dictionary or not data.get("read_ids") is Array:
		return false
	# No persisted chapter/event unlocks: later chapters cannot be enabled by saves.
	# Reject unsupported metadata rather than silently accepting forged flags.
	var keys := ["schema_version", "puzzle_set_version", "puzzle", "board",
		"selected_mask", "rotation", "moves", "history", "read_ids"]
	for key in data:
		if not key in keys:
			return false
	# Direct imports use the same strict version checks as disk candidates.
	if not _whole(data.get("schema_version"), SCHEMA_VERSION, SCHEMA_VERSION):
		return false
	if not _whole(data.get("puzzle_set_version"), PUZZLE_SET_VERSION, PUZZLE_SET_VERSION):
		return false
	if not _whole(data.get("puzzle"), 0, puzzle_count() - 1):
		return false
	var clean_ids: Array = []
	var valid_ids: Array = []
	for index in range(int(data["puzzle"]) + 1):
		valid_ids.append(puzzle_data()[index]["id"])
	for id in data["read_ids"]:
		if not id is String or not id in valid_ids or clean_ids.has(id):
			return false
		clean_ids.append(id)
	# Keep SliceState's replay validation and atomic failure behavior.
	if not super.import_progress(data):
		return false
	_read_ids = clean_ids
	return true
