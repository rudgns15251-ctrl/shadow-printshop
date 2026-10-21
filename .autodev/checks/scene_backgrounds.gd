extends SceneTree
## Trusted S11 probe: scene backgrounds show the night's passage. Story scenes
## name a background (night, midnight, dawn, ledger) that resolves to its own
## original SVG in the asset ledger; the play screen's NightScene follows the
## current chapter (1 night, 2 after midnight, 3 dawn) through play and load; the
## dawn plate is brighter and warmer than the night plate. Not an aesthetic review.
var failures: Array = []
var checks := 0
const FILES := {"night": "res://assets/art/scene_shop_night.svg", "midnight": "res://assets/art/scene_midnight.svg",
	"dawn": "res://assets/art/scene_dawn.svg", "ledger": "res://assets/art/scene_ledger.svg"}
const CHAPTER_KEYS := {1: "night", 2: "midnight", 3: "dawn"}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("SCENE BACKGROUNDS FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func mean(path: String) -> Color:
	var texture = load(path)
	if not texture is Texture2D:
		return Color.BLACK
	var image: Image = texture.get_image()
	if image == null:
		return Color.BLACK
	if image.is_compressed():
		image.decompress()
	var total := Vector3.ZERO
	var samples := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var c := image.get_pixel(x, y)
			total += Vector3(c.r, c.g, c.b)
			samples += 1
	total /= max(samples, 1)
	return Color(total.x, total.y, total.z)

func scene_texture(main) -> String:
	var scene: TextureRect = main.find_child("NightScene", true, false)
	return scene.texture.resource_path if scene != null and scene.texture != null else ""

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func run() -> void:
	var ledger = JSON.parse_string(FileAccess.get_file_as_string("res://ASSET_LICENSES.json"))
	var rows := {}
	if ledger is Array:
		for row in ledger:
			rows[str(row.get("path", ""))] = row
	for key in FILES:
		var path: String = FILES[key]
		var bytes := FileAccess.get_file_as_bytes(path)
		var text := bytes.get_string_from_utf8()
		check(text.contains("<svg") and not text.contains("<image") and not text.contains("data:image") and not text.contains("href=\"http"), path + ": original vector SVG")
		var row: Dictionary = rows.get(path.trim_prefix("res://"), {})
		var digest := ""
		if not bytes.is_empty():
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_SHA256)
			ctx.update(bytes)
			digest = ctx.finish().hex_encode()
		check(not row.is_empty() and str(row.get("final_encoded_measurements", {}).get("sha256", "")) == digest and not row.get("usage", []).is_empty(), path + ": in the ledger with matching hash and usage")
	var night := mean(FILES["night"])
	var dawn := mean(FILES["dawn"])
	var midnight := mean(FILES["midnight"])
	check(dawn.get_luminance() > night.get_luminance() + 0.03, "dawn plate brighter than the night plate")
	check(dawn.r - dawn.b > night.r - night.b + 0.03, "dawn plate warmer than the night plate")
	check(midnight.b - midnight.r >= night.b - night.r - 0.01 and midnight.get_luminance() <= dawn.get_luminance(), "after-midnight plate stays cool and darker than dawn")
	# Scenes name existing backgrounds; the ledger close-up is used.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_scenes.json"))
	var scenes: Array = parsed["scenes"] if parsed is Dictionary and parsed.get("scenes") is Array else []
	var used := {}
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for scene in scenes:
		var key := str(scene.get("background", ""))
		used[key] = true
		check(FILES.has(key), str(scene["id"]) + ": known background " + key)
		var texture: Texture2D = main._scene_background(scene)
		check(texture != null and FILES.has(key) and texture.resource_path == FILES[key], str(scene["id"]) + ": background resolves to " + key)
		if str(scene["trigger"]["type"]) == "chapter":
			check(key == CHAPTER_KEYS.get(int(scene["trigger"]["chapter"]), ""), str(scene["id"]) + ": chapter scene uses its chapter's time of night")
	check(used.has("ledger"), "the ledger close-up appears in a scene")
	# The play screen follows the chapter. Autosave off so the chapter-2 save
	# below is the one that loads (each Next would otherwise overwrite it).
	main.autosave_enabled = false
	main.start_new()
	main.dismiss_story()
	check(scene_texture(main) == FILES["night"], "chapter 1 plays at night")
	for index in range(17):
		main.dismiss_story()
		solve(main, index)
		main.advance()
		await process_frame
		var chapter := int(main.session.puzzle_data()[index + 1]["chapter"])
		check(scene_texture(main) == FILES[CHAPTER_KEYS[chapter]], "puzzle %d (chapter %d) background follows the chapter" % [index + 2, chapter])
		if index == 9:
			check(main.save_campaign(), "save in chapter 2")
	main.dismiss_story()
	check(main.load_campaign() and scene_texture(main) == FILES["midnight"], "loading a chapter-2 save restores the after-midnight room")
	main.start_new()
	main.dismiss_story()
	check(scene_texture(main) == FILES["night"], "a new campaign returns to night")
	main.free()
	print("SCENE_BACKGROUNDS_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("SCENE_BACKGROUNDS_PASS")
	quit(0 if failures.is_empty() else 2)
