extends MissionBase
## DiscoveryMission: Missão baseada em descobertas (visitar pontos, encontrar itens).
##
## Objetivos esperados no JSON:
## { "id": "ir_local", "tipo": "descoberta", "alvo_id": "local_encomenda", "texto": "Vá até o local" }
## { "id": "encontrar", "tipo": "descoberta", "alvo_id": "pacote", "texto": "Encontre o pacote" }
##
## Tipos de objetivo suportados:
## - "descoberta": jogador registra descoberta via Jogo.registrar_descoberta()
## - "area_enter": jogador entra em AreaTrigger específica
## - "interacao": jogador interage com objeto (pressiona E)

class_name DiscoveryMission

# Mapeamento: alvo_id -> objective_id (para lookup rápido)
var _descoberta_para_objetivo: Dictionary = {}


func _ready() -> void:
	super._ready()
	_construir_mapa_descobertas()


func _construir_mapa_descobertas() -> void:
	_descoberta_para_objetivo.clear()
	for obj in objetivos:
		var oid: String = str(obj.get("id", ""))
		var tipo: String = str(obj.get("tipo", "descoberta"))
		var alvo: String = str(obj.get("alvo_id", ""))
		if not oid.is_empty() and not alvo.is_empty() and tipo == "descoberta":
			_descoberta_para_objetivo[alvo] = oid


func _on_register() -> void:
	# Conecta ao sinal de descoberta do Jogo
	if is_instance_valid(Jogo):
		Jogo.descoberta_registrada.connect(_on_descoberta_registrada)


func _on_descoberta_registrada(ponto_id: String) -> void:
	if not _ativa or _concluida:
		return
	
	if _descoberta_para_objetivo.has(ponto_id):
		var oid: String = _descoberta_para_objetivo[ponto_id]
		_marcar_objetivo_completo(oid)
		_check_completion()


func on_objective_event(event_type: String, event_data: Dictionary) -> bool:
	# Para DiscoveryMission, eventos vêm via sinal Jogo.descoberta_registrada
	# Este método é para compatibilidade com MissionManager
	return false


func check_progress(game_state: Dictionary) -> bool:
	# DiscoveryMission é orientada a eventos (sinais), não polling
	# Mas verifica se todos objetivos já estão completos (ex: load save)
	if _ativa and not _concluida:
		if _verificar_todos_objetivos():
			_concluir_missao()
			return true
	return false


func _check_completion() -> void:
	if _verificar_todos_objetivos():
		_concluir_missao()