extends SceneTree
## Trusted S07 probe: entering chapters 2 and 3 presents the finished chapter's
## record and the new chapter's opening in one blocking, dismissible dialog with
## a chapter SFX; documents use a quiet paper SFX. Both original WAVs are PCM16,
## nonsilent, below clipping and fade to silence. Players follow SFX/mute
## settings and are owned by the inherited audio lifecycle. Not a listening test.
var failures: Array = []
var checks := 0
const CampaignState = preload("res://scripts/campaign_state.gd")
const Save = preload("res://scripts/campaign_save.gd")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("CHAPTER TRANSITION FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func text_of(node: Node) -> String:
	var text: String = node.text if (node is Label or node is Button) else ""
	for child in node.get_children():
		text += "\n" + text_of(child)
	return text

func u16(bytes: PackedByteArray, at: int) -> int:
	return bytes[at] | (bytes[at + 1] << 8)

func u32(bytes: PackedByteArray, at: int) -> int:
	return u16(bytes, at) | (u16(bytes, at + 2) << 16)

func analyse(path: String, min_seconds: float, max_seconds: float, max_peak: float) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	check(bytes.size() > 44 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE", path + " RIFF/WAVE")
	if bytes.size() <= 44:
		return
	var at := 12
	var channels := 0
	var rate := 0
	var bits := 0
	var format := 0
	var data_at := -1
	var data_size := 0
	while at + 8 <= bytes.size():
		var id := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := u32(bytes, at + 4)
		if id == "fmt ":
			format = u16(bytes, at + 8); channels = u16(bytes, at + 10); rate = u32(bytes, at + 12); bits = u16(bytes, at + 22)
		elif id == "data":
			data_at = at + 8; data_size = size
		at += 8 + size + (size % 2)
	check(format == 1 and bits == 16 and channels in [1, 2] and rate in [44100, 48000], path + " PCM16 44.1/48 kHz")
	check(data_at > 0 and data_at + data_size <= bytes.size() and data_size > 0, path + " data chunk")
	if data_at <= 0 or channels == 0 or rate == 0:
		return
	var count := data_size / 2
	var peak := 0
	var energy := 0.0
	var last := 0
	for i in range(count):
		var value := u16(bytes, data_at + i * 2)
		if value >= 32768:
			value -= 65536
		peak = maxi(peak, absi(value))
		energy += float(value * value)
		last = value
	var seconds := float(count / channels) / float(rate)
	var rms := sqrt(energy / maxf(1.0, float(count))) / 32768.0
	check(seconds >= min_seconds and seconds <= max_seconds, path + " duration %.3fs within bounds" % seconds)
	check(float(peak) / 32768.0 <= max_peak, path + " peak %.3f below limit %.2f" % [float(peak) / 32768.0, max_peak])
	check(rms > 0.004, path + " audible nonsilent content")
	check(absi(last) <= 64, path + " ends at silence without a click")
	print("SFX_MEASURE " + JSON.stringify({"path": path, "seconds": seconds, "peak": float(peak) / 32768.0, "rms": rms, "rate": rate, "channels": channels}))

func solve(main, index: int) -> void:
	for action in main.session.puzzle_data()[index]["solution"]:
		main.puzzle_view._select(int(int(action) / 4))
		main.session.set_rotation(int(action) % 4)
		main.puzzle_view._print()

func save_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Save.SAVE_PATH) if FileAccess.file_exists(Save.SAVE_PATH) else PackedByteArray()

func boundary(main, outro_id: String, intro_id: String, expect_sound: bool) -> void:
	var events: Dictionary = CampaignState.story_data()["events"]
	var before: int = int(main.session.snapshot()["puzzle"])
	main.advance()
	check(int(main.session.snapshot()["puzzle"]) == before + 1, intro_id + ": Next advances exactly once")
	check(main.overlay.visible, intro_id + ": chapter dialog presented on entry")
	var shown := text_of(main.dialog)
	for id in [outro_id, intro_id]:
		check(str(events[id]["text"]).get_slice("\n", 0) in shown, intro_id + ": dialog contains " + id)
	check(not "다음 버튼으로" in shown, intro_id + ": no stale Next instruction inside the story text")
	check(main.dialog_back.is_valid(), intro_id + ": Escape closes the chapter dialog")
	check(main.audio["chapter"].playing == expect_sound, intro_id + ": chapter SFX follows settings")
	var progress: Dictionary = main.session.export_progress().duplicate(true)
	var bytes := save_bytes()
	main.puzzle_view._print()
	main.puzzle_view._select(1)
	main.puzzle_view._rotate(1)
	main.puzzle_view._undo()
	check(main.session.export_progress() == progress, intro_id + ": puzzle input blocked while reading")
	main.dismiss_story()
	check(not main.overlay.visible and main.session.export_progress() == progress and save_bytes() == bytes,
		intro_id + ": dismissal changes no progress or save bytes")

func run() -> void:
	analyse("res://assets/audio/menu_paper.wav", 0.12, 0.9, 0.35)
	analyse("res://assets/audio/chapter_transition.wav", 0.6, 3.0, 0.5)
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	for key in ["paper", "chapter"]:
		check(main.audio.has(key) and main.audio[key] is AudioStreamPlayer and main.audio[key].stream is AudioStreamWAV, key + " SFX player in inherited audio set")
	if not (main.audio.has("paper") and main.audio.has("chapter")):
		main.free()
		quit(2)
		return
	check(main.audio["paper"].stream.resource_path == "res://assets/audio/menu_paper.wav", "paper SFX uses original asset")
	check(main.audio["chapter"].stream.resource_path == "res://assets/audio/chapter_transition.wav", "chapter SFX uses original asset")
	main._open_order()
	check(main.audio["paper"].playing, "opening an order plays the paper SFX")
	main.dismiss_story()
	main.audio["paper"].stop()
	main._setting_value_changed(0.0, "sfx")
	main._open_journal()
	check(not main.audio["paper"].playing and main.audio["paper"].volume_db <= -79.0, "SFX volume zero silences paper")
	main.dismiss_story()
	main._setting_value_changed(0.7, "sfx")
	for index in range(8):
		main.dismiss_story()
		solve(main, index)
		if index < 7:
			main.advance()
			check(not main.overlay.visible, "no chapter dialog inside chapter 1 (puzzle %d)" % (index + 2))
	boundary(main, "C01_OUTRO", "C02_INTRO", true)
	for index in range(8, 13):
		main.dismiss_story()
		solve(main, index)
		if index < 12:
			main.advance()
			check(not main.overlay.visible, "no chapter dialog inside chapter 2 (puzzle %d)" % (index + 2))
	main._setting_value_changed(true, "mute")
	boundary(main, "C02_OUTRO", "C03_INTRO", false)
	main._setting_value_changed(false, "mute")
	main._replay_event("C01_OUTRO")
	check(text_of(main.dialog).contains(str(CampaignState.story_data()["events"]["C01_OUTRO"]["text"]).get_slice("\n", 0)), "story replay keeps the same record")
	main.dismiss_story()
	main.free()
	print("CHAPTER_TRANSITION_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("CHAPTER_TRANSITION_PASS")
	quit(0 if failures.is_empty() else 2)
