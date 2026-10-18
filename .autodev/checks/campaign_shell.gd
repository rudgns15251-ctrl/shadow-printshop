extends SceneTree
var failures: Array=[]
var checks:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("CAMPAIGN FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://campaign_main.tscn"):
		check(false,"missing product campaign scene");quit(2);return
	var main=load("res://campaign_main.tscn").instantiate();root.add_child(main);await process_frame
	for name in ["start_new","save_campaign","load_campaign","advance","dismiss_story","is_finished"]:check(main.has_method(name),"campaign interface "+name)
	if not failures.is_empty():main.free();quit(2);return
	main.start_new();main.dismiss_story();await process_frame
	check(main.session.puzzle_count()>=8,"campaign preserves original eight")
	check(main.puzzle_view.state==main.session,"actual visible puzzle uses campaign session")
	var original=load("res://data/mech_data.gd")
	for i in range(8):
		for key in ["id","start","target","allowed_masks","solution"]:check(main.session.puzzle_data()[i][key]==original.PUZZLES[i][key],"original puzzle/answer unchanged")
	check(not main.is_finished(),"new campaign not already ended")
	check(main.save_campaign(),"campaign saves separately")
	var saved: Dictionary=main.session.export_progress()
	main.puzzle_view._print();main.puzzle_view._undo()
	check(main.load_campaign(),"campaign load works")
	check(main.session.export_progress()==saved,"campaign lossless round trip")
	var cfg:=ConfigFile.new();check(cfg.load("res://project.godot")==OK,"project config readable")
	check(cfg.get_value("application","run/main_scene","")=="res://campaign_main.tscn","actual product main scene switched")
	main.free();print("CAMPAIGN_SHELL_RESULT "+JSON.stringify({"checks":checks,"failures":failures}))
	if failures.is_empty():print("CAMPAIGN_SHELL_PASS")
	quit(0 if failures.is_empty() else 2)
