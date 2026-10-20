extends SceneTree
## Trusted S07 probe: every campaign heading shows a Korean puzzle title. The
## original eight keep their protected data titles; display names come from
## campaign_story.json display_titles only. Not a human wording review.
var failures: Array = []
var checks := 0
const CampaignState = preload("res://scripts/campaign_state.gd")
const Original = preload("res://data/mech_data.gd")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("CAMPAIGN TITLES FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func run() -> void:
	var latin := RegEx.create_from_string("[A-Za-z]")
	var hangul := RegEx.create_from_string("[가-힣]")
	var story: Dictionary = CampaignState.story_data()
	var display: Variant = story.get("display_titles", null)
	check(display is Dictionary, "display_titles data exists")
	if not display is Dictionary:
		quit(2)
		return
	var originals: Array = []
	for i in range(8):
		originals.append(Original.PUZZLES[i]["id"])
	check(display.keys().size() == 8 and originals.all(func(id): return display.has(id)), "exactly the original eight have display titles")
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	var shown: Array = []
	for index in range(18):
		main.dismiss_story()
		var row: Dictionary = main.session.puzzle_data()[index]
		var heading: String = main.heading.text
		var title: String = heading.get_slice("·", heading.get_slice_count("·") - 1).strip_edges()
		check(latin.search(heading) == null, row["id"] + ": heading has no Latin-script title: " + heading)
		check(hangul.search(title) != null, row["id"] + ": Korean title shown")
		check(not title in shown, row["id"] + ": distinct title")
		shown.append(title)
		if index < 8:
			check(title == str(display[row["id"]]), row["id"] + ": original display title from data")
			check(row["title"] == Original.PUZZLES[index]["title"], row["id"] + ": protected data title unchanged")
		else:
			check(title == row["title"], row["id"] + ": authored campaign title unchanged")
		solve(main, index)
		check(main.session.is_solved(), row["id"] + ": solution still valid")
		if index < 17:
			main.advance()
	main.free()
	print("CAMPAIGN_TITLES_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("CAMPAIGN_TITLES_PASS")
	quit(0 if failures.is_empty() else 2)
