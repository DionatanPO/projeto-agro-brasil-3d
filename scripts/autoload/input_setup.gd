extends Node
## Autoload `InputSetup`: garante as acoes de entrada do projeto base.
## Se as acoes ja existirem (definidas no editor), nada e alterado.

const ACOES: Dictionary = {
	"mover_frente": [KEY_W, KEY_UP],
	"mover_tras": [KEY_S, KEY_DOWN],
	"mover_esq": [KEY_A, KEY_LEFT],
	"mover_dir": [KEY_D, KEY_RIGHT],
	"pular": [KEY_SPACE],
	"descer": [KEY_C, KEY_CTRL],
	"ligar_motor": [KEY_L],
	"pulverizar": [KEY_F],
	"correr": [KEY_SHIFT],
	"interagir": [KEY_E],
	"tutorial_drone": [KEY_T],
	"buzinar": [KEY_H],
	"diario": [KEY_TAB],
	"chuva": [KEY_F1],  # Ativar/desativar simulacao de chuva
	"camera": [KEY_Y],  # Alternar distancia da camera (fase da descida)
}

## Botoes do controle (Xbox): A pula, LB corre, X interage, Y abre o caderno.
const BOTOES_PAD: Dictionary = {
	"pular": [JOY_BUTTON_A],
	"descer": [JOY_BUTTON_B],
	"ligar_motor": [JOY_BUTTON_RIGHT_SHOULDER],
	"correr": [JOY_BUTTON_LEFT_SHOULDER],
	"interagir": [JOY_BUTTON_X],
	"tutorial_drone": [JOY_BUTTON_Y],
	"buzinar": [JOY_BUTTON_BACK, JOY_BUTTON_LEFT_SHOULDER],
	"diario": [JOY_BUTTON_START],
}

## Stick esquerdo no lugar do WASD (eixo + lado que ativa).
const EIXOS_PAD: Dictionary = {
	"mover_esq": [JOY_AXIS_LEFT_X, -1.0],
	"mover_dir": [JOY_AXIS_LEFT_X, 1.0],
	"mover_frente": [JOY_AXIS_LEFT_Y, -1.0],
	"mover_tras": [JOY_AXIS_LEFT_Y, 1.0],
	"pulverizar": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}


func _ready() -> void:
	for acao: String in ACOES.keys():
		if InputMap.has_action(acao):
			continue
		InputMap.add_action(acao, 0.2)
		for tecla: Key in ACOES[acao]:
			var evento := InputEventKey.new()
			evento.physical_keycode = tecla
			InputMap.action_add_event(acao, evento)
	for acao: String in BOTOES_PAD.keys():
		if not InputMap.has_action(acao):
			InputMap.add_action(acao, 0.2)
		for botao: int in BOTOES_PAD[acao]:
			var evento_pad := InputEventJoypadButton.new()
			evento_pad.button_index = botao as JoyButton
			InputMap.action_add_event(acao, evento_pad)
	for acao: String in EIXOS_PAD.keys():
		if not InputMap.has_action(acao):
			InputMap.add_action(acao, 0.2)
		var dados: Array = EIXOS_PAD[acao]
		var evento_eixo := InputEventJoypadMotion.new()
		evento_eixo.axis = dados[0] as JoyAxis
		evento_eixo.axis_value = float(dados[1])
		InputMap.action_add_event(acao, evento_eixo)