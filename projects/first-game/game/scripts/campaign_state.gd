extends "res://scripts/slice_state.gd"
## Data must exist even when the inherited constructor calls reset().
## Static lazy loading also covers SliceState's get_script().new() replay path.
const CHAPTER_IDS := ["C01", "C02", "C03"]
const EVENT_IDS := ["C01_INTRO", "C01_OUTRO", "C02_INTRO", "C02_OUTRO", "C03_INTRO", "C03_ENDING"]
const CHAPTERS := [
	{"id": "C01", "title": "제1장 · 야간 의뢰", "available": true,
		"intro_event": "C01_INTRO", "outro_event": "C01_OUTRO",
		"summary": "의뢰서와 원본, 작업 대장의 날짜를 대조하는 여덟 번의 야간 작업."},
	{"id": "C02", "title": "제2장 · 교정 흔적", "available": true,
		"intro_event": "C02_INTRO", "outro_event": "C02_OUTRO",
		"summary": "자정 이후, 남겨진 교정 표시와 의뢰서의 문구를 대조하는 다섯 작업."},
	{"id": "C03", "title": "제3장 · 남겨진 이름", "available": true,
		"intro_event": "C03_INTRO", "outro_event": "C03_ENDING",
		"summary": "새벽, 원래 교정판과 작업 대장을 마주하는 마지막 다섯 작업."},
]

static var _campaign_rows: Array = []
static var _campaign_story: Dictionary = {}
var _read_ids: Array = []

func puzzle_data() -> Array:
	if _campaign_rows.is_empty():
		var parser := JSON.new()
		var error := parser.parse(FileAccess.get_file_as_string("res://data/campaign_puzzles.json"))
		assert(error == OK and parser.data is Array, "Campaign puzzle JSON must be valid")
		_campaign_rows = parser.data
		assert(_campaign_rows.size() == 18, "Campaign requires eighteen puzzles")
		# JSON numbers become floats; publish integer cells, chapters and actions.
		for row in _campaign_rows:
			row["chapter"] = int(row["chapter"])
			for field in ["start", "target", "allowed_masks", "solution"]:
				row[field] = _integer_board(row[field])
			for field in ["minimum_prints", "reachable_states"]:
				if row.get(field) != null:
					row[field] = int(row[field])
	return _campaign_rows

static func story_data() -> Dictionary:
	if _campaign_story.is_empty():
		var parser := JSON.new()
		var error := parser.parse(FileAccess.get_file_as_string("res://data/campaign_story.json"))
		assert(error == OK and parser.data is Dictionary, "Campaign story JSON must be valid")
		_campaign_story = parser.data
	return _campaign_story

func chapter_id() -> String:
	return CHAPTER_IDS[int(puzzle_data()[_puzzle_index]["chapter"]) - 1]

func is_finished() -> bool:
	return _puzzle_index == puzzle_count() - 1 and is_solved()

func read_ids() -> Array:
	return _read_ids.duplicate()

func event_available(id: String) -> bool:
	# All unlocks derive from validated active progress, never saved flags.
	match id:
		"C01_INTRO":
			return true
		"C01_OUTRO":
			return _puzzle_index > 7 or (_puzzle_index == 7 and is_solved())
		"C02_INTRO":
			return _puzzle_index >= 8
		"C02_OUTRO":
			return _puzzle_index > 12 or (_puzzle_index == 12 and is_solved())
		"C03_INTRO":
			return _puzzle_index >= 13
		"C03_ENDING":
			return is_finished()
	return false

func event_title(id: String) -> String:
	if not event_available(id):
		return ""
	return str(story_data()["events"].get(id, {}).get("title", ""))

func event_text(id: String) -> String:
	if not event_available(id):
		return ""
	return str(story_data()["events"].get(id, {}).get("text", ""))

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
	var keys := ["schema_version", "puzzle_set_version", "puzzle", "board",
		"selected_mask", "rotation", "moves", "history", "read_ids"]
	for key in data:
		if not key in keys:
			return false
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
	# Keep inherited full-history replay and atomic failure behavior.
	if not super.import_progress(data):
		return false
	_read_ids = clean_ids
	return true
