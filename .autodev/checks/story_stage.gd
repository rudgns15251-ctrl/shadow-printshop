extends SceneTree
## Trusted S11 probe: data-driven story scenes. A StoryStage inside the modal
## overlay shows a background, a portrait, a name plate, the line kind (직접 말함 /
## 남겨진 문서 / 기록) and the line; Space/Enter/click advance at the player's pace,
## Escape skips, and nothing reading does changes progress or the save. Scenes play
## on a new campaign (opening), on entering orders that have one, over the chapter
## record at a chapter boundary, and from the ending panel; 이야기 replays only
## unlocked scenes. Character rules: 윤해린 speaks live only in the ending, 0번
## 의뢰인 only through documents. Not a literary or aesthetic review.
var failures: Array = []
var checks := 0
const CampaignState = preload("res://scripts/campaign_state.gd")
const Save = preload("res://scripts/campaign_save.gd")
const SPEAKERS := ["백인호", "윤해린", "0번 의뢰인", ""]
const KINDS := ["live", "document", "narration"]
const KIND_TEXT := {"live": "직접 말함", "document": "남겨진 문서", "narration": "기록"}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("STORY STAGE FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func text_of(node: Node) -> String:
	var out := str(node.text) if (node is Label or node is Button) else ""
	for child in node.get_children():
		out += "\n" + text_of(child)
	return out

func save_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Save.SAVE_PATH) if FileAccess.file_exists(Save.SAVE_PATH) else PackedByteArray()

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release)

func settle() -> void:
	for i in range(4):
		await process_frame

func stage(main) -> Control:
	return main.find_child("StoryStage", true, false)

func part(main, part_name: String) -> Control:
	var node = stage(main)
	return node.find_child(part_name, true, false) if node != null else null

func shown_text(main) -> String:
	# Lines may carry invisible word joiners (U+2060) so words never break when wrapped.
	return str(part(main, "DialogueText").text).replace(char(0x2060), "")

func playing(main) -> bool:
	var node := stage(main)
	return node != null and node.is_visible_in_tree() and main.overlay.visible

func scenes() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_scenes.json"))
	return parsed["scenes"] if parsed is Dictionary and parsed.get("scenes") is Array else []

func data_checks() -> Dictionary:
	var all := scenes()
	check(not all.is_empty(), "campaign_scenes.json has scenes")
	var by_id := {}
	var counts := {"opening": 0, "enter": 0, "chapter": 0, "ending": 0}
	var puzzle_ids: Array = []
	for row in CampaignState.new().puzzle_data():
		puzzle_ids.append(row["id"])
	for scene in all:
		var id := str(scene.get("id", ""))
		check(not id.is_empty() and not by_id.has(id), "unique scene id " + id)
		check(not str(scene.get("title", "")).strip_edges().is_empty(), id + ": has a title")
		by_id[id] = scene
		var trigger: Dictionary = scene.get("trigger", {})
		var type := str(trigger.get("type", ""))
		check(counts.has(type), id + ": known trigger " + type)
		if counts.has(type):
			counts[type] += 1
		if type == "enter":
			var target := str(trigger.get("puzzle_id", ""))
			var index := puzzle_ids.find(target)
			check(index > 0 and target.right(2) != "01", id + ": enters an existing order that is not a chapter's first")
		if type == "chapter":
			check(int(trigger.get("chapter", 0)) in [2, 3], id + ": chapter scene for chapter 2 or 3")
		var lines: Array = scene.get("lines", [])
		check(not lines.is_empty(), id + ": has lines")
		for line in lines:
			var speaker := str(line.get("speaker", "?"))
			var kind := str(line.get("kind", ""))
			check(SPEAKERS.has(speaker) and KINDS.has(kind) and not str(line.get("text", "")).strip_edges().is_empty(), id + ": line speaker/kind/text valid")
			check((speaker == "") == (kind == "narration"), id + ": narration has no speaker and speakers are not narration")
			if speaker == "윤해린" and kind == "live":
				check(type == "ending", id + ": 윤해린 speaks live only in the ending")
			if speaker == "0번 의뢰인":
				check(kind == "document", id + ": 0번 의뢰인 only through documents")
			for word in ["CURRENT", "AFTER", "TARGET", "STAMP"]:
				check(not str(line.get("text", "")).contains(word), id + ": no developer label in a line")
	check(counts["opening"] == 1 and counts["chapter"] == 2 and counts["ending"] == 1, "one opening, two chapter scenes, one ending " + str(counts))
	check(counts["enter"] >= 4, "at least four scenes between orders " + str(counts["enter"]))
	return by_id

