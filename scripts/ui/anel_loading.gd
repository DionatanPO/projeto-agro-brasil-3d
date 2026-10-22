extends Control
## Spinner minimalista e veloz de carregamento circular.
## Usa espessura e velocidade refinadas para fluidez mesmo em 60+ FPS.

var angulo := 0.0
var velocidade := 4.5
var cor_fundo := Color(1.0, 1.0, 1.0, 0.12)
var cor_frente := Color(0.38, 1.0, 0.62, 0.95)
var espessura := 3.5

func _process(delta: float) -> void:
	angulo = fmod(angulo + delta * velocidade, TAU)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var raio := minf(size.x, size.y) * 0.5 - espessura * 0.5 - 1.0
	if raio <= 0.0:
		return
	# Trilha de fundo translúcida
	draw_arc(c, raio, 0.0, TAU, 32, cor_fundo, espessura, true)
	# Arco em movimento
	var inicio := -PI * 0.5 + angulo
	var fim := inicio + TAU * 0.4
	draw_arc(c, raio, inicio, fim, 32, cor_frente, espessura, true)

func definir(_v: float) -> void:
	pass
