extends SceneTree
## Trusted S08 probe: the chapter-transition dialog presents the finished
## chapter's record and the new chapter's opening as two visually distinct
## sections: each section heading is its own label, larger than the body and in
## an accent colour, followed by its unchanged event text. Behaviour from
## chapter_transition (blocking, Escape, no progress change) still applies.
var failures: Array = []
var checks := 0
const CampaignState = preload("res://scripts/campaign_state.gd")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("TRANSITION SECTIONS FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func labels(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Label and child.is_visible_in_tree():
			out.append(child)
		labels(child, out)

func size_of(label: Label) -> int:
	return label.get_theme_font_size("font_size")

func verify(main, outro_id: String, intro_id: String) -> void:
	var events: Dictionary = CampaignState.story_data()["events"]
	var found: Array = []
	labels(main.dialog, found)
	for id in [outro_id, intro_id]:
		var heading: Label = null
		var body: Label = null
		for label in found:
			if label.text == str(events[id]["title"]):
				heading = label
			elif label.text == str(events[id]["text"]):
				body = label
		check(heading != null, intro_id + ": separate heading label for " + id)
		check(body != null, intro_id + ": unchanged body text label for " + id)
		if heading != null and body != null:
			check(size_of(heading) > size_of(body), intro_id + ": " + id + " heading larger than its text")
			check(heading.get_theme_color("font_color") != body.get_theme_color("font_color"), intro_id + ": " + id + " heading in a distinct colour")
			check(heading.get_index() < body.get_index() and heading.get_parent() == body.get_parent(), intro_id + ": " + id + " heading precedes its text")
	var outro_heading := -1
	var intro_heading := -1
	for label in found:
		if label.text == str(events[outro_id]["title"]): outro_heading = label.get_index()
		if label.text == str(events[intro_id]["title"]): intro_heading = label.get_index()
	check(outro_heading >= 0 and outro_heading < intro_heading, intro_id + ": finished record comes before the new opening")

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	for index in range(13):
		main.dismiss_story()
		for action in main.session.puzzle_data()[index]["solution"]:
			main.puzzle_view._select(int(int(action) / 4))
			main.session.set_rotation(int(action) % 4)
			main.puzzle_view._print()
		if index in [7, 12]:
			main.advance()
			await process_frame
			verify(main, "C01_OUTRO" if index == 7 else "C02_OUTRO", "C02_INTRO" if index == 7 else "C03_INTRO")
		elif index < 12:
			main.advance()
	main.dismiss_story()
	main.free()
	print("TRANSITION_SECTIONS_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("TRANSITION_SECTIONS_PASS")
	quit(0 if failures.is_empty() else 2)
