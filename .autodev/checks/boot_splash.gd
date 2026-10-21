extends SceneTree
## Trusted S15 probe: the game boots on its own screen, not the engine logo.
## The boot background is the game's night colour; the boot image is an original
## PNG in the asset ledger (hash, size, usage), drawn on transparency so the
## night colour shows around it, shown at its own size (stretch disabled) so it
## stays crisp and whole on any window or phone, with no added waiting time.
## The window icon, base size and everything the game draws stay as certified.
var failures: Array = []
var checks := 0
const UiTheme = preload("res://scripts/ui_theme.gd")
const SPLASH := "res://assets/art/boot_splash.png"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("BOOT SPLASH FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	check(bg.is_equal_approx(UiTheme.NIGHT), "boot background is the night colour (" + bg.to_html(false) + ")")
	check(bool(ProjectSettings.get_setting("application/boot_splash/show_image", true)), "boot image shown")
	check(str(ProjectSettings.get_setting("application/boot_splash/image", "")) == SPLASH, "boot image is the game's own PNG")
	check(int(ProjectSettings.get_setting("application/boot_splash/stretch_mode", 1)) == 0, "boot image at its own size (stretch disabled)")
	check(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time", 0)) == 0, "no added boot waiting time")
	check(str(ProjectSettings.get_setting("application/config/icon", "")) == "res://assets/art/app_icon.svg", "window icon unchanged")
	check(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 1280 and int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 720, "base size unchanged")
	var bytes := FileAccess.get_file_as_bytes(SPLASH)
	check(bytes.size() > 8 and bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "boot image is a real PNG (the engine loads only PNG at boot)")
	var image := Image.new()
	var loaded := not bytes.is_empty() and image.load_png_from_buffer(bytes) == OK
	check(loaded, "boot image decodes")
	if loaded:
		var w := image.get_width()
		var h := image.get_height()
		check(w >= 256 and w <= 640 and h >= 200 and h <= 640, "boot image sized for a 720-line screen (%dx%d)" % [w, h])
		image.convert(Image.FORMAT_RGBA8)
		var corners := 0
		for p in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
			if image.get_pixelv(p).a < 0.05:
				corners += 1
		check(corners == 4, "drawn on transparency so the night colour shows around it")
		var drawn := 0
		var lamp := 0
		for y in range(0, h, 4):
			for x in range(0, w, 4):
				var c := image.get_pixel(x, y)
				if c.a > 0.5:
					drawn += 1
					if c.r > 0.85 and c.g > 0.72 and c.b < 0.72 and c.b > 0.45:
						lamp += 1
		check(drawn > (w / 4) * (h / 4) / 10, "boot image draws a recognisable mark")
		check(lamp > 20, "title lettering in the lamp colour")
	var ledger = JSON.parse_string(FileAccess.get_file_as_string("res://ASSET_LICENSES.json"))
	var row := {}
	if ledger is Array:
		for item in ledger:
			if str(item.get("path", "")) == SPLASH.trim_prefix("res://"):
				row = item
	var digest := ""
	if not bytes.is_empty():
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(bytes)
		digest = ctx.finish().hex_encode()
	check(not row.is_empty() and str(row.get("final_encoded_measurements", {}).get("sha256", "")) == digest and not row.get("usage", []).is_empty(), "boot image in the ledger with matching hash and usage")
	check(FileAccess.get_file_as_string("res://CREDITS_KO.md").contains("boot_splash.png"), "boot image named in the credits")
	print("BOOT_SPLASH_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("BOOT_SPLASH_PASS")
	quit(0 if failures.is_empty() else 2)