func line_shown(main, scene: Dictionary, index: int, label: String) -> void:
	var line: Dictionary = scene["lines"][index]
	check(shown_text(main) == str(line["text"]), label + ": line %d text shown" % index)
	var plate := part(main, "NamePlate")
	if str(line["speaker"]).is_empty():
		check(plate == null or not plate.is_visible_in_tree() or str(plate.text).is_empty(), label + ": narration has no name plate")
	else:
		check(plate != null and plate.is_visible_in_tree() and str(plate.text).contains(str(line["speaker"])), label + ": name plate " + str(line["speaker"]))
	check(str(part(main, "LineKind").text).contains(KIND_TEXT[str(line["kind"])]), label + ": line kind shown as " + KIND_TEXT[str(line["kind"])])
	var portrait := part(main, "Portrait") as TextureRect
	if str(line["speaker"]).is_empty():
		check(portrait == null or not portrait.is_visible_in_tree(), label + ": narration shows no portrait")
	else:
		check(portrait != null and portrait.is_visible_in_tree() and portrait.texture != null, label + ": speaker portrait shown")

func fits(main, label: String) -> void:
	await settle()
	var view: Rect2 = main.get_viewport_rect()
	for part_name in ["DialogueBox", "AdvanceKey", "SkipKey", "NamePlate", "PortraitFrame"]:
		var node := part(main, part_name)
		if node != null and node.is_visible_in_tree():
			var rect: Rect2 = node.get_global_rect()
			check(rect.position.x >= -1 and rect.position.y >= -1 and rect.end.x <= view.end.x + 1 and rect.end.y <= view.end.y + 1, label + ": " + part_name + " inside the window")
	var box := part(main, "DialogueBox")
	var text := part(main, "DialogueText")
	if box != null and text != null:
		check(box.get_global_rect().grow(1).encloses(text.get_global_rect()), label + ": line fits in the dialogue box")

