extends SceneTree
## Trusted S08 probe: the product has its own window/taskbar icon (project
## setting, original SVG registered in ASSET_LICENSES.json and credited), not the
## engine default. The exported executable is not modified, so the pinned
## template identity check still applies. Not an aesthetic review.
var failures: Array = []
var checks := 0
const ICON := "res://assets/art/app_icon.svg"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("WINDOW ICON FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(ProjectSettings.get_setting("application/config/icon", "") == ICON, "project icon setting")
	var texture: Texture2D = load(ICON) if ResourceLoader.exists(ICON) else null
	check(texture != null and texture.get_width() >= 128 and texture.get_height() >= 128, "icon imports as a texture of at least 128 px")
	if texture != null:
		var image: Image = texture.get_image()
		var colors := {}
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				var c := image.get_pixel(x, y)
				colors[Color(snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1), snappedf(c.a, 0.5))] = true
		check(colors.size() >= 4, "icon has real artwork, not a flat placeholder")
	var source := FileAccess.get_file_as_string(ICON)
	check(source.contains("<svg") and not source.contains("<image") and not source.contains("href=\"http") and not source.contains("<text"), "self-contained vector without embedded images, links or font text")
	var parser := JSON.new()
	var registered := false
	if parser.parse(FileAccess.get_file_as_string("res://ASSET_LICENSES.json")) == OK and parser.data is Array:
		for row in parser.data:
			if row is Dictionary and row.get("path", "") == "assets/art/app_icon.svg":
				registered = row.has("license") and row.has("origin") and row.has("creator")
	check(registered, "icon recorded in the asset register with creator, origin and license")
	check(FileAccess.get_file_as_string("res://CREDITS_KO.md").contains("app_icon.svg"), "icon credited")
	print("WINDOW_ICON_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("WINDOW_ICON_PASS")
	quit(0 if failures.is_empty() else 2)
