extends "res://scripts/main.gd"

func _ready() -> void:
	state = preload("res://scripts/mech_state.gd").new()
	super._ready()

func _refresh() -> void:
	super._refresh()
	var allowed: Array = state.puzzle_data()[state.snapshot()["puzzle"]]["allowed_masks"]
	for i in range(mask_buttons.size()):
		mask_buttons[i].disabled = not i in allowed
	if state.is_solved():
		status.text = "MATCH! N: next puzzle | U / Z: undo | R: retry" if state.can_advance() else "Six puzzles complete. U / Z: undo | R: retry"
