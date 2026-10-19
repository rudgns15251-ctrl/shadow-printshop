extends RefCounted
## The only campaign progress writer. Paths are fixed, never supplied by a save.
const CampaignState = preload("res://scripts/campaign_state.gd")
const Utf8 = preload("res://scripts/story_journal.gd")
const SAVE_PATH := "user://c01_campaign_v1.json"
const SAVE_BACKUP := "user://c01_campaign_v1.bak"
const SAVE_TEMP := "user://c01_campaign_v1.json.tmp"
const FORMAT := "c01_campaign"
const SCHEMA_VERSION := 1
const CAMPAIGN_VERSION := 1
const MAX_BYTES := 8 * 1024 * 1024

func envelope(session, hints: Array) -> Dictionary:
	return {"format": FORMAT, "schema_version": SCHEMA_VERSION,
		"campaign_version": CAMPAIGN_VERSION, "chapter_id": session.chapter_id(),
		"progress": session.export_progress(), "hints": hints.duplicate()}

func validate(data: Variant) -> bool:
	return not candidate(data).is_empty()

func candidate(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var keys := ["format", "schema_version", "campaign_version", "chapter_id", "progress", "hints"]
	for key in data:
		if not key in keys:
			return {}
	for key in keys:
		if not data.has(key):
			return {}
	if not data["format"] is String or data["format"] != FORMAT:
		return {}
	if not CampaignState._whole(data["schema_version"], SCHEMA_VERSION, SCHEMA_VERSION):
		return {}
	if not CampaignState._whole(data["campaign_version"], CAMPAIGN_VERSION, CAMPAIGN_VERSION):
		return {}
	if not data["chapter_id"] is String:
		return {}
	var restored = CampaignState.new()
	if not data["hints"] is Array:
		return {}
	var legacy: bool = data["hints"].size() == 8
	if data["hints"].size() != restored.puzzle_count() and not legacy:
		return {}
	var hints: Array = []
	for value in data["hints"]:
		if not CampaignState._whole(value, 0, 3):
			return {}
		hints.append(int(value))
	if not data["progress"] is Dictionary:
		return {}
	if not restored.import_progress(data["progress"]):
		return {}
	# Eight-slot campaign-v1 saves describe C01 only. Preserve every field and
	# append empty hint slots in memory; loading never rewrites either source.
	if legacy and int(restored.snapshot()["puzzle"]) > 7:
		return {}
	if data["chapter_id"] != restored.chapter_id():
		return {}
	while hints.size() < restored.puzzle_count():
		hints.append(0)
	return {"session": restored, "hints": hints}

func _read_bytes(path: String) -> Variant:
	if not path in [SAVE_PATH, SAVE_BACKUP, SAVE_TEMP] or not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var length: int = file.get_length()
	if length <= 0 or length > MAX_BYTES:
		file.close()
		return null
	var bytes: PackedByteArray = file.get_buffer(length)
	var error: Error = file.get_error()
	file.close()
	if error != OK or bytes.size() != length:
		return null
	return bytes

func _read_json(path: String) -> Variant:
	var bytes: Variant = _read_bytes(path)
	if bytes == null or not Utf8.valid_utf8(bytes):
		return null
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return null
	return parser.data

func read_valid(path: String) -> Variant:
	var data: Variant = _read_json(path)
	return data if validate(data) else null

func load_candidate() -> Dictionary:
	# candidate() validates and reconstructs each source once. Do not replay the
	# undo history again merely to turn an already validated envelope into state.
	var restored: Dictionary = candidate(_read_json(SAVE_PATH))
	if restored.is_empty():
		restored = candidate(_read_json(SAVE_BACKUP))
	# Recovery is read-only: corrupt originals and backup bytes are preserved.
	return restored

func has_save() -> bool:
	return read_valid(SAVE_PATH) != null or read_valid(SAVE_BACKUP) != null

func save(session, hints: Array) -> bool:
	var data: Dictionary = envelope(session, hints)
	if not validate(data):
		return false
	var bytes: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	if bytes.size() > MAX_BYTES:
		return false
	var file := FileAccess.open(SAVE_TEMP, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or _read_bytes(SAVE_TEMP) != bytes or read_valid(SAVE_TEMP) == null:
		return false
	var directory := DirAccess.open("user://")
	if directory == null:
		return false
	# Only a validated primary can replace the last known-good backup.
	if read_valid(SAVE_PATH) != null:
		if directory.rename(SAVE_PATH.get_file(), SAVE_BACKUP.get_file()) != OK:
			return false
	if directory.rename(SAVE_TEMP.get_file(), SAVE_PATH.get_file()) != OK:
		# Leave the verified backup in place, including when the primary was corrupt.
		# Recovery remains read-only; a later explicit save can retry the commit.
		return false
	return _read_bytes(SAVE_PATH) == bytes and read_valid(SAVE_PATH) != null
