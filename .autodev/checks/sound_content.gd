extends SceneTree
var failures: Array=[]
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);printerr("SOUND CONTENT FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	check(AudioServer.get_driver_name()=="WASAPI","actual WASAPI required")
	var main=load("res://campaign_main.tscn").instantiate();root.add_child(main);main.start_new();main.dismiss_story();await process_frame
	check(main.has_method("get_environment_audio"),"actual product ambience interface")
	if not main.has_method("get_environment_audio"):main.free();quit(2);return
	var player=main.get_environment_audio()
	check(player is AudioStreamPlayer and player.stream is AudioStreamWAV,"actual original ambience WAV used")
	var peak: float=-200.0;var deadline:=Time.get_ticks_msec()+2000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		peak=maxf(peak,maxf(AudioServer.get_bus_peak_volume_left_db(0,0),AudioServer.get_bus_peak_volume_right_db(0,0)))
	check(peak> -70.0 and peak<0.0,"nonzero real mixer output below clipping")
	main._setting_value_changed(true,"mute");check(not player.playing,"mute stops ambience")
	main._setting_value_changed(false,"mute");main._setting_value_changed(0.0,"bgm");check(not player.playing,"BGM zero stops ambience")
	main._setting_value_changed(0.3,"bgm");check(player.playing,"BGM restore resumes ambience")
	main.free();print("SOUND_CONTENT_RESULT "+JSON.stringify({"peak_db":peak,"failures":failures}))
	if failures.is_empty():print("SOUND_CONTENT_PASS")
	quit(0 if failures.is_empty() else 2)
