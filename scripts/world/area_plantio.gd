extends Area3D
## AreaPlantio: área onde o jogador pode plantar milho clicando no chão.
##
## Uso:
## 1. Colocar um Area3D na área de terra (entre silo e parque solar)
## 2. Adicionar este script
## 3. Configurar: mission_id, objective_id, quantidade_necessaria
## 4. O jogador clica com o mouse dentro da área para plantar milho

class_name AreaPlantio

signal milho_plantado(posicao: Vector3)
signal plantio_completo(quantidade: int)
signal pulverizacao_progresso(percentual: float)

@export var mission_id: String = ""
@export var objective_id: String = ""
# Para a missão 4 (pulverização), qual missão deve ser considerada ativa.
# Deixe vazio para usar o mesmo mission_id. Ex: "operacao_drone_milho".
@export var mission_id_pulverizacao: String = "operacao_drone_milho"
@export var objective_id_pulverizacao: String = "pulverizar_milho"
@export var quantidade_necessaria: int = 5
@export var quantidade_maxima: int = 400
@export var cena_milho: String = "res://scenes/world/milho_plantavel.tscn"
@export var distancia_max_plantio: float = 15.0
## Logs de depuração no console. Deixe desligado: cada print vai para o
## depurador do editor e, no meio da missão (um print por milho plantado e
## um por frame de pulverização), trava o jogo.
@export var debug_log: bool = false

var _milhos_plantados: int = 0
var _cena_milho: PackedScene
var _player: Node3D = null
var _camera: Camera3D = null
var _drone: Node3D = null
var _milhos_pulverizados: Array = []       # Posições dos milhos já pulverizados (para evitar duplicatas)
var _nos_milhos: Array[Node3D] = []           # Referências aos nós de milho criados
var _posicoes_pulverizadas: Array = []       # Posições dos milhos já pulverizados (legacy, mantido por compatibilidade)
@export var raio_pulverizacao: float = 3.0   # Raio de alcance da pulverização do drone
@export var percentual_necessario: float = 0.8   # Percentual da área que deve ser pulverizada (0.0 a 1.0). 1.0 = 100%, 0.8 = 80%.
var material_pulverizado: StandardMaterial3D = null  # Material aplicado ao milho pulverizado (configurar no inspector)

# Índice O(1) de posições já salvas (evita varrer todo o array a cada plantio).
var _chaves_posicoes: Dictionary = {}
# Índice O(1) de posições já pulverizadas.
var _chaves_pulverizadas: Dictionary = {}
# Adia o salvamento em disco para o final do frame (não trava o clique).
var _salvar_agendado := false
# Guarda se o objetivo de plantio já foi concluído (evita disparar 3x por clique).
var _objetivo_concluido := false
# Pulverização processa apenas durante a missão "operacao_drone_milho".
var _em_missao_pulverizacao: bool = false
# Última posição de pulverização já processada (evita revarrer tudo parado).
var _ultima_pos_pulverizacao := Vector3.ZERO
var _ultima_pos_pulverizacao_valida := false
# Gerador reaproveitado para a rotação aleatória de cada milho.
var _rng: RandomNumberGenerator = null


func _ready() -> void:
	_cena_milho = load(cena_milho) as PackedScene
	if _cena_milho == null:
		push_error("AreaPlantio: cena do milho não encontrada: " + cena_milho)
	
	add_to_group("area_plantio")
	
	# Referências
	_player = get_tree().get_first_node_in_group("jogador") as Node3D
	_camera = get_viewport().get_camera_3d()
	_drone = get_tree().get_first_node_in_group("drone_jogador") as Node3D
	_conectar_drone()
	
	# Restaura os milhos já plantados (persistência entre sessões)
	# Usa call_deferred para garantir que a cena esteja totalmente carregada
	if SaveSystem != null and SaveSystem.dados.has("milhos_plantados_posicoes"):
		call_deferred("_restaurar_milhos_salvos")
	
	# (Re)constroi os índices O(1) a partir do save existente.
	_reindexar_posicoes_salvas()
	_reindexar_pulverizados_salvos()
	
	set_process_input(true)
	# Conecta ao MissionManager para ativar/desativar pulverização por missão
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm != null and mm.has_signal("mission_changed") and not mm.is_connected("mission_changed", _on_missao_pulverizacao_mudou):
		mm.mission_changed.connect(_on_missao_pulverizacao_mudou)
	var ativa: Variant = mm.get_missao_ativa()
	if ativa != null and str(ativa.mission_id) == "operacao_drone_milho":
		_em_missao_pulverizacao = true
	# Tenta conectar ao drone após um frame (garante que o drone já entrou no grupo)
	call_deferred("_conectar_drone")


