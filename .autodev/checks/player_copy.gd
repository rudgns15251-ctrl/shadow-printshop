extends SceneTree
## Trusted S12 probe: the words a player meets are the game's own. Across the
## title, every play state, the ending, every dialog a player can open (help,
## settings, menu, story list, archive, orders, hints, confirmations, credits'
## first page) and every scene tag, no prototype or developer vocabulary
## (퍼즐/캠페인/플레이/목표/반전/다음 버튼/XOR/로컬/schema metadata/file names/order
## IDs). Orders still say whether words were spoken or left as documents; the
## current text size is marked; an empty continue is disabled and 종료 is full
## width; the last hint names the [E] key; 백인호 is one person on orders and in
## scenes; the status bar, subheading, ending text and scene lines never break
## inside a Korean word. Licence readers keep their exact records. Not a literary review.
var failures: Array = []
var checks := 0
const FORBIDDEN := ["퍼즐", "캠페인", "플레이", "목표", "반전", "다음 버튼", "XOR", "로컬", "만남 순서", "발화 날짜",
	"기록 명의", "기록 이미지", "익명의 문서 표식", "현장 발화", "보관 문서", "시계 방향", ".wav", ".svg", "2026-"]
var ids := RegEx.create_from_string("C0[123]-[0-9][0-9]")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("PLAYER COPY FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(4):
		await process_frame

func gather(node: Node, out: Array, skip: Node = null) -> void:
	for child in node.get_children():
		if child == skip:
			continue
		if child is CanvasItem and not child.is_visible_in_tree():
			continue
		if child is Label or child is Button:
			out.append(str(child.text))
			if child is Control and not str(child.tooltip_text).is_empty():
				out.append(str(child.tooltip_text))
		gather(child, out, skip)

func clean(texts: Array, label: String) -> void:
	var found: Array = []
	for text in texts:
		var plain := str(text).replace(char(0x2060), "")
		for word in FORBIDDEN:
			if plain.contains(word):
				found.append(word + " in '" + plain.left(36) + "'")
		var hit := ids.search(plain)
		if hit != null:
			found.append(hit.get_string() + " in '" + plain.left(36) + "'")
	check(found.is_empty(), label + ": player vocabulary only " + str(found.slice(0, 3)))

func screen(main, label: String) -> void:
	await settle()
	var texts: Array = []
	gather(main, texts, main.overlay)
	clean(texts, label)

func dialog(main, label: String) -> void:
	await settle()
	var texts: Array = []
	gather(main.overlay, texts)
	clean(texts, label)

func is_hangul(c: String) -> bool:
	return c.length() == 1 and c.unicode_at(0) >= 0xAC00 and c.unicode_at(0) <= 0xD7A3

func whole_words(label: Label, name: String) -> void:
	# Every wrapped line ends at a space or punctuation, never between two syllables.
	if label == null or not label.is_visible_in_tree() or label.text.is_empty():
		return
	var server := TextServerManager.get_primary_interface()
	var shaped := server.create_shaped_text()
	server.shaped_text_add_string(shaped, label.text, label.get_theme_font("font").get_rids(), label.get_theme_font_size("font_size"))
	var style: StyleBox = label.get_theme_stylebox("normal")
	var width := label.size.x - (style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT) if style != null else 0.0)
	var breaks := server.shaped_text_get_line_breaks(shaped, width, 0, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var bad: Array = []
	for i in range(0, breaks.size() - 2, 2):
		var end: int = breaks[i + 1]
		var before := label.text.substr(end - 1, 1)
		var after := label.text.substr(end, 1)
		if before == char(0x2060):
			before = label.text.substr(end - 2, 1)
		if after == char(0x2060):
			after = label.text.substr(end + 1, 1)
		if is_hangul(before) and is_hangul(after):
			bad.append(label.text.substr(maxi(0, end - 4), 8).replace(char(0x2060), ""))
	server.free_rid(shaped)
	check(bad.is_empty(), name + ": wraps only between words " + str(bad.slice(0, 2)))

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func open_order_at(main, index: int) -> String:
	main._open_order()
	await settle()
	var texts: Array = []
	gather(main.overlay, texts)
	return "\n".join(texts)

func portrait_path(main) -> String:
	var row = main.dialog.find_child("OrderPortrait", true, false)
	if row == null:
		return ""
	for node in row.get_children():
		if node is TextureRect and node.texture != null:
			return node.texture.resource_path
	return ""

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.autosave_enabled = false
	root.size = Vector2i(1280, 720)
	# Title: no save yet.
	main._open_start()
	await dialog(main, "title")
	var grid = main.find_child("TitleMenuGrid", true, false)
	for node in main.dialog.find_children("*", "Button", true, false):
		if str(node.text).begins_with("이어하기"):
			check(node.disabled, "continue without a save is disabled")
		if str(node.text) == "종료":
			check(grid == null or not grid.is_ancestor_of(node), "종료 is a full-width key, not alone in the grid")
	main.start_new()
	main.dismiss_story()
	await screen(main, "first order")
	var first_order := await open_order_at(main, 0)
	clean([first_order], "first order document")
	check(first_order.contains("직접"), "a spoken order says it was said in person")
	check(portrait_path(main) == "res://assets/art/portrait_baek_neutral.svg", "백인호's order portrait is the same man as in the scenes")
	var card = main.find_child("OrderCard", true, false)
	check(card is Button and card.icon != null and card.icon.resource_path == "res://assets/art/portrait_baek_neutral.svg", "order card shows the same 백인호")
	main.dismiss_story()
	for opener in ["_open_help", "_open_settings", "_open_pause", "_open_story", "_open_journal", "_ask_reset", "_ask_new_game"]:
		if main.has_method(opener):
			main.call(opener)
			await dialog(main, opener)
			main.dismiss_story()
	# Settings mark the current text size.
	for scale in [1.0, 1.25, 1.5]:
		main._set_font_scale(scale)
		main._open_settings()
		await settle()
		var marked := false
		for node in main.dialog.find_children("*", "Button", true, false):
			if str(node.text).contains("%d%%" % int(scale * 100)):
				marked = node.button_pressed or str(node.text).contains("✓")
		check(marked, "settings mark the current text size %d%%" % int(scale * 100))
		var texts: Array = []
		gather(main.overlay, texts)
		check("\n".join(texts).contains("이 컴퓨터"), "settings say where they are kept in plain words")
		main.dismiss_story()
	main._set_font_scale(1.0)
	# Hints, including the last suggestion.
	main.puzzle_view._print()
	for level in range(3):
		main._open_hint()
		await dialog(main, "first-order hint %d" % (level + 1))
		if level == 2:
			var texts: Array = []
			gather(main.overlay, texts)
			var joined := "\n".join(texts)
			check(joined.contains("[E]") or joined.contains("돌리지 않"), "the last hint names the rotate key")
		main.dismiss_story()
	main.puzzle_view._undo()
	main.puzzle_view._print()
	await screen(main, "after a print")
	main.puzzle_view._undo()
	solve(main, 0)
	await screen(main, "solved first order")
	main.advance()
	main.dismiss_story()
	await screen(main, "second order")
	solve(main, 1)
	main.advance()
	main.dismiss_story()
	var document := await open_order_at(main, 2)
	clean([document], "retained document order")
	check(document.contains("남겨진"), "a retained document says it was left behind")
	check(portrait_path(main) == "res://assets/art/portrait_yoon_record.svg", "윤해린's order is her archival record")
	main.dismiss_story()
	for index in range(2, 8):
		main.dismiss_story()
		solve(main, index)
		if index < 7:
			main.advance()
	main.dismiss_story()
	await screen(main, "chapter 1 last order solved")
	main.advance()
	main.find_child("StoryStage", true, false).skip()
	await dialog(main, "chapter record")
	main.dismiss_story()
	await screen(main, "chapter 2")
	main._open_journal()
	await dialog(main, "archive with read orders")
	main.dismiss_story()
	for index in range(8, 18):
		main.dismiss_story()
		solve(main, index)
		if index < 17:
			main.advance()
	main.dismiss_story()
	await screen(main, "finished")
	main.show_credits()
	await dialog(main, "credits first page")
	main.dismiss_story()
	main._ask_campaign_replay()
	await dialog(main, "replay confirmation")
	main.dismiss_story()
	# Scene tags and lines.
	var tags := {}
	var stage = main.find_child("StoryStage", true, false)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_scenes.json"))
	main._set_font_scale(1.5)
	for scene in parsed["scenes"]:
		main.dismiss_story()
		main.play_scene(str(scene["id"]))
		for index in range(scene["lines"].size()):
			await process_frame
			tags[str(stage.find_child("LineKind", true, false).text)] = true
			whole_words(stage.find_child("DialogueText", true, false), str(scene["id"]) + " line %d" % index)
			stage.advance()
	clean(tags.keys(), "scene tags")
	main.dismiss_story()
	# Larger text: the status bar, subheading and ending text keep whole words.
	await settle()
	whole_words(main.ending_panel.find_children("*", "Label", true, false).filter(func(l): return str(l.text).length() > 60).front() if not main.ending_panel.find_children("*", "Label", true, false).filter(func(l): return str(l.text).length() > 60).is_empty() else null, "ending text 150%")
	whole_words(main.feedback, "status bar at the ending 150%")
	main.start_new()
	main.dismiss_story()
	await settle()
	whole_words(main.feedback, "first-order status bar 150%")
	whole_words(main.subheading, "first-order subheading 150%")
	main._set_font_scale(1.0)
	main.free()
	print("PLAYER_COPY_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("PLAYER_COPY_PASS")
	quit(0 if failures.is_empty() else 2)
