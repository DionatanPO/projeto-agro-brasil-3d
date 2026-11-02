extends Label

@export var ativo_debug: bool = false

func _ready() -> void:
	set_process(ativo_debug)

func _process(_delta: float) -> void:
	if not ativo_debug:
		set_process(false)
		return
	text = """
FPS: %d
Frame Time: %.2f ms
""" % [
		Engine.get_frames_per_second(),
		1000.0 / Engine.get_frames_per_second()
	]
