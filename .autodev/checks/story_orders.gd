extends SceneTree
var failures: Array=[]
var checks:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("STORY ORDER FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func text_of(node: Node) -> String:
	var text: String=node.text if node is Label else ""
	for child in node.get_children():text+="\n"+text_of(child)
	return text
func run() -> void:
	if not ResourceLoader.exists("res://data/story_orders.gd"):
		check(false,"missing playable story data");quit(2);return
	var data=load("res://data/story_orders.gd")
	var orders: Array=data.ORDERS
	check(orders.size()==8,"exactly eight chapter1 orders")
	var view=load("res://integrated_main.tscn").instantiate();view.autosave_enabled=false;root.add_child(view)
	view._new_game();view.overlay.hide()
	check(view.has_method("_open_order"),"actual playable scene exposes order UI")
	if not view.has_method("_open_order"):view.free();quit(2);return
	var ids: Array=[]
	for index in range(orders.size()):
		var row: Dictionary=orders[index]
		for key in ["id","puzzle_id","date","speaker","text"]:check(row.has(key) and row[key] is String,"typed field "+key)
		check(row["id"]=="C01-%02d"%(index+1) and row["puzzle_id"]==row["id"],"stable original puzzle mapping")
		check(not row["id"] in ids,"unique order id");ids.append(row["id"])
		check(row["date"].begins_with("1998-11-"),"fixed period")
		check(row["speaker"] in ["백인호","윤해린","0번 의뢰인"],"canonical speaker")
		check(row["text"].length()>=20 and row["text"].length()<=400,"short substantive prose")
		view.state._puzzle_index=index;view.state.reset();view._refresh()
		var before: Dictionary=view.state.export_progress();var hints: Array=view.hint_levels.duplicate()
		view._open_order();await process_frame
		check(view.overlay.visible,"order actually opens modal")
		check(row["text"] in text_of(view.dialog),"actual dialog renders current order")
		view._print();view._rotate(1);view._undo();view._next()
		check(view.state.export_progress()==before and view.hint_levels==hints,"reading blocks gameplay without altering progress")
		var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
		root.push_input(event,true);await process_frame
		check(not view.overlay.visible,"Escape returns from order")
	view.free();print("STORY_ORDERS_RESULT "+JSON.stringify({"checks":checks,"failures":failures}))
	if failures.is_empty():print("STORY_ORDERS_PASS")
	quit(0 if failures.is_empty() else 2)
