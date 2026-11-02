extends Node
## Autoload `Jogo`: estado global da sessao (conteudos, descobertas, dialogo).

signal descoberta_registrada(ponto_id: String)
signal dialogo_solicitado(conteudo_id: String)
signal alternar_diario

const CAMINHO_CONTEUDOS := "res://data/configs/conteudos.json"

var conteudos: Dictionary = {}
var tempo_sessao: float = 0.0


func _ready() -> void:
	set_process_mode(Node.PROCESS_MODE_ALWAYS)
	_carregar_conteudos()
	# Salvamento so ocorre ao concluir missao/subobjetivo (via sinais do MissionManager).
	# Nao há autosave periodico nem gravacao de posicao/tempo a cada frame.
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm != null:
		if mm.has_signal("mission_completed") and not mm.is_connected("mission_completed", _on_missao_concluida):
			mm.mission_completed.connect(_on_missao_concluida)
		if mm.has_signal("objective_completed") and not mm.is_connected("objective_completed", _on_objetivo_concluido):
			mm.objective_completed.connect(_on_objetivo_concluido)


func _process(_delta: float) -> void:
	# Apenas acumula tempo local. O tempo e gravado no save apenas ao concluir missao.
	tempo_sessao += _delta


func _on_missao_concluida(mission_id: String) -> void:
	_salvar_progresso_missao()


func _on_objetivo_concluido(mission_id: String, objective_id: String) -> void:
	_salvar_progresso_missao()


func _salvar_progresso_missao() -> void:
	"""Grava posicao do jogador, drone, trator e tempo jogado no save e salva em disco.
	Chamado apenas ao concluir uma missao ou subobjetivo."""
	var player = get_tree().get_first_node_in_group("jogador")
	if player is Node3D:
		SaveSystem.dados["posicao_jogador"] = [player.global_position.x, player.global_position.y, player.global_position.z]
	var drone = get_tree().get_first_node_in_group("drone_jogador")
	if drone is Node3D:
		SaveSystem.dados["posicao_drone"] = [drone.global_position.x, drone.global_position.y, drone.global_position.z]
	var trator = get_tree().get_first_node_in_group("trator_jogador")
	if trator is Node3D:
		SaveSystem.dados["posicao_trator"] = [trator.global_position.x, trator.global_position.y, trator.global_position.z]
	SaveSystem.dados["tempo_jogado_seg"] = float(SaveSystem.dados.get("tempo_jogado_seg", 0.0)) + tempo_sessao
	SaveSystem.salvar()


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
	descoberta_registrada.emit(ponto_id)
	# MissionManager (via DiscoveryMission) ouve descoberta_registrada e verifica progresso
	# Missoes.verificar_progresso(descobertas)  # LEGADO - agora via MissionManager


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
