extends "res://scripts/slice_state.gd"
## Chapter one reuses the original eight rows and every SliceState rule/API.
## Later chapters are framing only; no future revelations are unlocked here.
const CHAPTER_IDS := ["C01", "C02", "C03"]
const EVENT_IDS := ["C01_INTRO", "C01_OUTRO", "C03_ENDING"]
const CHAPTERS := [
	{"id": "C01", "title": "제1장 · 야간 작업", "available": true},
	{"id": "C02", "title": "제2장 · 추후 공개", "available": false},
	{"id": "C03", "title": "제3장 · 추후 공개", "available": false},
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

func mark_read(id: String) -> bool:
	var found := false
	for row in puzzle_data():
		if row["id"] == id:
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
	var clean_ids: Array = []
	var valid_ids: Array = []
	for row in puzzle_data():
		valid_ids.append(row["id"])
	for id in data["read_ids"]:
		if not id is String or not id in valid_ids or clean_ids.has(id):
			return false
		clean_ids.append(id)
	# Keep SliceState's replay validation and atomic failure behavior.
	if not super.import_progress(data):
		return false
	_read_ids = clean_ids
	return true