func _conectar_drone() -> void:
	_drone = get_tree().get_first_node_in_group("drone_jogador") as Node3D
	if _drone != null and _drone.has_signal("pulverizando"):
		if _em_missao_pulverizacao and not _drone.is_connected("pulverizando", _on_drone_pulverizando):
			_drone.pulverizando.connect(_on_drone_pulverizando)
			if debug_log:
				print("[AreaPlantio] Conectado ao sinal de pulverização do drone (missao ativa)")
		elif not _em_missao_pulverizacao and _drone.is_connected("pulverizando", _on_drone_pulverizando):
			_drone.pulverizando.disconnect(_on_drone_pulverizando)
			if debug_log:
				print("[AreaPlantio] Desconectado do sinal de pulverização do drone (missao inativa)")
	elif _drone == null:
		# Tenta novamente daqui a 1 segundo se o drone ainda não apareceu
		# Usa Timer one-shot em vez de call_deferred em loop.
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = 1.0
		timer.timeout.connect(_conectar_drone.bind())
		add_child(timer)
		timer.start()


func _notification(what: int) -> void:
	# Sem salvamento automático ao fechar. O save ocorre apenas ao concluir missão/subobjetivo (via Jogo).
	pass


func _unhandled_input(event: InputEvent) -> void:
	# Confere a ação PRIMEIRO: _unhandled_input recebe todo evento (inclusive
	# movimento de mouse, que chega dezenas de vezes por segundo). Fazer
	# consultas/prints antes daqui roda esse código a cada evento e derruba o FPS.
	if not event.is_action_pressed("interagir"):
		return
	if not _esta_ativa():
		return
	
	var player = get_tree().get_first_node_in_group("jogador") as Node3D
	if player == null:
		return
	
	# Verifica se o jogador está perto o suficiente da área
	var dist := global_position.distance_to(player.global_position)
	if dist > distancia_max_plantio:
		return
	
	# Raycast da câmera para o chão
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	
	var origem := camera.global_position
	var direcao := -camera.global_transform.basis.z
	var alvo := origem + direcao * 100.0
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origem, alvo)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 0xFFFFFFFF  # atinge todas as camadas (inclui Terrain3D)
	var resultado := space_state.intersect_ray(query)
	
	if resultado.is_empty():
		if debug_log:
			print("[AreaPlantio] Raycast não atingiu nada")
		return
	
	var ponto := resultado.position as Vector3
	
	# Verifica se o ponto está dentro da área de plantio (usando o raio do collision shape)
	if not _ponto_dentro_da_area(ponto):
		if debug_log:
			print("[AreaPlantio] Ponto fora da área de plantio: ", ponto)
		return
	
	if debug_log:
		print("[AreaPlantio] Plantando milho em: ", ponto)
	_plantar_milho(ponto)


func _ponto_dentro_da_area(ponto: Vector3) -> bool:
	# Verifica se o ponto está dentro dos limites do Area3D (usando o CollisionShape)
	var shape := _achar_collision_shape()
	if shape == null:
		return true  # Sem shape definido, permite em qualquer lugar próximo
	
	# Distância do ponto ao centro da área
	var dist := global_position.distance_to(ponto)
	var raio_efetivo := 8.0  # raio padrão de plantio
	
	if shape.shape is SphereShape3D:
		raio_efetivo = (shape.shape as SphereShape3D).radius
	elif shape.shape is BoxShape3D:
		var size := (shape.shape as BoxShape3D).size
		raio_efetivo = max(size.x, size.z) * 0.7
	
	return dist <= raio_efetivo


func _achar_collision_shape() -> CollisionShape3D:
	for filho in get_children():
		if filho is CollisionShape3D:
			return filho as CollisionShape3D
	return null


