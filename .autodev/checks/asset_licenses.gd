extends SceneTree
## Trusted S07 probe: completed-campaign credits open a bounded asset-license
## reader that shows every registered path, its license identifier, recorded
## creator/origin and any license_text verbatim, labels NOASSERTION as missing
## permission, hides synthesis metadata, returns to credits and to the original
## ending destination, and never changes progress. Malformed data reads as an
## honest error. Credits render without Markdown markers. Not a rights review.
var failures: Array = []
var checks := 0
const Save = preload("res://scripts/campaign_save.gd")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("ASSET LICENSES FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func text_of(node: Node) -> String:
	var text: String = node.text if (node is Label or node is Button) else ""
	for child in node.get_children():
		text += "\n" + text_of(child)
	return text

func button(main, label: String) -> Button:
	var found: Array = []
	_find(main.dialog, label, found)
	return found[0] if not found.is_empty() else null

func _find(node: Node, label: String, found: Array) -> void:
	if node is Button and node.text == label and node.is_visible_in_tree():
		found.append(node)
	for child in node.get_children():
		_find(child, label, found)

func press(main, label: String) -> bool:
	var item := button(main, label)
	if item == null:
		return false
	item.pressed.emit()
	return true

func save_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Save.SAVE_PATH) if FileAccess.file_exists(Save.SAVE_PATH) else PackedByteArray()

func reader_checks(main, register: Array) -> void:
	var shown := text_of(main.dialog)
	check(shown.contains("자산 출처·라이선스"), "reader heading")
	for row in register:
		check(shown.contains(str(row["path"])), "reader lists " + str(row["path"]))
		check(shown.contains(str(row["license"])), "reader shows license id for " + str(row["path"]))
		if row.has("license_text"):
			check(shown.contains(str(row["license_text"])), "license text verbatim for " + str(row["path"]))
		if row.has("synthesis") and row["synthesis"] is Dictionary and row["synthesis"].has("reproduce_python_stdlib"):
			check(not shown.contains(str(row["synthesis"]["reproduce_python_stdlib"]).get_slice("\n", 0)), "synthesis recipe not dumped")
		if row.has("geometry_recipe"):
			check(not shown.contains(str(row["geometry_recipe"])), "geometry recipe not dumped")
	check(shown.contains("기록된 허가 없음"), "NOASSERTION explained as missing recorded permission")
	var focus: Control = main.get_viewport().gui_get_focus_owner()
	check(focus != null and main.dialog.is_ancestor_of(focus), "keyboard focus inside the reader")
	check(main.dialog_back.is_valid(), "Escape path available in the reader")

func run() -> void:
	var parser := JSON.new()
	check(parser.parse(FileAccess.get_file_as_string("res://ASSET_LICENSES.json")) == OK and parser.data is Array, "register parses")
	var register: Array = parser.data if parser.data is Array else []
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	for index in range(18):
		main.dismiss_story()
		for action in main.session.puzzle_data()[index]["solution"]:
			main.puzzle_view._select(int(int(action) / 4))
			main.session.set_rotation(int(action) % 4)
			main.puzzle_view._print()
		if index < 17:
			main.advance()
	main.dismiss_story()
	check(main.is_finished(), "campaign completed")
	var progress: Dictionary = main.session.export_progress().duplicate(true)
	var hints: Array = main.hint_levels.duplicate()
	var bytes := save_bytes()
	# Route 1: nonmodal ending panel -> credits -> reader -> credits -> ending.
	main.show_credits()
	var credits := text_of(main.dialog)
	check(main.overlay.visible and credits.contains("Godot"), "credits open")
	var markdown := RegEx.create_from_string("(?m)^#+ ")
	check(markdown.search(credits) == null, "credits render without Markdown heading markers")
	check(press(main, "자산 출처·라이선스"), "credits offer the asset-license reader")
	reader_checks(main, register)
	check(press(main, "크레딧으로 돌아가기"), "reader returns to credits")
	check(text_of(main.dialog).contains("Godot") and button(main, "자산 출처·라이선스") != null, "credits restored")
	check(press(main, "결말로 돌아가기"), "credits return to the ending")
	check(not main.overlay.visible and main.ending_panel.visible, "nonmodal ending restored")
	# Route 2: C03_ENDING record -> credits -> reader -> Escape -> credits -> record.
	main._replay_event("C03_ENDING")
	check(press(main, "크레딧"), "ending record offers credits")
	check(press(main, "자산 출처·라이선스"), "reader from ending-record credits")
	main._dialog_action(main.dialog_back)  # exactly what Escape does
	check(button(main, "결말 기록으로 돌아가기") != null, "Escape from reader keeps the ending-record destination")
	check(press(main, "결말 기록으로 돌아가기"), "return toward the record")
	check(main.overlay.visible and main.overlay.get_meta("campaign_event_id", "") == "C03_ENDING", "C03_ENDING record restored")
	main.dismiss_story()
	check(main.session.export_progress() == progress and main.hint_levels == hints and save_bytes() == bytes,
		"browsing credits/licenses never changes progress, hints or save bytes")
	# Malformed or missing data never fabricates attribution.
	for raw in ["", "{broken", "{\"path\":\"x\"}", "[1, 2]"]:
		var message: String = main._asset_license_text(raw)
		check(message.contains("읽을 수 없습니다"), "honest error for malformed register: " + raw)
		check(not message.contains("OpenAI") and not message.contains("Anthropic"), "no invented authorship for malformed register")
	main.free()
	print("ASSET_LICENSES_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "rights_review": "human_pending"}))
	if failures.is_empty():
		print("ASSET_LICENSES_PASS")
	quit(0 if failures.is_empty() else 2)
