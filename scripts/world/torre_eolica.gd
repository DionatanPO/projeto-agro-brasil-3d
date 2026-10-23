extends Node3D
## TorreEolica: torre estatica + rotor girando.
## Segue o padrao do drone (drone_jogador.gd): as helices giram em _process.
## O rotor fica no "Eixo principal do rotor" da torre (0, 26.5, 0.98) e gira
## no eixo Z (pas apontam +Y e varrem o plano vertical de frente para +Z).

## Rotacoes por minuto do rotor. Turbina real: ~10-20 rpm.
@export var rpm := 18.0
## Eixo de giro no espaco local do Rotor.
@export var eixo_giro := Vector3(0.0, 0.0, 1.0)
## Variacao suave do vento (0 = vento constante).
@export var variacao_vento := 0.1

@onready var rotor: Node3D = $Rotor

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	var fator := 1.0 + variacao_vento * sin(_t * 0.5)
	rotor.rotate(eixo_giro.normalized(), TAU * (rpm / 60.0) * fator * delta)