func _plantar_milho(ponto: Vector3) -> void:
	if _milhos_plantados >= quantidade_maxima:
		# Campo cheio é estado normal de jogo, não erro: antes um push_error
		# aqui disparava a cada clique no chão, enchendo o console.
		if debug_log:
			print("[AreaPlantio] Limite de ", quantidade_maxima, " milhos atingido.")
		return
	if _cena_milho == null:
		return

	# Espaçamento entre os milhos da fileirinha (metros).
	var espacamento := 1.0

	# Direção da fileira ao longo do eixo X do mundo.
	var direcao := Vector3.RIGHT

	# Um único gerador reutilizado. Antes cada milho criava um RNG e chamava
	# randomize() (reseed pelo sistema operacional) — 3 chamadas por clique.
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

	for i in 3:
		if _milhos_plantados >= quantidade_maxima:
			break

		var pos := ponto + direcao * (i - 1) * espacamento
		var milho := _cena_milho.instantiate()
		if milho == null:
			push_error("AreaPlantio: falha ao instanciar milho")
			return

		var pai := get_tree().current_scene
		if pai == null:
			pai = get_parent()

		if pai == null:
			milho.queue_free()
			return

		# Adiciona o nó à cena PRIMEIRO, depois posiciona (mais seguro no Godot 4)
		pai.add_child(milho)
		milho.global_position = pos + Vector3(0, 0.1, 0)

		var rng := _rng
		milho.rotation = Vector3(0, rng.randf_range(0, TAU), 0)

		_milhos_plantados += 1
		milho.add_to_group("milho_plantado")
		_nos_milhos.append(milho)
		milho_plantado.emit(pos)
		if debug_log:
			print("[AreaPlantio] Milho plantado: ", _milhos_plantados, " / ", quantidade_necessaria)

		# Registra a posição no save (sem gravar em disco ainda).
		_salvar_posicao_milho(milho.global_position, milho.rotation)

	# Completa o objetivo UMA ÚNICA VEZ ao atingir a quantidade necessária.
	if not _objetivo_concluido and _milhos_plantados >= quantidade_necessaria:
		_objetivo_concluido = true
		plantio_completo.emit(_milhos_plantados)
		_completar_objetivo()

	# Grava o save no final do frame (não trava o clique do jogador).
	_agendar_salvar()


func _esta_ativa() -> bool:
	if mission_id.is_empty():
		return true
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		return false
	var ativa: Variant = mm.get_missao_ativa()
	return ativa != null and str(ativa.mission_id) == mission_id


func _completar_objetivo() -> void:
	if is_instance_valid(Jogo):
		Jogo.registrar_descoberta("area_plantio_milho")
	
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm != null:
		mm.completar_objetivo(mission_id, objective_id)


## API pública

func get_quantidade_plantada() -> int:
	return _milhos_plantados


func resetar() -> void:
	_milhos_plantados = 0
	_milhos_pulverizados.clear()
	_chaves_pulverizadas.clear()
	_objetivo_concluido = false


func _ja_foi_pulverizado(posicao: Vector3) -> bool:
	# Consulta O(1) via Dictionary.
	var chave := _chave_posicao(posicao)
	return _chaves_pulverizadas.has(chave)


func _percentual_pulverizado() -> float:
	if _milhos_plantados == 0:
		return 0.0
	return float(_milhos_pulverizados.size()) / float(_milhos_plantados)


func _atualizar_progresso_pulverizacao() -> void:
	var percentual := _percentual_pulverizado()
	pulverizacao_progresso.emit(percentual)

	# Determina qual missão/objetivo atualizar baseado na missão ativa
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		return
	var ativa: Variant = mm.get_missao_ativa()
	var mid_ativa: String = str(ativa.mission_id) if ativa != null else ""

	# Se a missão ativa for a de pulverização, usa os IDs de pulverização
	var mid_usar: String = mission_id
	var obj_usar: String = objective_id
	if not mission_id_pulverizacao.is_empty() and mid_ativa == mission_id_pulverizacao:
		mid_usar = mission_id_pulverizacao
		obj_usar = objective_id_pulverizacao

	if not mid_usar.is_empty() and not obj_usar.is_empty():
		var m = mm.get_mission(mid_usar)
		if m != null and m.has_method("atualizar_progresso_objetivo"):
			m.atualizar_progresso_objetivo(obj_usar, percentual)

	# Só completa o objetivo quando atingir o percentual necessário
	if percentual >= percentual_necessario:
		if is_instance_valid(Jogo):
			Jogo.registrar_descoberta("milho_pulverizado")
		if debug_log:
			print("[AreaPlantio] Pulverizacao completa (", int(percentual * 100), "%)!")


