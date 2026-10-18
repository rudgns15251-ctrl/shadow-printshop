extends SceneTree
const Data = preload("res://data/mech_data.gd")
var view
var checks := 0
var failures: Array = []
var output := ""
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);printerr("SPRINT CHECK FAIL: " + message)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output=arg.substr(7)
	call_deferred("run")
func shot(label: String) -> void:
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"rendered effect evidence "+label)
func added_motion() -> bool:
	for board in [view.stamp_mask_view,view.before_view,view.after_view,view.target_view]:
		if board.feedback_time>0.0: return true
	return false
func close_modal() -> void:
	view.overlay.hide()
	var focus = root.gui_get_focus_owner()
	if focus != null: focus.release_focus()
func settle() -> void:
	var deadline := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < deadline: await process_frame
func solve(index: int) -> void:
	for action in Data.PUZZLES[index]["solution"]:
		view._select(int(int(action)/4));view.state.set_rotation(int(action)%4);view._print()
func quiet() -> bool:
	return not added_motion() and view.stamp_view.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(view.stamp_view.rotation) and view.stamp_view.modulate.is_equal_approx(Color.WHITE) and is_zero_approx(view.before_view.impression) and is_zero_approx(view.before_view.success)
func run() -> void:
	view=load("res://integrated_main.tscn").instantiate();view.autosave_enabled=false;root.add_child(view)
	close_modal();view._new_game();await process_frame
	check(view.state.puzzle_count()==8,"eight puzzles preserved")
	check("0↔1" in view.subheading.text and "AFTER" in view.subheading.text,"first screen explains flipping and preview")
	check("U/Z" in view.feedback.text and "힌트" in view.feedback.text and "같은 도장" in view.feedback.text,"first screen exposes undo hints and repeat reversal")
	var initial: Dictionary = view.state.export_progress()
	var hints: Array = view.hint_levels.duplicate()
	view._select(1)
	check(added_motion(),"allowed selection immediately starts visual cue")
	await shot("selection")
	check(view.state.get_board()==initial["board"] and view.state.snapshot()["moves"]==0,"selection is free")
	view._rotate(1)
	check(added_motion() and view.after_view.feedback_time<=0.30,"rotation immediately starts bounded visual cue")
	await shot("rotation")
	check(view.state.snapshot()["rotation"]==1 and view.state.get_board()==initial["board"],"rotation synchronous and free")
	var selected: Dictionary = view.state.export_progress()
	await settle()
	check(not added_motion(),"selection/rotation cue ends without retained clock")
	check(view.state.export_progress()==selected and view.hint_levels==hints,"finished feedback never mutates state or hints")
	for i in range(80):
		view._select(i%2);view._rotate(1)
		var before: Dictionary = view.state.export_progress()
		view._print()
		check(view.state.snapshot()["history_size"]==before["history"].size()+1,"rapid print exactly once %d"%i)
		view._undo()
		check(view.state.get_board()==before["board"] and view.state.snapshot()["moves"]==before["moves"],"rapid undo restores %d"%i)
		view._next()
		check(view.state.snapshot()["puzzle"]==0,"unsolved next rejected %d"%i)
	var rapid: Dictionary = view.state.export_progress()
	await settle()
	check(view.state.export_progress()==rapid,"rapid action clocks cannot replay input")
	view._rotate(1);view._open_pause()
	check(not added_motion(),"modal immediately cancels added cue")
	var paused: Dictionary = view.state.export_progress()
	view._select(1);view._rotate(1);view._print();view._undo();view._next()
	await settle()
	check(view.state.export_progress()==paused,"modal blocks every gameplay action during effect")
	close_modal();await settle()
	check(view.state.export_progress()==paused,"closing modal cannot replay earlier action")
	view._reset_confirmed();solve(0);await shot("complete")
	view._next()
	check(view.state.snapshot()["puzzle"]==1 and added_motion(),"normal manual Next applies state and cue immediately")
	await shot("next")
	var next_state: Dictionary=view.state.export_progress()
	await settle()
	check(view.state.export_progress()==next_state and not added_motion(),"next cue ends without delayed progress")
	view._new_game()
	view._select(0);view.state.set_rotation(0);view._refresh();view._print();view._rotate(1)
	check(view.state.preview()==view.state.get_target() and "일치" in view.feedback.text and "SPACE" in view.feedback.text,"preview match gives state-derived print guidance")
	check(view.state.snapshot()["moves"]==1 and not view.state.is_solved(),"matching preview does not apply print")
	view._undo();check("인쇄 기록 없음" in view.feedback.text,"undo recomputes zero-history guidance")
	view._reset_confirmed();check("인쇄 기록 없음" in view.feedback.text,"reset recomputes zero-history guidance")
	view._reset_confirmed();view._rotate(1)
	view._setting_value_changed(true,"reduce_motion")
	check(quiet(),"reduce motion immediately clears active selection/rotation presentation")
	view._select(1);view._rotate(1);check(quiet(),"reduced selection/rotation stay static")
	view._print();check(quiet(),"reduced print stays static")
	view._undo();check(quiet(),"reduced undo stays static")
	view._reset_confirmed()
	for index in range(8):
		solve(index)
		check(view.state.is_solved() and view.state.snapshot()["puzzle"]==index,"solve never auto advances %d"%index)
		check(quiet(),"reduced completion stays static %d"%index)
		if index<7:
			check(not view.next_button.disabled,"next enabled on nonfinal completion %d"%index)
			view._next()
			check(view.state.snapshot()["puzzle"]==index+1 and view.state.snapshot()["moves"]==0,"manual next synchronous and clears history %d"%index)
			check(quiet(),"reduced next stays static %d"%index)
		else:
			check(view.next_button.disabled and "8개 퍼즐을 모두 해결" in view.feedback.text,"final completion and disabled next")
			check("메뉴" in view.feedback.text and "U" in view.feedback.text,"final completion offers menu and undo")
			var final: Dictionary=view.state.export_progress();view._next()
			check(view.state.export_progress()==final,"final next never wraps")
			check(view._save_progress(),"save final progress")
			view._undo();check(not view.state.is_solved() and view.next_button.disabled,"final undo reopens without enabling next")
			check(not "모두 해결" in view.feedback.text,"undo clears stale completion guidance")
			view._load_confirmed();check(view.state.is_solved() and view.next_button.disabled,"load restores final guidance boundary")
	view._new_game();view._setting_value_changed(false,"reduce_motion");view._rotate(1)
	view.free();view=null
	print("SPRINT_INTERACTION_RESULT "+JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 2)
