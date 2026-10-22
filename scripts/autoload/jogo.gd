extends Node
## Autoload `Jogo`: estado global da sessao (conteudos, descobertas, dialogo).

signal descoberta_registrada(ponto_id: String)
signal dialogo_solicitado(conteudo_id: String)
signal alternar_diario

const CAMINHO_CONTEUDOS := "res://data/configs/conteudos.json"

var conteudos: Dictionary = {}
var tempo_sessao: float = 0.0


func _ready() -> void:
	_carregar_conteudos()


func _process(delta: float) -> void:
	tempo_sessao += delta
	SaveSystem.dados["tempo_jogado_seg"] = float(SaveSystem.dados.get("tempo_jogado_seg", 0.0)) + delta


func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("diario"):
		alternar_diario.emit()


func obter_conteudo(ponto_id: String) -> Dictionary:
	return conteudos.get(ponto_id, {})


func abrir_dialogo(ponto_id: String) -> void:
	dialogo_solicitado.emit(ponto_id)


func registrar_descoberta(ponto_id: String) -> void:
	var descobertas: Array = SaveSystem.dados.get("descobertas", [])
	if ponto_id in descobertas:
		return
	descobertas.append(ponto_id)
	SaveSystem.dados["descobertas"] = descobertas
	SaveSystem.salvar()
	descoberta_registrada.emit(ponto_id)
	Missoes.verificar_progresso(descobertas)


func total_descobertas() -> int:
	return (SaveSystem.dados.get("descobertas", []) as Array).size()


func total_pontos() -> int:
	return conteudos.size()


func _carregar_conteudos() -> void:
	var arq := FileAccess.open(CAMINHO_CONTEUDOS, FileAccess.READ)
	if arq == null:
		push_error("Jogo: data/conteudos.json nao encontrado.")
		return
	var parsed: Variant = JSON.parse_string(arq.get_as_text())
	if parsed is Dictionary:
		conteudos = (parsed as Dictionary).get("conteudos", {})
