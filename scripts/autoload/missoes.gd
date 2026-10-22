extends Node
## Autoload `Missoes`: definicoes de data/missoes.json + progresso do save.

signal missoes_atualizadas
signal missao_concluida(missao_id: String)

const CAMINHO := "res://data/configs/missoes.json"

var ordem: Array = []
var por_id: Dictionary = {}


func _ready() -> void:
	_carregar_definicoes()


func concluidas() -> Array:
	return SaveSystem.dados.get("missoes_concluidas", [])


func esta_concluida(missao_id: String) -> bool:
	return missao_id in concluidas()


func verificar_progresso(descobertas: Array) -> void:
	for missao_id: String in ordem:
		if esta_concluida(missao_id):
			continue
		var req: Array = (por_id[missao_id] as Dictionary).get("pontos_ids", [])
		var ok := true
		for ponto: String in req:
			if not (ponto in descobertas):
				ok = false
				break
		if ok:
			(concluidas() as Array).append(missao_id)
			SaveSystem.dados["missoes_concluidas"] = concluidas()
			SaveSystem.salvar()
			missao_concluida.emit(missao_id)
	missoes_atualizadas.emit()


func proxima_pendente() -> Dictionary:
	for missao_id: String in ordem:
		if not esta_concluida(missao_id):
			return por_id[missao_id]
	return {}


func total_concluidas() -> int:
	return concluidas().size()


func total_missoes() -> int:
	return ordem.size()


func _carregar_definicoes() -> void:
	var arq := FileAccess.open(CAMINHO, FileAccess.READ)
	if arq == null:
		push_error("Missoes: data/missoes.json nao encontrado.")
		return
	var parsed: Variant = JSON.parse_string(arq.get_as_text())
	if not (parsed is Dictionary):
		push_error("Missoes: JSON invalido.")
		return
	ordem.clear()
	por_id.clear()
	for m: Variant in (parsed as Dictionary).get("missoes", []):
		if m is Dictionary and (m as Dictionary).has("id"):
			ordem.append((m as Dictionary)["id"])
			por_id[(m as Dictionary)["id"]] = m