func play_through(main, scene: Dictionary, label: String) -> void:
	# Player-paced: one line per key, nothing advances by itself.
	var progress: Dictionary = main.session.export_progress().duplicate(true)
	var bytes := save_bytes()
	for index in range(scene["lines"].size()):
		await settle()
		check(playing(main) and str(stage(main).scene_id) == str(scene["id"]), label + ": scene playing at line %d" % index)
		line_shown(main, scene, index, label)
		var focus: Control = main.get_viewport().gui_get_focus_owner()
		check(focus != null and stage(main).is_ancestor_of(focus), label + ": keyboard focus inside the stage")
		main.puzzle_view._print()
		main.puzzle_view._select(1)
		check(main.session.export_progress() == progress, label + ": puzzle input blocked while the scene plays")
		for i in range(30):
			await process_frame
		check(int(stage(main).line_index) == index, label + ": line waits for the player")
		key(KEY_SPACE if index % 2 == 0 else KEY_ENTER)
		await settle()
	check(main.session.export_progress() == progress and save_bytes() == bytes, label + ": reading changes no progress or save bytes")

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func run() -> void:
	var by_id := data_checks()
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.size = Vector2i(1280, 720)
	check(main.has_method("play_scene"), "campaign exposes play_scene")
	check(stage(main) != null and main.overlay.is_ancestor_of(stage(main)), "StoryStage lives inside the modal overlay")
	var opening: Dictionary = {}
	var chapter_scenes := {}
	var ending: Dictionary = {}
	var entering := {}
	for scene in by_id.values():
		match str(scene["trigger"]["type"]):
			"opening": opening = scene
			"ending": ending = scene
			"chapter": chapter_scenes[int(scene["trigger"]["chapter"])] = scene
			"enter": entering[str(scene["trigger"]["puzzle_id"])] = scene
	for part_name in ["SceneBackground", "PortraitFrame", "Portrait", "NamePlate", "LineKind", "DialogueBox", "DialogueText", "AdvanceKey", "SkipKey"]:
		check(part(main, part_name) != null, "stage part " + part_name)
	if opening.is_empty() or ending.is_empty() or part(main, "DialogueText") == null or not main.has_method("play_scene"):
		main.free()
		print("STORY_STAGE_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
		quit(2)
		return
	# Opening: 처음부터 on the title starts the campaign and plays the opening.
	main._ask_new_game()
	await settle()
	check(main.game_active and playing(main) and str(stage(main).scene_id) == str(opening["id"]), "처음부터 plays the opening scene")
	var background := part(main, "SceneBackground") as TextureRect
	check(background != null and background.is_visible_in_tree() and background.texture != null, "scene background shown")
	await fits(main, "1280x720 100% opening")
	await play_through(main, opening, "opening")
	check(not main.overlay.visible and main.game_active, "the last line returns to the first order")
	# Escape skips a scene; dismiss_story closes it; replay is read-only.
	main.play_scene(str(opening["id"]))
	await settle()
	check(playing(main), "replay plays the scene")
	key(KEY_SPACE)
	await settle()
	check(int(stage(main).line_index) == 1, "Space advances one line")
	key(KEY_ESCAPE)
	await settle()
	check(not playing(main) and not main.overlay.visible, "Escape skips the rest of the scene")
	main.play_scene(str(opening["id"]))
	main.dismiss_story()
	await settle()
	check(not playing(main) and not main.overlay.visible, "dismiss_story closes a scene")
	# 이야기 replays only unlocked scenes.
	main._open_story()
	await settle()
	var listed := text_of(main.dialog)
	check(listed.contains(str(opening["title"])), "이야기 lists the opening scene")
	var locked_ok := true
	for node in main.dialog.find_children("*", "Button", true, false):
		if str(node.text).contains(str(ending["title"])):
			locked_ok = node.disabled
	check(locked_ok, "the ending scene is locked before the ending")
	main.dismiss_story()
	# Larger text and reduced motion: the line is complete at once and still fits.
	main._set_font_scale(1.5)
	main._setting_value_changed(true, "reduce_motion")
	main.play_scene(str(opening["id"]))
	await settle()
	check(shown_text(main) == str(opening["lines"][0]["text"]) and part(main, "DialogueText").visible_ratio >= 1.0, "reduced motion shows the whole line at once")
	await fits(main, "1280x720 150% opening")
	root.size = Vector2i(1920, 1080)
	await fits(main, "1920x1080 150% opening")
	main.dismiss_story()
	main._set_font_scale(1.0)
	main._setting_value_changed(false, "reduce_motion")
	main.play_scene(str(ending["id"]))
	await fits(main, "1920x1080 100% ending lines")
	main.dismiss_story()
	root.size = Vector2i(1280, 720)
	# Orders, chapter boundaries and the ending.
	var seen_enter := 0
	for index in range(18):
		main.dismiss_story()
		solve(main, index)
		if index == 17:
			break
		main.advance()
		await settle()
		var entered: String = main.session.puzzle_data()[index + 1]["id"]
		var chapter := int(main.session.puzzle_data()[index + 1]["chapter"])
		if chapter != int(main.session.puzzle_data()[index]["chapter"]):
			check(chapter_scenes.has(chapter) and playing(main) and str(stage(main).scene_id) == str(chapter_scenes.get(chapter, {}).get("id", "")), "chapter %d scene plays at the boundary" % chapter)
			check(not main.popup_panel.is_visible_in_tree(), "chapter %d record waits under the scene" % chapter)
			key(KEY_ESCAPE)
			await settle()
			check(main.overlay.visible and main.popup_panel.is_visible_in_tree() and not playing(main), "chapter %d record shown after the scene" % chapter)
			var focus: Control = main.get_viewport().gui_get_focus_owner()
			check(focus != null and main.dialog.is_ancestor_of(focus), "chapter %d record takes focus" % chapter)
		elif entering.has(entered):
			check(playing(main) and str(stage(main).scene_id) == str(entering[entered]["id"]), entered + ": scene plays on entering the order")
			await play_through(main, entering[entered], entered)
			check(not main.overlay.visible, entered + ": scene returns to the order")
			seen_enter += 1
		else:
			check(not playing(main), entered + ": no scene for this order")
	check(seen_enter == entering.size(), "every between-order scene was reached")
	await settle()
	check(main.is_finished() and main.ending_panel.visible, "final order solved")
	var ending_key: Button = null
	for node in main.ending_panel.find_children("*", "Button", true, false):
		if str(node.text).contains("결말 장면"):
			ending_key = node
	check(ending_key != null, "ending panel offers the ending scene")
	if ending_key != null:
		ending_key.pressed.emit()
		await settle()
		check(playing(main) and str(stage(main).scene_id) == str(ending["id"]), "ending scene plays")
		await play_through(main, ending, "ending")
		check(main.is_finished() and main.ending_panel.visible, "ending scene returns to the ending")
	main._open_story()
	await settle()
	listed = text_of(main.dialog)
	for scene in by_id.values():
		check(listed.contains(str(scene["title"])), "이야기 lists " + str(scene["id"]) + " after the ending")
	var replay: Button = null
	for node in main.dialog.find_children("*", "Button", true, false):
		if str(node.text).contains(str(ending["title"])):
			replay = node
	check(replay != null and not replay.disabled, "the ending scene is replayable after the ending")
	if replay != null:
		var progress: Dictionary = main.session.export_progress().duplicate(true)
		replay.pressed.emit()
		await settle()
		check(playing(main) and str(stage(main).scene_id) == str(ending["id"]), "이야기 replays the ending scene")
		key(KEY_ESCAPE)
		await settle()
		check(main.session.export_progress() == progress, "replay changes no progress")
	main.dismiss_story()
	main.free()
	print("STORY_STAGE_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("STORY_STAGE_PASS")
	quit(0 if failures.is_empty() else 2)
