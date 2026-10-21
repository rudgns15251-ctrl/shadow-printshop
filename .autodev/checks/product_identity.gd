extends SceneTree
## Trusted S08 probe: the product is named 음영 인쇄소 everywhere the engine shows a
## project name, while user:// stays the exact legacy directory so every existing
## v1, story and campaign save remains where it was. Not a branding review.
var failures: Array = []
var checks := 0
const LEGACY_USER_DIR := "Godot/app_userdata/C01 - Shadow Printshop Slice"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("PRODUCT IDENTITY FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func visible_text(node: Node) -> String:
	var text: String = node.text if node is Control and node.is_visible_in_tree() and (node is Label or node is Button) else ""
	for child in node.get_children():
		text += "\n" + visible_text(child)
	return text

func run() -> void:
	check(ProjectSettings.get_setting("application/config/name") == "음영 인쇄소", "project display name")
	check(ProjectSettings.get_setting("application/config/use_custom_user_dir", false) == true, "explicit user directory")
	check(ProjectSettings.get_setting("application/config/custom_user_dir_name", "") == LEGACY_USER_DIR, "legacy user directory key kept")
	check(OS.get_user_data_dir().replace("\\", "/").ends_with("/" + LEGACY_USER_DIR), "user:// resolves to the legacy save directory: " + OS.get_user_data_dir())
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.get_window().title == "음영 인쇄소", "window title")
	for forbidden in ["Shadow Printshop Slice", "Slice", "Test", "수직 슬라이스"]:
		check(not forbidden in visible_text(main), "start screen has no prototype naming: " + forbidden)
	main.start_new()
	check(main.save_campaign() and FileAccess.file_exists("user://c01_campaign_v1.json"), "campaign save written in the kept directory")
	check(main.load_campaign(), "campaign save reloads")
	main.free()
	print("PRODUCT_IDENTITY_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("PRODUCT_IDENTITY_PASS")
	quit(0 if failures.is_empty() else 2)
