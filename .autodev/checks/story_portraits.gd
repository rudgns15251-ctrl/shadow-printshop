extends SceneTree
## Trusted S11 probe: expression portraits for the story scenes. Every speaking
## line resolves to its own original SVG (백인호 neutral/worried/resolved, 윤해린
## record/restored, 0번 의뢰인 sealed/signed), each registered in the asset ledger
## with its measured hash and actual usage. 윤해린 appears restored only in the
## ending (an archival record before it), 0번 의뢰인's signature only in chapter 3.
## The stage shows the line's expression. Not an aesthetic review.
var failures: Array = []
var checks := 0
const EXPRESSIONS := {"백인호": ["neutral", "worried", "resolved"], "윤해린": ["record", "restored"], "0번 의뢰인": ["sealed", "signed"]}
const FILE_KEYS := {"백인호": "baek", "윤해린": "yoon", "0번 의뢰인": "client"}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("STORY PORTRAITS FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func path_for(speaker: String, expression: String) -> String:
	return "res://assets/art/portrait_%s_%s.svg" % [FILE_KEYS[speaker], expression]

func run() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_scenes.json"))
	var scenes: Array = parsed["scenes"] if parsed is Dictionary and parsed.get("scenes") is Array else []
	check(not scenes.is_empty(), "scenes present")
	var ledger = JSON.parse_string(FileAccess.get_file_as_string("res://ASSET_LICENSES.json"))
	var rows := {}
	if ledger is Array:
		for row in ledger:
			rows[str(row.get("path", ""))] = row
	# Files: original SVG, distinct per expression, registered with hash and usage.
	var hashes := {}
	for speaker in EXPRESSIONS:
		for expression in EXPRESSIONS[speaker]:
			var path := path_for(speaker, expression)
			var bytes := FileAccess.get_file_as_bytes(path)
			var text := bytes.get_string_from_utf8()
			check(text.contains("<svg") and not text.contains("<image") and not text.contains("href=\"http") and not text.contains("data:image"), path + ": original vector SVG without embedded or external images")
			var digest := ""
			if not bytes.is_empty():
				var ctx := HashingContext.new()
				ctx.start(HashingContext.HASH_SHA256)
				ctx.update(bytes)
				digest = ctx.finish().hex_encode()
			check(not digest.is_empty() and not hashes.has(digest), path + ": distinct drawing")
			hashes[digest] = path
			var row: Dictionary = rows.get(path.trim_prefix("res://"), {})
			check(not row.is_empty(), path + ": in the asset ledger")
			if not row.is_empty():
				check(str(row.get("final_encoded_measurements", {}).get("sha256", "")) == digest and int(row.get("final_encoded_measurements", {}).get("bytes", -1)) == bytes.size(), path + ": ledger hash and size match the file")
				check(row.get("usage", []) is Array and not row.get("usage", []).is_empty() and str(row.get("origin", "")).contains("SVG"), path + ": ledger records origin and actual usage")
			check(load(path) is Texture2D, path + ": imports as a texture")
	# Data rules.
	for scene in scenes:
		var type := str(scene["trigger"]["type"])
		for line in scene["lines"]:
			var speaker := str(line["speaker"])
			if speaker.is_empty():
				continue
			var expression := str(line.get("expression", ""))
			check(EXPRESSIONS.has(speaker) and EXPRESSIONS[speaker].has(expression), str(scene["id"]) + ": " + speaker + " line names a known expression '" + expression + "'")
			if speaker == "윤해린":
				check((expression == "restored") == (type == "ending"), str(scene["id"]) + ": 윤해린 restored only in the ending")
			if speaker == "0번 의뢰인" and expression == "signed":
				check(int(scene.get("chapter", 0)) == 3, str(scene["id"]) + ": the signature appears only in chapter 3")
	# The running product resolves and shows the same files.
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	for speaker in EXPRESSIONS:
		for expression in EXPRESSIONS[speaker]:
			var texture: Texture2D = main._scene_portrait(speaker, expression)
			check(texture != null and texture.resource_path == path_for(speaker, expression), speaker + "/" + expression + " resolves to its own portrait")
	for scene in scenes:
		main.dismiss_story()
		main.play_scene(str(scene["id"]))
		await process_frame
		var stage: Control = main.find_child("StoryStage", true, false)
		var portrait: TextureRect = stage.find_child("Portrait", true, false) if stage != null else null
		for index in range(scene["lines"].size()):
			var line: Dictionary = scene["lines"][index]
			if not str(line["speaker"]).is_empty() and portrait != null:
				check(portrait.texture != null and portrait.texture.resource_path == path_for(str(line["speaker"]), str(line["expression"])), str(scene["id"]) + " line %d shows its expression" % index)
			if stage != null:
				stage.advance()
	main.dismiss_story()
	# Order documents before the ending keep 윤해린 as a record, never restored.
	main._open_order()
	await process_frame
	main.dismiss_story()
	var restored := load(path_for("윤해린", "restored"))
	check(main.PORTRAITS.get("윤해린") != restored, "order documents never show 윤해린 restored")
	main.free()
	print("STORY_PORTRAITS_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("STORY_PORTRAITS_PASS")
	quit(0 if failures.is_empty() else 2)
