extends SceneTree
var checks:=0
var failures: Array=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("STORY ARCHIVE FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func text_of(n: Node) -> String:
	var result: String=n.text if n is Label else ""
	for child in n.get_children():result+="\n"+text_of(child)
	return result
func run() -> void:
	if not ResourceLoader.exists("res://scripts/story_journal.gd"):
		check(false,"missing persistent story journal");quit(2);return
	var Journal=load("res://scripts/story_journal.gd");var j=Journal.new()
	check(j.SAVE_PATH=="user://c01_story_archive_v1.json","separate archive namespace")
	check(j.mark_read("C01-01"),"read first order persists")
	check(j.mark_read("C01-03"),"read later order persists")
	check(j.mark_read("C01-01"),"duplicate read allowed")
	var ids: Array=j.read_ids();check(not j.mark_read("C01-99"),"unknown order rejected")
	check(j.read_ids()==ids,"unknown read never mutates archive")
	var k=Journal.new();check(k.read_ids()==ids,"new instance restores recorded ids")
	var f=FileAccess.open(j.SAVE_PATH,FileAccess.WRITE);f.store_string("{invalid json");f.close()
	check(not j.reload() and j.read_ids()==ids,"corrupt reload preserves in-memory archive quietly")
	check(FileAccess.get_file_as_string(j.SAVE_PATH)=="{invalid json","merely reading corrupt file never overwrites it")
	var view=load("res://integrated_main.tscn").instantiate();view.autosave_enabled=false;root.add_child(view)
	view._new_game();view.overlay.hide()
	check(view.has_method("_open_journal"),"actual game exposes journal")
	if view.has_method("_open_journal"):
		view._open_order();view.overlay.hide();view._open_journal();await process_frame
		var before: Dictionary=view.state.export_progress()
		check(view.overlay.visible,"archive modal visible")
		check("C01-01" in text_of(view.dialog),"actual archive displays read order")
		view._print();view._next();check(view.state.export_progress()==before,"archive blocks gameplay")
	view.free();j=null;k=null
	print("STORY_ARCHIVE_RESULT "+JSON.stringify({"checks":checks,"failures":failures}))
	if failures.is_empty():print("STORY_ARCHIVE_PASS")
	quit(0 if failures.is_empty() else 2)
