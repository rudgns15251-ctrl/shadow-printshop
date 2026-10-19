extends SceneTree
## Objective hints/boundary coverage only. Human difficulty and prose stay pending.
const MASKS = [11,38,416,200,7,292,448,73]
var checks := 0
var failures: Array = []
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("CAMPAIGN_HINT_FAIL: " + message)
func bits(cells: Array) -> int:
	var result := 0
	for index in range(9):result |= int(cells[index]) << index
	return result
func distance(start: int,target: int,masks: Array) -> int:
	var queue: Array = [start]
	var distances: Dictionary = {start:0}
	var cursor := 0
	while cursor < queue.size():
		var board: int = queue[cursor];cursor += 1
		if board == target:return int(distances[board])
		for stamp in masks:
			for rotation in range(4):
				var following: int = board ^ MASKS[int(stamp)*4+rotation]
				if not distances.has(following):
					distances[following] = int(distances[board])+1
					queue.append(following)
	return -1
func text_of(node: Node) -> String:
	var text: String = node.text if node is Label or node is BaseButton else ""
	for child in node.get_children():text += "\n"+text_of(child)
	return text
func hint_scenario(view,row: Dictionary,label: String) -> Array:
	var index: int = view.session.snapshot()["puzzle"]
	view.hint_levels[index] = 0
	var captured: Array = []
	for level in range(1,4):
		view.dismiss_story()
		var before: Dictionary = view.session.export_progress().duplicate(true)
		view._open_hint()
		check(view.overlay.visible and view.hint_levels[index] == level,label+" opens correct hint level")
		var after: Dictionary = view.session.export_progress().duplicate(true)
		before.erase("read_ids");after.erase("read_ids")
		check(after == before,label+" hint preserves board/selection/rotation/moves/history/index")
		captured.append(text_of(view.dialog))
		if level == 3:
			var action: Dictionary = view._find_next_move()
			var valid: bool = action.has("stamp") and action.has("rotation") and action["stamp"] in row["allowed_masks"] and int(action["rotation"]) in range(4)
			check(valid,label+" live suggestion is allowed")
			if valid:
				var board := bits(view.session.get_board());var target := bits(row["target"])
				var next_board: int = board ^ MASKS[int(action["stamp"])*4+int(action["rotation"])]
				check(distance(next_board,target,row["allowed_masks"]) == distance(board,target,row["allowed_masks"])-1,label+" reduces actual shortest distance by one")
				var expression := RegEx.new();expression.compile("([AB]) 도장을 시계 방향 ([0-9]+)°")
				var rendered := expression.search(text_of(view.dialog))
				check(rendered != null,label+" actual dialog renders existing level-three suggestion")
				if rendered != null:
					check((0 if rendered.get_string(1)=="A" else 1)==int(action["stamp"]) and int(rendered.get_string(2))==int(action["rotation"])*90,label+" rendered suggestion matches live solver")
		view.dismiss_story()
	check(view.save_campaign(),label+" hinted state saves")
	var hints: Array = view.hint_levels.duplicate()
	var saved: Dictionary = view.session.export_progress().duplicate(true)
	check(view.load_campaign() and view.hint_levels==hints and view.session.export_progress()==saved,label+" hints and full state restore")
	return captured
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view = load("res://campaign_main.tscn").instantiate()
	view.autosave_enabled = false;root.add_child(view);await process_frame
	view.start_new();view.dismiss_story()
	check(view.session.puzzle_count()==18,"exact18 campaign")
	var identity = view.session
	var first_texts: Array = [];var second_texts: Array = []
	for index in range(18):
		var row: Dictionary = view.session.puzzle_data()[index]
		view.dismiss_story()
		if index >= 8:
			var texts := hint_scenario(view,row,row["id"]+" start")
			check(not texts[0] in first_texts and not texts[1] in second_texts,"distinct authored first/second hints: "+row["id"])
			first_texts.append(texts[0]);second_texts.append(texts[1])
			var sampled := false
			for stamp in row["allowed_masks"]:
				for rotation in range(4):
					var action: int = int(stamp)*4+rotation
					if (bits(view.session.get_board()) ^ MASKS[action]) != bits(row["target"]):
						view._select(stamp);view.session.set_rotation(rotation);view._print()
						hint_scenario(view,row,row["id"]+" after non-solving print")
						sampled = true;break
				if sampled:break
			check(sampled,"tested a non-solving print for each new puzzle")
			view.session.reset();view._refresh()
		view._open_order();view.dismiss_story()
		var previous: Dictionary = {}
		for action in row["solution"]:
			view._select(int(int(action)/4));view.session.set_rotation(int(action)%4)
			previous = view.session.export_progress().duplicate(true)
			view._print()
		var solved: Dictionary = view.session.export_progress().duplicate(true)
		var hints: Array = view.hint_levels.duplicate()
		check(view.session.is_solved() and solved["puzzle"]==index,"solved boundary never auto advances")
		check(view.save_campaign(),"save solved boundary")
		view._undo()
		check(view.session.export_progress()==previous,"undo preserves exact prior history/selection")
		check(view.load_campaign() and view.session.export_progress()==solved and view.hint_levels==hints,"full solved-boundary round trip")
		check(view.session==identity and view.puzzle_view.state==identity,"stable authoritative state identity")
		view.hint_levels[index] = 2;view._open_hint()
		check(not "제안:" in text_of(view.dialog) and "목표" in text_of(view.dialog),"solved hint reports completion without print action")
		view.dismiss_story()
		if index < 17:view.advance()
	check(view.is_finished() and view.ending_panel.visible,"final ending restored")
	var final_state: Dictionary = view.session.export_progress().duplicate(true)
	var final_hints: Array = view.hint_levels.duplicate()
	view.show_credits();view.dismiss_story()
	check(view.session.export_progress()==final_state and view.hint_levels==final_hints,"credits preserve complete gameplay")
	view.free()
	print("CAMPAIGN_HINT_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"human_review":"not_performed"}))
	if failures.is_empty():print("CAMPAIGN_HINT_PASS")
	quit(0 if failures.is_empty() else 2)