func _on_drone_pulverizando(posicao: Vector3) -> void:
	# Pulverização só processa durante a missão de pulverização de milho
	if not _em_missao_pulverizacao:
		return
	if not _ponto_dentro_da_area(posicao):
		return

	# O drone emite este sinal a cada frame. Se ele está parado (ou quase),
	# a nuvem anterior já marcou tudo que estava no raio: varrer os 400
	# milhos de novo é trabalho jogado fora.
	if _ultima_pos_pulverizacao_valida and posicao.distance_squared_to(_ultima_pos_pulverizacao) < 0.0625:
		return
	_ultima_pos_pulverizacao = posicao
	_ultima_pos_pulverizacao_valida = true

	var raio2 := raio_pulverizacao * raio_pulverizacao
	var pulverizou_algo := false

	# Otimização: filtra milhos dentro do raio usando distância ao quadrado (evita sqrt).
	# A lista _nos_milhos cresce linearmente, mas para 400 itens ainda é aceitável
	# em uma única chamada. Se o drone emitir a 60 Hz, pode considerar grid espacial depois.
	for milho in _nos_milhos:
		if milho == null or not is_instance_valid(milho):
			continue
		var diff := milho.global_position - posicao
		# Ignora Y (altura) para pulverização em área plana
		diff.y = 0.0
		if diff.length_squared() <= raio2:
			if not _ja_foi_pulverizado(milho.global_position):
				_marcar_milho_pulverizado(milho)
				_milhos_pulverizados.append(milho.global_position)
				pulverizou_algo = true

	if pulverizou_algo:
		_atualizar_progresso_pulverizacao()
		_agendar_salvar()
		# Um print por evento, e o drone emite a cada frame enquanto borrifa:
		# isso sozinho já pesa no console do editor.
		if debug_log:
			print("[AreaPlantio] Milho pulverizado! Progresso: ", round(_percentual_pulverizado() * 100), "% / ", round(percentual_necessario * 100), "%")


func _marcar_milho_pulverizado(milho: Node3D) -> void:
	"""Marca um milho específico como pulverizado (visual + persistência)."""
	var corpo := milho.get_node_or_null("Milho")
	if corpo == null:
		corpo = milho
	if material_pulverizado != null:
		corpo.material_override = material_pulverizado
	_salvar_milho_pulverizado(milho.global_position)


func _salvar_milho_pulverizado(posicao: Vector3) -> void:
	"""Salva a posição de um milho pulverizado para persistir entre sessões."""
	var pulverizados: Array = SaveSystem.dados.get("milhos_pulverizados_posicoes", [])
	if pulverizados == null:
		pulverizados = []

	# Evita duplicatas via índice O(1).
	var chave := _chave_posicao(posicao)
	if _chaves_pulverizadas.has(chave):
		return  # Já existe, não salva novamente

	pulverizados.append({
		"x": posicao.x,
		"y": posicao.y,
		"z": posicao.z,
	})
	SaveSystem.dados["milhos_pulverizados_posicoes"] = pulverizados
	_chaves_pulverizadas[chave] = true
	# O gravamento em disco é feito por _fazer_salvar() (call_deferred).


## Persistência de milhos ──────────────────────────────────────────────

func _salvar_posicao_milho(posicao: Vector3, rotacao: Vector3) -> void:
	"""Adiciona a posição do milho ao save para persistir entre sessões."""
	var posicoes: Array = SaveSystem.dados.get("milhos_plantados_posicoes", [])
	if posicoes == null:
		posicoes = []
	
	# Evita duplicatas via índice O(1).
	var chave := _chave_posicao(posicao)
	if _chaves_posicoes.has(chave):
		return  # Já existe, não salva novamente
	
	var entrada: Dictionary = {
		"x": posicao.x,
		"y": posicao.y,
		"z": posicao.z,
		"rx": rotacao.x,
		"ry": rotacao.y,
		"rz": rotacao.z,
	}
	posicoes.append(entrada)
	SaveSystem.dados["milhos_plantados_posicoes"] = posicoes
	_chaves_posicoes[chave] = true
	# O gravamento em disco é feito uma única vez ao final de _plantar_milho.


func _salvar_todas_posicoes() -> void:
	"""Sem salvamento automático ao fechar. O save ocorre apenas ao concluir missão/subobjetivo (via Jogo)."""
	pass


## Agendamento de salvamento em disco ────────────────────────────────

