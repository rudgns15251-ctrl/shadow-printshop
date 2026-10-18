extends SceneTree
var failures: Array=[]
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);printerr("RELEASE CANDIDATE FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func visible_text(node: Node) -> String:
	var text: String=node.text if node is Control and node.is_visible_in_tree() and (node is Label or node is Button) else ""
	for child in node.get_children():text+="\n"+visible_text(child)
	return text
func run() -> void:
	for path in ["res://campaign_main.tscn","res://CREDITS_KO.md","res://ASSET_LICENSES.json"]:check(FileAccess.file_exists(path),"required release resource "+path)
	if not failures.is_empty():quit(2);return
	var parser:=JSON.new();check(parser.parse(FileAccess.get_file_as_string("res://ASSET_LICENSES.json"))==OK,"valid asset license record")
	var licenses=parser.data
	check(licenses is Array and licenses.size()>0,"nonempty asset register")
	if licenses is Array:
		for row in licenses:
			check(row is Dictionary and row.has("path") and row.has("license") and row.has("origin"),"asset license provenance fields")
			if row is Dictionary and row.has("path"):check(FileAccess.file_exists("res://"+row["path"]) or ResourceLoader.exists("res://"+row["path"]),"licensed asset actually exists")
	var credits:=FileAccess.get_file_as_string("res://CREDITS_KO.md")
	check(credits.length()>50 and "Godot" in credits,"substantive credits including engine")
	var main=load("res://campaign_main.tscn").instantiate();root.add_child(main)
	for forbidden in ["수직 슬라이스","이번 시범","TODO","FIXME","placeholder"]:check(not forbidden in visible_text(main),"product start contains no provisional text")
	main._open_settings();await process_frame
	for forbidden in ["이번 시범","포함되지 않았습니다","TODO","FIXME"]:check(not forbidden in visible_text(main),"actual audio settings contain no misleading provisional text")
	check(main.has_method("show_credits") and main.has_method("get_environment_audio"),"production features reachable")
	check(not main.is_finished(),"fresh user is not completed")
	main.free();print("RELEASE_CANDIDATE_RESULT "+JSON.stringify({"failures":failures,"human_playtest":"not_performed","human_listening":"not_performed"}))
	if failures.is_empty():print("RELEASE_CANDIDATE_PASS")
	quit(0 if failures.is_empty() else 2)
