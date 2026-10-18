extends SceneTree
class FailWriteJournal extends "res://scripts/story_journal.gd":
	var fail_writes:=false
	func _write_bytes(path: String,bytes: PackedByteArray) -> bool:
		return false if fail_writes else super._write_bytes(path,bytes)
var checks:=0
var failures: Array=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("ARCHIVE EXTENDED FAIL: "+message)
func put(path: String,text: String) -> void:
	var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(text);f.close()
func bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func text_of(n: Node) -> String:
	var result: String=n.text if n is Label or n is BaseButton else ""
	for child in n.get_children():result+="\n"+text_of(child)
	return result
func escape() -> void:
	var e:=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=true;root.push_input(e,true);await process_frame
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var Journal=load("res://scripts/story_journal.gd")
	put(Journal.SAVE_PATH,JSON.stringify({"schema_version":1,"read_ids":[]}))
	var j=Journal.new();check(j.mark_read("C01-03") and j.mark_read("C01-01"),"reverse first-read order writes")
	check(j.read_ids()==["C01-03","C01-01"],"first-read chronology stable")
	var returned: Array=j.read_ids();returned.append("C01-08")
	check(j.read_ids()==["C01-03","C01-01"],"returned ids cannot mutate journal")
	var k=Journal.new();check(k.read_ids()==j.read_ids(),"chronology survives new instance")
	# Embed invalid encodings inside an otherwise valid, ignored JSON string.
	# Replacing them with U+FFFD would wrongly accept the entire envelope.
	for invalid in [PackedByteArray([255]),PackedByteArray([128]),PackedByteArray([192,175]),PackedByteArray([224,128,175]),PackedByteArray([237,160,128]),PackedByteArray([244,144,128,128]),PackedByteArray([240,159,146]),PackedByteArray([194,65])]:
		var envelope: PackedByteArray='{"schema_version":1,"read_ids":[],"memo":"'.to_utf8_buffer()
		envelope.append_array(invalid);envelope.append_array('"}'.to_utf8_buffer())
		check(j._decode(envelope)==null,"invalid UTF-8 inside valid JSON must be rejected")
	check(j._decode('{"schema_version":1,"read_ids":[],"memo":"윤해린의 교정 · 😀"}'.to_utf8_buffer())==[],"valid Korean and four-byte UTF-8 remain accepted")
	var corrupt:=PackedByteArray([123,255,0,42]);var f=FileAccess.open(Journal.SAVE_PATH,FileAccess.WRITE);f.store_buffer(corrupt);f.close()
	check(not j.reload() and j.read_ids()==["C01-03","C01-01"],"invalid bytes preserve memory")
	check(j.mark_read("C01-08"),"explicit read repairs archive")
	check(bytes(Journal.SAVE_PATH+".corrupt.bak")==corrupt,"corrupt backup exact byte equality")
	var failing=FailWriteJournal.new();var old_ids: Array=failing.read_ids();var old_file: PackedByteArray=bytes(Journal.SAVE_PATH)
	failing.fail_writes=true
	check(not failing.mark_read("C01-02"),"injected temp-write failure rejected")
	check(failing.read_ids()==old_ids and bytes(Journal.SAVE_PATH)==old_file,"failed write preserves memory and disk")
	for malformed in ["null","[]","{\"schema_version\":true,\"read_ids\":[]}","{\"schema_version\":1,\"read_ids\":[\"C01-99\"]}","{\"schema_version\":1,\"read_ids\":[\"C01-01\",\"C01-01\"]}"]:
		put(Journal.SAVE_PATH,malformed);check(not j.reload(),"invalid schema rejected");check(j.read_ids()==["C01-03","C01-01","C01-08"],"invalid schema retains memory")
	put(Journal.SAVE_PATH,JSON.stringify({"schema_version":1,"read_ids":["C01-03"]}))
	var view=load("res://integrated_main.tscn").instantiate();view.autosave_enabled=false;root.add_child(view);view._new_game();view.overlay.hide()
	check(view._save_progress(),"isolated fixture progress saves")
	var before: Dictionary=view.state.export_progress();var hints: Array=view.hint_levels.duplicate();var settings: Dictionary=view.settings.duplicate()
	var progress_bytes: PackedByteArray=bytes(view.SAVE_PATH);var settings_bytes: PackedByteArray=bytes(view.SETTINGS_PATH)
	view._open_journal();await process_frame
	var archive_text: String=text_of(view.dialog)
	check("C01-03" in archive_text and not "C01-01" in archive_text and not "C01-08" in archive_text,"C01-03-only archive has no unread spoilers")
	view._replay_order("C01-01");check(text_of(view.dialog)==archive_text,"unread replay rejected")
	view._replay_order("C01-03");await process_frame
	check("의뢰서" in text_of(view.dialog) and "C01-03" in text_of(view.dialog),"read order replays")
	await escape();check(view.overlay.visible and "기록함" in text_of(view.dialog),"nested Escape returns to archive")
	await escape();check(not view.overlay.visible,"archive Escape returns to gameplay")
	check(view.state.export_progress()==before and view.hint_levels==hints and view.settings==settings,"all narrative navigation preserves game/hints/settings")
	check(bytes(view.SAVE_PATH)==progress_bytes and bytes(view.SETTINGS_PATH)==settings_bytes,"narrative navigation preserves core file bytes")
	view._load_confirmed();check(view.story_journal.read_ids()==["C01-03"],"manual core load does not replace independent archive")
	view._new_game();check(view.story_journal.read_ids()==["C01-03"],"new game preserves independent read archive")
	view._open_start();view._open_journal();await escape()
	var focus=root.gui_get_focus_owner()
	check(view.overlay.visible and focus is Button and focus.text=="처음부터","title archive Escape restores start focus")
	view.free();j=null;k=null;failing=null
	print("ARCHIVE_EXTENDED_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"rename_failure_injection":"not_performed"}))
	if failures.is_empty():print("ARCHIVE_EXTENDED_PASS")
	quit(0 if failures.is_empty() else 2)