func _agendar_salvar() -> void:
	if not _salvar_agendado:
		_salvar_agendado = true
		call_deferred("_fazer_salvar")


func _fazer_salvar() -> void:
	_salvar_agendado = false
	# Sem gravacao automática em disco. O save ocorre apenas ao concluir missao/subobjetivo (via Jogo).


## Retorna uma chave de string para uma posição (tolerância de 1 cm).
func _chave_posicao(pos: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [pos.x, pos.y, pos.z]


## (Re)constroi o índice O(1) a partir dos dados salvos existentes.
func _reindexar_posicoes_salvas() -> void:
	_chaves_posicoes.clear()
	var posicoes: Array = SaveSystem.dados.get("milhos_plantados_posicoes", [])
	if posicoes == null:
		return
	for entrada in posicoes:
		if entrada is Dictionary:
			var p := Vector3(
				float(entrada.get("x", 0)),
				float(entrada.get("y", 0)),
				float(entrada.get("z", 0)),
			)
			_chaves_posicoes[_chave_posicao(p)] = true


func _reindexar_pulverizados_salvos() -> void:
	_chaves_pulverizadas.clear()
	var pulverizados: Array = SaveSystem.dados.get("milhos_pulverizados_posicoes", [])
	if pulverizados == null:
		return
	for entrada in pulverizados:
		if entrada is Dictionary:
			var p := Vector3(
				float(entrada.get("x", 0)),
				float(entrada.get("y", 0)),
				float(entrada.get("z", 0)),
			)
			_chaves_pulverizadas[_chave_posicao(p)] = true


func _on_missao_pulverizacao_mudou(mission_id: Variant) -> void:
	var mid: String = str(mission_id)
	_em_missao_pulverizacao = (mid == "operacao_drone_milho")
	# Reconecta/desconecta o sinal do drone baseado na missão
	call_deferred("_conectar_drone")
	if not _em_missao_pulverizacao:
		if debug_log:
			print("[AreaPlantio] Missão de pulverização encerrada. Sinal de drone desconectado.")


func _posicao_foi_pulverizada(posicao: Vector3) -> bool:
	"""Verifica se um milho nesta posição já foi pulverizado (O(1))."""
	var chave := _chave_posicao(posicao)
	return _chaves_pulverizadas.has(chave)


func _restaurar_milhos_salvos() -> void:
	"""Recria os milhos salvos no disco ao carregar o jogo."""
	var posicoes: Array = SaveSystem.dados.get("milhos_plantados_posicoes", [])
	if debug_log:
		print("[AreaPlantio] Restaurando milhos salvos: ", posicoes.size())
	if posicoes == null or posicoes.is_empty():
		return
	if _cena_milho == null:
		push_error("AreaPlantio: cena do milho não carregada, impossível restaurar o plantio.")
		return

	var pai := get_tree().current_scene
	if pai == null:
		pai = get_parent()

	var restaurados := 0
	for entrada in posicoes:
		if not (entrada is Dictionary):
			continue
		var milho := _cena_milho.instantiate()
		if milho == null:
			continue
		var pos := Vector3(
			float(entrada.get("x", 0)),
			float(entrada.get("y", 0)),
			float(entrada.get("z", 0)),
		)
		var rot := Vector3(
			float(entrada.get("rx", 0)),
			float(entrada.get("ry", 0)),
			float(entrada.get("rz", 0)),
		)

		# Adiciona ao pai PRIMEIRO, depois posiciona (mais seguro no Godot 4)
		if pai:
			pai.add_child(milho)
		# A posição salva já inclui o deslocamento de 0.1 de altura (salvo no plantio)
		milho.global_position = pos
		milho.rotation = rot
		milho.add_to_group("milho_plantado")
		_nos_milhos.append(milho)
		_milhos_plantados += 1
		restaurados += 1

		# Restaura o estado pulverizado se este milho foi pulverizado anteriormente (O(1)).
		if _posicao_foi_pulverizada(pos):
			_milhos_pulverizados.append(pos)
			if material_pulverizado != null:
				var corpo := milho.get_node_or_null("Milho")
				if corpo == null:
					corpo = milho
				corpo.material_override = material_pulverizado

	if debug_log:
		print("[AreaPlantio] Milhos restaurados do save: ", restaurados, " / ", _milhos_plantados, " | Pulverizados: ", _milhos_pulverizados.size())
