extends SceneTree
## Additional objective coverage for the retained campaign_02 verification block.
## This never certifies human narrative quality, taste, listening or play duration.
class VerificationFailure extends "res://scripts/campaign_save.gd":
	func _read_bytes(path: String) -> Variant:
		return null if path == SAVE_TEMP else super._read_bytes(path)
class FailedSaveView extends "res://scripts/campaign_main.gd":
	func save_campaign() -> bool:
		return false
var checks := 0
var failures: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("CAMPAIGN_RECOVERY_FAIL: " + message)
func put(path: String, value: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(value)
	file.close()
func disk(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func text_of(node: Node) -> String:
	var text: String = node.text if node is Label or node is BaseButton else ""
	for child in node.get_children():
		text += "\n" + text_of(child)
	return text
func unchanged(view, progress: Dictionary, hints: Array, message: String) -> void:
	check(view.session.export_progress() == progress and view.hint_levels == hints, message)
func solve(view) -> void:
	var row: Dictionary = view.session.puzzle_data()[int(view.session.snapshot()["puzzle"])]
	for action in row["solution"]:
		view.session.select_mask(int(action) / 4)
		view.session.set_rotation(int(action) % 4)
		view.session.print_mask()
	view._refresh()
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var Save = load("res://scripts/campaign_save.gd")
	var State = load("res://scripts/campaign_state.gd")
	var view = load("res://campaign_main.tscn").instantiate()
	view.autosave_enabled = false
	root.add_child(view)
	await process_frame
	view.start_new()
	view.dismiss_story()
	var identity = view.session
	var legacy := ["user://c01_progress_v1.json", "user://c01_progress_v1.bak", "user://c01_story_archive_v1.json"]
	for path in legacy:
		put(path, "legacy-sentinel".to_utf8_buffer())
	var original: Dictionary = view.session.export_progress()
	var hints: Array = view.hint_levels.duplicate()
	view.advance()
	unchanged(view, original, hints, "unsolved Next cannot advance")
	view._replay_event("C01_INTRO")
	var intro := text_of(view.dialog)
	check(view.overlay.visible and "1998" in intro, "explicit intro available")
	view.dismiss_story()
	view.dismiss_story()
	unchanged(view, original, hints, "dismissal is idempotent and progress preserving")
	check(not view.overlay.visible and root.gui_get_focus_owner() == null, "dismiss releases hidden focus")
	view._replay_event("C01_INTRO")
	check(text_of(view.dialog) == intro, "intro replay has identical text")
	view.dismiss_story()
	for id in ["C01_OUTRO", "C02_INTRO", "C02_OUTRO", "C03_INTRO", "C03_ENDING", "UNKNOWN"]:
		view._replay_event(id)
		check(not view.overlay.visible, "locked or unknown event cannot open: " + id)
	unchanged(view, original, hints, "blocked replays preserve all progress")
	view._open_order()
	var read: Dictionary = view.session.export_progress()
	var order := text_of(view.dialog)
	view.dismiss_story()
	view._replay_order("C01-01")
	check("C01-01" in order and "C01-01" in text_of(view.dialog), "read order can replay")
	unchanged(view, read, hints, "order replay preserves puzzle, read IDs and hints")
	view.dismiss_story()
	var store = Save.new()
	check(view.save_campaign(), "initial save")
	var valid := disk(Save.SAVE_PATH)
	var candidate: Dictionary = store.envelope(view.session, view.hint_levels)
	for pair in [["event_ids", ["C03_ENDING"]], ["chapter_id", "C03"], ["unlocked_chapters", ["C01", "C02"]]]:
		var forged: Dictionary = candidate.duplicate(true)
		forged["progress"][pair[0]] = pair[1]
		check(not store.validate(forged), "forged narrative metadata rejected: " + pair[0])
	var future: Dictionary = candidate.duplicate(true)
	future["progress"]["read_ids"] = ["C01-08"]
	check(not store.validate(future), "unreached order cannot be restored")
	for chapter in ["C02", "C03", "UNKNOWN"]:
		var forged: Dictionary = candidate.duplicate(true)
		forged["chapter_id"] = chapter
		check(not store.validate(forged), "invalid envelope chapter rejected")
	put(Save.SAVE_BACKUP, valid)
	put(Save.SAVE_PATH, "corrupt primary".to_utf8_buffer())
	var corrupt := disk(Save.SAVE_PATH)
	check(view.load_campaign(), "valid backup restores corrupt primary")
	unchanged(view, read, hints, "backup restores exact state and hints")
	check(view.session == identity and view.puzzle_view.state == identity, "load preserves public state identity")
	check(disk(Save.SAVE_PATH) == corrupt and disk(Save.SAVE_BACKUP) == valid, "backup load never writes")
	check(view.load_campaign() and not view.overlay.visible, "repeated load never opens dialogs")
	check(view.session == identity, "repeated load keeps identity")
	check(view.save_campaign(), "explicit save repairs corrupt primary")
	check(disk(Save.SAVE_BACKUP) == valid, "repair never rotates corrupt bytes into valid backup")
	valid = disk(Save.SAVE_PATH)
	put(Save.SAVE_BACKUP, "bad backup".to_utf8_buffer())
	put(Save.SAVE_PATH, corrupt)
	var bad_backup := disk(Save.SAVE_BACKUP)
	check(not view.load_campaign(), "both invalid files reject loading")
	unchanged(view, read, hints, "rejected load preserves active progress")
	check(disk(Save.SAVE_PATH) == corrupt and disk(Save.SAVE_BACKUP) == bad_backup, "rejected load preserves both files")
	put(Save.SAVE_PATH, valid)
	put(Save.SAVE_BACKUP, valid)
	check(DirAccess.make_dir_absolute(Save.SAVE_TEMP) == OK, "inject temp-open obstruction")
	check(not view.save_campaign(), "temp-open failure returns false")
	check(disk(Save.SAVE_PATH) == valid and disk(Save.SAVE_BACKUP) == valid, "temp failure preserves primary and backup")
	DirAccess.remove_absolute(Save.SAVE_TEMP)
	var verification = VerificationFailure.new()
	check(not verification.save(view.session, view.hint_levels), "temp verification fault returns false")
	check(disk(Save.SAVE_PATH) == valid and disk(Save.SAVE_BACKUP) == valid, "verification fault preserves recoverable saves")
	DirAccess.remove_absolute(Save.SAVE_TEMP)
	# Only files created inside this fresh trusted QA sandbox are removed here.
	DirAccess.remove_absolute(Save.SAVE_PATH)
	check(DirAccess.make_dir_absolute(Save.SAVE_PATH) == OK, "inject final rename obstruction")
	check(not view.save_campaign(), "final rename failure returns false")
	check(disk(Save.SAVE_BACKUP) == valid and not store.load_candidate().is_empty(), "rename failure retains recoverable backup")
	DirAccess.remove_absolute(Save.SAVE_PATH)
	put(Save.SAVE_PATH, valid)
	for index in range(8):
		view.dismiss_story()
		solve(view)
		check(view.session.is_solved(), "known solution solves original puzzle")
		if index < 7:
			view.advance()
			check(int(view.session.snapshot()["puzzle"]) == index + 1, "solved Next advances exactly once")
	check(view.is_finished() and view.next_button.disabled, "eighth puzzle is available final milestone")
	var finished: Dictionary = view.session.export_progress()
	var finished_hints: Array = view.hint_levels.duplicate()
	view.advance()
	unchanged(view, finished, finished_hints, "final Next never wraps or unlocks another chapter")
	view._replay_event("C01_OUTRO")
	var outro := text_of(view.dialog)
	check("1998-11-16" in outro, "outro is available after completion")
	view.dismiss_story()
	view._replay_event("C01_OUTRO")
	check(text_of(view.dialog) == outro, "outro replay text stable")
	unchanged(view, finished, finished_hints, "outro replay preserves completion")
	view.dismiss_story()
	check(view.save_campaign(), "completed state saves")
	view._undo()
	check(not view.is_finished() and not "마지막 퍼즐을 완성" in view.next_button.tooltip_text, "undo immediately refreshes completion and tooltip")
	check(view.load_campaign() and view.is_finished(), "completed save restores completion")
	view._reset_confirmed()
	check(not view.is_finished(), "reset clears milestone completion")
	var failed = FailedSaveView.new()
	failed.autosave_enabled = true
	root.add_child(failed)
	failed.start_new()
	failed.dismiss_story()
	failed._open_order()
	check("저장 실패" in text_of(failed.dialog), "order save failure remains visible")
	failed.free()
	for size in [Vector2i(960,540), Vector2i(1280,720)]:
		root.size = size
		for font in [1.0,1.25,1.5]:
			view._set_font_scale(font)
			view._open_story()
			await process_frame
			check(view.overlay.visible and is_instance_valid(root.gui_get_focus_owner()), "story actions remain focusable at size/font")
			view.dismiss_story()
	for path in legacy:
		check(disk(path) == "legacy-sentinel".to_utf8_buffer(), "legacy namespace untouched: " + path)
	view.free()
	print("CAMPAIGN_RECOVERY_RESULT " + JSON.stringify({"checks":checks,"failures":failures,"human_review":"not_performed"}))
	if failures.is_empty():
		print("CAMPAIGN_RECOVERY_PASS")
	quit(0 if failures.is_empty() else 2)
