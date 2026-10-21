extends SceneTree
## Trusted S14 probe: the project is ready for an Android export. ETC2/ASTC
## texture import (required by the Android exporter), sensor-landscape handheld
## orientation, aspect "expand" so wide phones are filled instead of letterboxed,
## and the back gesture left to the game. Adaptive launcher icon layers exist as
## original SVGs in the asset ledger: the foreground stays inside the circular
## safe zone, the background is opaque, the monochrome layer is a single colour
## for themed icons. The desktop window size and icon stay as certified.
var failures: Array = []
var checks := 0
const ICONS := {"foreground": "res://assets/art/android_icon_foreground.svg",
	"background": "res://assets/art/android_icon_background.svg",
	"monochrome": "res://assets/art/android_icon_monochrome.svg"}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("ANDROID PROJECT FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func raster(path: String) -> Image:
	var image := Image.new()
	if image.load_svg_from_string(FileAccess.get_file_as_string(path), 432.0 / 432.0) != OK:
		return null
	if image.get_width() != 432:
		image.resize(432, 432, Image.INTERPOLATE_BILINEAR)
	return image

func run() -> void:
	check(bool(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false)), "ETC2/ASTC texture import enabled for Android")
	check(int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) == DisplayServer.SCREEN_SENSOR_LANDSCAPE, "landscape that follows the phone's rotation")
	check(str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "expand", "wide phones are filled, not letterboxed")
	check(not bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)), "the back gesture is the game's to handle")
	check(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 1280 and int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 720, "desktop base size unchanged")
	check(str(ProjectSettings.get_setting("application/config/icon", "")) == "res://assets/art/app_icon.svg", "desktop icon unchanged")
	var ledger = JSON.parse_string(FileAccess.get_file_as_string("res://ASSET_LICENSES.json"))
	var rows := {}
	if ledger is Array:
		for row in ledger:
			rows[str(row.get("path", ""))] = row
	for key in ICONS:
		var path: String = ICONS[key]
		var text := FileAccess.get_file_as_string(path)
		check(text.contains("<svg") and not text.contains("<image") and not text.contains("href=\"http") and not text.contains("data:image"), key + ": original vector SVG")
		var bytes := FileAccess.get_file_as_bytes(path)
		var digest := ""
		if not bytes.is_empty():
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_SHA256)
			ctx.update(bytes)
			digest = ctx.finish().hex_encode()
		var row: Dictionary = rows.get(path.trim_prefix("res://"), {})
		check(not row.is_empty() and str(row.get("final_encoded_measurements", {}).get("sha256", "")) == digest and not row.get("usage", []).is_empty(), key + ": in the ledger with matching hash and usage")
	var fg := raster(ICONS["foreground"])
	var bg := raster(ICONS["background"])
	var mono := raster(ICONS["monochrome"])
	check(fg != null and bg != null and mono != null, "icon layers rasterise at 432x432")
	if fg == null or bg == null or mono == null:
		print("ANDROID_PROJECT_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
		quit(2)
		return
	var outside := 0
	var drawn := 0
	var transparent_bg := 0
	var colours := {}
	for y in range(0, 432, 4):
		for x in range(0, 432, 4):
			var d := Vector2(x - 216, y - 216).length()
			var a := fg.get_pixel(x, y).a
			if a > 0.1:
				drawn += 1
				if d > 160.0:
					outside += 1
			if bg.get_pixel(x, y).a < 0.99:
				transparent_bg += 1
			var m := mono.get_pixel(x, y)
			if m.a > 0.5:
				colours[Color(m.r, m.g, m.b).to_html(false)] = true
	check(drawn > 200, "foreground draws a recognisable mark")
	check(outside == 0, "foreground stays inside the adaptive-icon safe zone (%d pixels outside)" % outside)
	check(transparent_bg == 0, "background layer is fully opaque")
	check(colours.size() >= 1 and colours.size() <= 3, "monochrome layer is a single colour (%d tones)" % colours.size())
	print("ANDROID_PROJECT_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("ANDROID_PROJECT_PASS")
	quit(0 if failures.is_empty() else 2)
