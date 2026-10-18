extends SceneTree
var view
var checks := 0
var failures: Array = []
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message);printerr("SPRINT LAYOUT FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in range(8): await process_frame
func controls(n: Node, out: Array) -> void:
	if n is Control: out.append(n)
	for child in n.get_children(): controls(child,out)
func scroll_of(n: Node) -> ScrollContainer:
	var p=n.get_parent()
	while p!=null:
		if p is ScrollContainer: return p
		p=p.get_parent()
	return null
func contains(scroll: ScrollContainer, item: Control) -> bool:
	return scroll.get_global_rect().grow(1.0).encloses(item.get_global_rect())
func close_modal() -> void:
	view.overlay.hide()
	var focus=root.gui_get_focus_owner()
	if focus!=null: focus.release_focus()
func run() -> void:
	view=load("res://integrated_main.tscn").instantiate();view.autosave_enabled=false;root.add_child(view)
	close_modal();view._new_game();await settle()
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution;root.content_scale_size=resolution
		for scale_value in [1.0,1.25,1.5]:
			view._set_font_scale(scale_value);view._new_game();close_modal();await settle()
			var label="%s font %s"%[resolution,scale_value]
			var scroll=scroll_of(view.print_button)
			check(scroll!=null,label+" main scroller exists")
			scroll.scroll_vertical=0;await settle()
			if resolution==Vector2i(1280,720) and scale_value==1.0:
				check(contains(scroll,view.print_button),label+" print visible without scrolling")
				for board in [view.before_view,view.after_view,view.target_view]:
					check(contains(scroll,board),label+" full board visible without scrolling")
			var state: Dictionary=view.state.export_progress()
			view.print_button.grab_focus();await settle()
			check(contains(scroll,view.print_button),label+" main focused action scrolls into view")
			check(view.state.export_progress()==state,label+" focus never prints")
			view._open_settings();await settle()
			check(view.popup_panel.get_global_rect().grow(1.0).encloses(view.popup_scroll.get_global_rect()),label+" modal scroller within panel")
			var all: Array=[];controls(view.dialog,all)
			var returns: Array=[];var font_buttons:=0
			for item in all:
				if item is Label and item.text in ["전체 음량","효과음","글자 크기"]:
					var width: float=item.get_theme_font("font").get_string_size(item.text,HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x
					check(item.size.x+1.0>=width,label+" readable short setting name "+item.text)
				if item is Button and item.text in ["100%","125%","150%"]:
					font_buttons+=1
					check(item.size.y<=item.get_combined_minimum_size().y+2.0,label+" font choice natural height "+item.text)
				if item is Button and item.text=="돌아가기": returns.append(item)
			check(font_buttons==3,label+" three font choices preserved")
			check(returns.size()==1,label+" return button exists")
			if returns.size()==1:
				returns[0].release_focus()
				view.popup_scroll.scroll_vertical=0;returns[0].grab_focus();await settle()
				check(contains(view.popup_scroll,returns[0]),label+" modal focused Return scrolls into view")
			check(view.state.export_progress()==state,label+" settings focus preserves game progress")
			close_modal()
	view.free();view=null
	print("SPRINT_LAYOUT_RESULT "+JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 2)
