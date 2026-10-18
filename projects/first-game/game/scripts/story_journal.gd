extends RefCounted
## Independent read-order archive. Loading is read-only, including corrupt files.
const SAVE_PATH = "user://c01_story_archive_v1.json"
const VALID_IDS := ["C01-01", "C01-02", "C01-03", "C01-04", "C01-05", "C01-06", "C01-07", "C01-08"]

var _ids: Array = []

func _init() -> void:
	reload()

func read_ids() -> Array:
	return _ids.duplicate()

func reload() -> bool:
	var bytes: Variant = _read_bytes(SAVE_PATH)
	if bytes == null:
		return false
	var restored: Variant = _decode(bytes)
	if restored == null:
		return false
	_ids = restored
	return true

func mark_read(id: String) -> bool:
	if not id in VALID_IDS:
		return false
	var candidate: Array = _ids.duplicate()
	if not candidate.has(id):
		candidate.append(id)
	var original: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		original = _read_bytes(SAVE_PATH)
		if original == null:
			return false
		var stored: Variant = _decode(original)
		if stored != null and stored == candidate:
			_ids = candidate
			return true
	var bytes: PackedByteArray = JSON.stringify({"schema_version": 1, "read_ids": candidate}).to_utf8_buffer()
	var temporary: String = SAVE_PATH + ".tmp"
	if not _write_bytes(temporary, bytes):
		return false
	if original != null and _decode(original) == null:
		# Never overwrite an earlier corrupt backup. Verify the exact bytes before
		# attempting replacement; every failure leaves the original and _ids intact.
		var backup: String = SAVE_PATH + ".corrupt.bak"
		var suffix := 0
		while FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup):
			suffix += 1
			backup = SAVE_PATH + ".corrupt.%d.bak" % suffix
		if not _write_bytes(backup, original):
			return false
	var directory := DirAccess.open("user://")
	if directory == null:
		return false
	# Replace from a verified sibling file, without truncating/removing the original.
	if directory.rename(temporary.get_file(), SAVE_PATH.get_file()) != OK:
		return false
	_ids = candidate
	return true

func _read_bytes(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var length: int = file.get_length()
	var bytes: PackedByteArray = file.get_buffer(length)
	var error: Error = file.get_error()
	file.close()
	if bytes.size() != length or error != OK:
		return null
	return bytes

func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return false
	var written: Variant = _read_bytes(path)
	return written != null and written == bytes

func _decode(bytes: PackedByteArray) -> Variant:
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return null
	var data: Variant = parser.data
	if not data is Dictionary:
		return null
	var version: Variant = data.get("schema_version")
	if not (typeof(version) in [TYPE_INT, TYPE_FLOAT]) or version != 1:
		return null
	var ids: Variant = data.get("read_ids")
	if not ids is Array:
		return null
	var validated: Array = []
	for id in ids:
		if not id is String or not id in VALID_IDS or validated.has(id):
			return null
		validated.append(id)
	return validated
