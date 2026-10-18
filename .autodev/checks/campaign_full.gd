extends SceneTree
var failures: Array=[]
var checks:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("CAMPAIGN FULL FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://campaign_main.tscn"):check(false,"missing campaign");quit(2);return
	var main=load("res://campaign_main.tscn").instantiate();root.add_child(main);main.start_new();main.dismiss_story();await process_frame
	var count: int=main.session.puzzle_count();check(count>=18 and count<=24,"bounded full campaign content")
	var chapters: Array=[];var signatures: Array=[]
	for index in range(count):
		var row: Dictionary=main.session.puzzle_data()[index]
		check(row.has("chapter") and row["chapter"] in [1,2,3],"three chapter mapping")
		if row.has("chapter") and not row["chapter"] in chapters:chapters.append(row["chapter"])
		check(row.has("id") and row.has("solution") and not row["solution"].is_empty(),"identified solvable puzzle")
		var signature=JSON.stringify([row["start"],row["target"],row["allowed_masks"]])
		check(not signature in signatures,"no duplicated puzzle");signatures.append(signature)
		check(main.session.snapshot()["puzzle"]==index,"no auto advance before input")
		main.dismiss_story()
		for action in row["solution"]:
			main.puzzle_view._select(int(int(action)/4));main.session.set_rotation(int(action)%4);main.puzzle_view._print()
		await process_frame
		check(main.session.is_solved(),"published solution solves puzzle")
		check(main.save_campaign(),"save every completion")
		check(main.load_campaign() and main.session.is_solved(),"resume every completion")
		main.dismiss_story()
		if index<count-1:main.advance()
	check(chapters==[1,2,3],"chapter order complete")
	check(main.is_finished(),"ending reached")
	check(main.ending_panel is Control and main.ending_panel.visible,"actual ending presentation exists")
	check(main.has_method("show_credits"),"credits reachable")
	main.show_credits();await process_frame
	check(main.is_finished(),"credits preserve completion")
	main.free();print("CAMPAIGN_FULL_RESULT "+JSON.stringify({"checks":checks,"failures":failures}))
	if failures.is_empty():print("CAMPAIGN_FULL_PASS")
	quit(0 if failures.is_empty() else 2)
