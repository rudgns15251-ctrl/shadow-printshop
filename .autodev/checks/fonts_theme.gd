extends SceneTree
## Trusted S09 probe: the product ships its own Korean fonts (unmodified SIL OFL
## Nanum files) and a shared theme, so Hangul never depends on an OS fallback
## font. Titles/documents use NanumMyeongjo, UI uses NanumGothic. Font scaling,
## the register (OFL text verbatim) and credits remain correct. Not a taste review.
var failures: Array = []
var checks := 0
const FONTS := {
	"res://assets/fonts/NanumGothic-Regular.ttf": "76f45ef4a6bcff344c837c95a7dcc26e017e38b5846d5ae0cdcb5b86be2e2d31",
	"res://assets/fonts/NanumGothic-Bold.ttf": "f96298f9fb18e364d2370f4c3ce948ac67a2b61af992d7234bc15c42b033c674",
	"res://assets/fonts/NanumMyeongjo-Regular.ttf": "7ed9e8653a8ed04285d51dc343ffea6eb3d9c73afc27383ea8929ee4ffd03205",
	"res://assets/fonts/NanumMyeongjo-Bold.ttf": "bc9ed8e60d93fe6db054b8fb988481b625f2eef8cb2317ad0e9834681b8fe3f3",
}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FONTS THEME FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func family(font: Font) -> String:
	return font.get_font_name() if font != null else ""

func is_gothic(font: Font) -> bool:
	return family(font).contains("NanumGothic") or family(font).contains("나눔고딕")

func is_myeongjo(font: Font) -> bool:
	return family(font).contains("NanumMyeongjo") or family(font).contains("나눔명조")

func controls(node: Node, out: Array) -> void:
	for child in node.get_children():
		if (child is Label or child is Button) and child.is_visible_in_tree() and not str(child.text).is_empty():
			out.append(child)
		controls(child, out)

func coverage(main, label: String) -> void:
	var found: Array = []
	controls(main, found)
	var missing := {}
	for item in found:
		var font: Font = item.get_theme_font("font")
		for ch in str(item.text):
			var code := ch.unicode_at(0)
			var hangul := code >= 0xAC00 and code <= 0xD7A3
			var basic := (code >= 0x30 and code <= 0x39) or (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A)
			if (hangul or basic) and not font.has_char(code):
				missing[ch] = family(font)
	check(missing.is_empty(), label + ": Hangul and alphanumerics are covered by the bundled primary font " + str(missing.keys().slice(0, 10)))

func run() -> void:
	for path in FONTS:
		check(FileAccess.file_exists(path) and FileAccess.get_sha256(path) == FONTS[path], "unmodified bundled font " + path)
		check(load(path) is FontFile, "font imports " + path)
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.theme is Theme and is_gothic(main.theme.default_font), "campaign theme default font is NanumGothic")
	coverage(main, "start screen")
	main.start_new()
	main.dismiss_story()
	await process_frame
	check(is_myeongjo(main.heading.get_theme_font("font")), "puzzle heading uses NanumMyeongjo")
	check(is_gothic(main.print_button.get_theme_font("font")), "action buttons use NanumGothic")
	coverage(main, "puzzle screen")
	main._open_order()
	await process_frame
	coverage(main, "order document")
	main.dismiss_story()
	var before: int = main.heading.get_theme_font_size("font_size")
	main._set_font_scale(1.5)
	check(main.heading.get_theme_font_size("font_size") > before, "font scale still enlarges themed text")
	main._set_font_scale(1.0)
	var parser := JSON.new()
	var rows := {}
	if parser.parse(FileAccess.get_file_as_string("res://ASSET_LICENSES.json")) == OK and parser.data is Array:
		for row in parser.data:
			if row is Dictionary:
				rows[str(row.get("path", ""))] = row
	for path in FONTS:
		var row: Dictionary = rows.get(path.trim_prefix("res://"), {})
		check(str(row.get("license", "")) == "OFL-1.1", "register license for " + path)
		var text := str(row.get("license_text", ""))
		check(text.contains("SIL OPEN FONT LICENSE Version 1.1") and text.contains("Reserved Font Name"), "full OFL text recorded for " + path)
	var credits := FileAccess.get_file_as_string("res://CREDITS_KO.md")
	check(credits.contains("나눔고딕") and credits.contains("나눔명조") and credits.contains("OFL"), "credits name the bundled fonts and license")
	main.free()
	print("FONTS_THEME_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("FONTS_THEME_PASS")
	quit(0 if failures.is_empty() else 2)
