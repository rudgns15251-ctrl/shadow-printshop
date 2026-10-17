extends SceneTree
## No game code, timers, hidden muting, or retained strong playback references.
var players: Array[AudioStreamPlayer] = []
var playback_refs: Array[WeakRef] = []
var stream_refs: Array[WeakRef] = []
var started_usec := 0
var case_name := "A"
var game_scene: Node

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("case="):
			case_name = argument.trim_prefix("case=")
	call_deferred("run")

func live(refs: Array[WeakRef]) -> int:
	var count := 0
	for item in refs:
		if item.get_ref() != null:
			count += 1
	return count

func trace(phase: String) -> void:
	print("LAB_TRACE " + JSON.stringify({"phase": phase, "usec": Time.get_ticks_usec() - started_usec,
		"playback_weak_refs_alive": live(playback_refs), "stream_weak_refs_alive": live(stream_refs),
		"tree_nodes": get_node_count(), "mix_since_s": AudioServer.get_time_since_last_mix()}))

func retain_weak_playback(player: AudioStreamPlayer) -> void:
	var playback := player.get_stream_playback()
	if playback != null:
		playback_refs.append(weakref(playback))
	# The local strong reference ends here, before any stop/free/quit operation.

func create_players(count: int) -> void:
	for index in range(count):
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/slice_%s.wav" % ["print", "undo", "complete"][index])
		stream_refs.append(weakref(player.stream))
		root.add_child(player)
		players.append(player)

func cleanup_players(queued: bool = false) -> void:
	for player in players:
		player.stop()
		player.stream = null
		if queued:
			player.queue_free()
		else:
			player.free()
	players.clear()

func drain_observed_references() -> bool:
	# This is a separately labelled mitigation experiment, NOT an alteration to
	# immediate-quit cases C/D/E or the original game stress test.
	var deadline := Time.get_ticks_usec() + 2_000_000
	while live(playback_refs) > 0:
		if Time.get_ticks_usec() >= deadline:
			printerr("ERROR: observed playback references did not retire within 2 seconds")
			return false
		await process_frame
	return true

func finish(ok: bool = true) -> void:
	trace("before_quit")
	print("LAB_RESULT " + JSON.stringify({"case": case_name, "driver": AudioServer.get_driver_name(),
		"script_usec": Time.get_ticks_usec() - started_usec, "completed": ok,
		"playback_weak_refs_alive": live(playback_refs), "stream_weak_refs_alive": live(stream_refs)}))
	quit(0 if ok else 2)

func game_case() -> void:
	game_scene = load("res://integrated_main.tscn").instantiate()
	game_scene.autosave_enabled = false
	root.add_child(game_scene)
	game_scene._new_game()
	game_scene.overlay.hide()
	for player in game_scene.audio.values():
		stream_refs.append(weakref(player.stream))
	for repetition in range(100):
		for key in ["print", "undo", "complete"]:
			game_scene._play_sound(key)
			retain_weak_playback(game_scene.audio[key])
		if repetition % 4 == 0:
			game_scene._setting_value_changed(true, "mute")
			game_scene._setting_value_changed(false, "mute")
	trace("after_game_stress")
	if case_name == "H_quit":
		# The game's existing menu close path; no cleanup performed by the probe.
		game_scene._quit_game()
		finish()
		return
	game_scene.free()
	game_scene = null
	trace("after_game_free")
	if case_name == "H_drain":
		finish(await drain_observed_references())
	else:
		finish()

func run() -> void:
	started_usec = Time.get_ticks_usec()
	print("LAB_BEGIN " + JSON.stringify({"case": case_name, "driver": AudioServer.get_driver_name(),
		"engine": Engine.get_version_info()["string"]}))
	if case_name.begins_with("H_"):
		await game_case()
		return
	if case_name == "A":
		finish()
		return
	create_players(1 if case_name == "C" else 3)
	if case_name == "B":
		cleanup_players()
		finish()
		return
	for repetition in range(100 if case_name in ["D", "E", "E_queue", "E_drain"] else 1):
		for player in players:
			player.play()
			retain_weak_playback(player)
	trace("after_play")
	if case_name == "F":
		# Natural completion is signalled by the players, not a fixed wait period.
		var deadline := Time.get_ticks_usec() + 5_000_000
		while players.any(func(player): return player.playing):
			if Time.get_ticks_usec() > deadline:
				printerr("ERROR: natural playback did not finish")
				finish(false)
				return
			await process_frame
		trace("natural_completion")
		cleanup_players()
	elif case_name in ["E", "E_drain", "E_queue"]:
		cleanup_players(case_name == "E_queue")
		if case_name == "E_queue":
			await process_frame
		trace("after_stop_null_free")
	if case_name == "E_drain":
		finish(await drain_observed_references())
	else:
		finish()
