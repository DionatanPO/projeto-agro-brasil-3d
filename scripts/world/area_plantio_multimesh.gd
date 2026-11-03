extends Area3D
## AreaPlantioMultiMesh: versão otimizada da área de plantio usando MultiMesh3D.
##
## Em vez de criar 400 MeshInstance3D individuais (400 draw calls), usa um único
## MultiMeshInstance3D com 400 instâncias (1 draw call). Ganho massivo de FPS em mobile.
##
## Para usar: substitua o script do nó AreaPlantio no world.tscn por este.

class_name AreaPlantioMultiMesh

signal milho_plantado(posicao: Vector3)
signal plantio_completo(quantidade: int)
signal pulverizacao_progresso(percentual: float)

@export var mission_id: String = ""
@export var objective_id: String = ""
@export var quantidade_necessaria: int = 5
@export var quantidade_maxima: int = 400
@export var cena_milho: String = "res://scenes/world/milho_plantavel.tscn"
@export var distancia_max_plantio: float = 15.0
@export var raio_pulverizacao: float = 3.0
@export var percentual_necessario: float = 0.8

var _milhos_plantados: int = 0
var _cena_milho: PackedScene
var _player: Node3D = null
var _camera: Camera3D = null
var _drone: Node3D = null
var _milhos_pulverizados: Array = []
var _nos_milhos: Array[Vector3] = []       # Apenas posições (não nós!)
var _chaves_posicoes: Dictionary = {}
var _chaves_pulverizadas: Dictionary = {}
var _salvar_agendado := false
var _objetivo_concluido := false
var _em_missao_pulverizacao: bool = false

# Referência ao MultiMesh (criado em _ready)
var _multimesh: MultiMeshInstance3D = null
var _multimesh_data: MultiMesh = null
var _instancias_array: Array[Transform3D] = []

func _ready() -> void:
	_cena_milho = load(cena_milho) as PackedScene
	if _cena_milho == null:
		push_error("AreaPlantioMultiMesh: cena do milho não encontrada: " + cena_milho)
	
	add_to_group("area_plantio")
	
	_player = get_tree().get_first_node_in_group("jogador") as Node3D
	_camera = get_viewport().get_camera_3d()
	_drone = get_tree().get_first_node_in_group("drone_jogador") as Node3D
	
	# Cria o MultiMesh3D (um único nó de renderização para todos os milhos)
	_criar_multimesh()
	
	# Restaura os milhos já plantados
	if SaveSystem != null and SaveSystem.dados.has("milhos_plantados_posicoes"):
		call_deferred("_restaurar_milhos_salvos")
	
	_reindexar_posicoes_salvas()
	_reindexar_pulverizados_salvos()
	
	set_process_input(true)
	
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm != null and mm.has_signal("mission_changed") and not mm.is_connected("mission_changed", _on_missao_pulverizacao_mudou):
		mm.mission_changed.connect(_on_missao_pulverizacao_mudou)
	var ativa: Variant = mm.get_missao_ativa()
	if ativa != null and str(ativa.mission_id) == "operacao_drone_milho":
		_em_missao_pulverizacao = true

func _criar_multimesh() -> void:
	# Obtém a malha do milho da cena
	var cena := _cena_milho.instantiate()
	var milho_mesh := cena.get_node_or_null("Milho/MeshInstance3D") as MeshInstance3D
	if milho_mesh == null:
		# Fallback: tenta qualquer MeshInstance3D na cena
		milho_mesh = cena.find_child("MeshInstance3D", true, false) as MeshInstance3D
	cena.queue_free()
	
	if milho_mesh == null or milho_mesh.mesh == null:
		push_error("AreaPlantioMultiMesh: não foi possível encontrar a malha do milho.")
		return
	
	_multimesh = MultiMeshInstance3D.new()
	_multimesh.name = "MilhosMultiMesh"
	
	var mm := MultiMesh.new()
	mm.mesh = milho_mesh.mesh
	mm.instance_count = quantidade_maxima
	mm.transform_format = MultiMesh.TRANSFORM_3D
	
	_multimesh.multimesh = mm
	_multimesh_data = mm
	
	# Array de transformes (começa com identidades)
	_instancias_array.resize(quantidade_maxima)
	for i in quantidade_maxima:
		_instancias_array[i] = Transform3D.IDENTITY
	
	add_child(_multimesh)
	set_multi_meshes()

func set_multi_meshes() -> void:
	# Aplica o array de transformes ao MultiMesh
	if _multimesh_data == null:
		return
	_multimesh_data.instance_count = _milhos_plantados
	for i in _milhos_plantados:
		_multimesh_data.set_instance_transform(i, _instancias_array[i])

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interagir"):
		return
	if not _esta_ativa():
		return
	
	var player = get_tree().get_first_node_in_group("jogador") as Node3D
	if player == null:
		return
	
	var dist := global_position.distance_to(player.global_position)
	if dist > distancia_max_plantio:
		return
	
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
	query.collision_mask = 0xFFFFFFFF
	var resultado := space_state.intersect_ray(query)
	
	if resultado.is_empty():
		return
	
	var ponto := resultado.position as Vector3
	if not _ponto_dentro_da_area(ponto):
		return
	
	_plantar_milho(ponto)

func _ponto_dentro_da_area(ponto: Vector3) -> bool:
	var shape := _achar_collision_shape()
	if shape == null:
		return true
	var dist := global_position.distance_to(ponto)
	var raio_efetivo := 8.0
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
		push_error("AreaPlantioMultiMesh: limite máximo atingido.")
		return
	if _cena_milho == null:
		return
	
	var espacamento := 1.0
	var direcao := Vector3.RIGHT
	
	for i in 3:
		if _milhos_plantados >= quantidade_maxima:
			break
		
		var pos := ponto + direcao * (i - 1) * espacamento
		pos += Vector3(0, 0.1, 0)  # pequeno desvio para não ficar no chão
		
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var rot_y := rng.randf_range(0, TAU)
		var escala := 0.9 + rng.randf_range(0, 0.2)  # variação leve de escala
		
		var t := Transform3D(Basis(Vector3.UP, rot_y), pos)
		t = t.rotated(Vector3.RIGHT, 0.0)  # mantém vertical
		# Aplica escala uniforme (se o MultiMesh suportar scale)
		# Nota: MultiMesh TRANSFORM_3D inclui escala se usar Transform3D com basis escalado
		
		_instancias_array[_milhos_plantados] = t
		_milhos_plantados += 1
		_nos_milhos.append(pos)
		
		milho_plantado.emit(pos)
		
		_salvar_posicao_milho(pos, Vector3(0, rot_y, 0))
	
	set_multi_meshes()  # atualiza o MultiMesh (1 draw call)
	
	if not _objetivo_concluido and _milhos_plantados >= quantidade_necessaria:
		_objetivo_concluido = true
		plantio_completo.emit(_milhos_plantados)
		_completar_objetivo()
	
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

func get_quantidade_plantada() -> int:
	return _milhos_plantados

func resetar() -> void:
	_milhos_plantados = 0
	_milhos_pulverizados.clear()
	_chaves_pulverizadas.clear()
	_objetivo_concluido = false
	_nos_milhos.clear()
	_instancias_array.resize(quantidade_maxima)
	for i in quantidade_maxima:
		_instancias_array[i] = Transform3D.IDENTITY
	set_multi_meshes()

func _ja_foi_pulverizado(posicao: Vector3) -> bool:
	var chave := _chave_posicao(posicao)
	return _chaves_pulverizadas.has(chave)

func _percentual_pulverizado() -> float:
	if _milhos_plantados == 0:
		return 0.0
	return float(_milhos_pulverizados.size()) / float(_milhos_plantados)

func _atualizar_progresso_pulverizacao() -> void:
	var percentual := _percentual_pulverizado()
	pulverizacao_progresso.emit(percentual)
	
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm == null:
		return
	var ativa: Variant = mm.get_missao_ativa()
	var mid_ativa: String = str(ativa.mission_id) if ativa != null else ""
	
	var mid_usar: String = mission_id
	var obj_usar: String = objective_id
	if not mid_ativa.is_empty() and mid_ativa == "operacao_drone_milho":
		mid_usar = "operacao_drone_milho"
		obj_usar = "pulverizar_milho"
	
	if not mid_usar.is_empty() and not obj_usar.is_empty():
		var m = mm.get_mission(mid_usar)
		if m != null and m.has_method("atualizar_progresso_objetivo"):
			m.atualizar_progresso_objetivo(obj_usar, percentual)
	
	if percentual >= percentual_necessario:
		if is_instance_valid(Jogo):
			Jogo.registrar_descoberta("milho_pulverizado")

func _on_drone_pulverizando(posicao: Vector3) -> void:
	if not _em_missao_pulverizacao:
		return
	if not _ponto_dentro_da_area(posicao):
		return
	
	var raio2 := raio_pulverizacao * raio_pulverizacao
	var pulverizou_algo := false
	
	# Otimização: itera sobre posições (Vector3), não nós
	for milho_pos in _nos_milhos:
		var diff := milho_pos - posicao
		diff.y = 0.0
		if diff.length_squared() <= raio2:
			if not _ja_foi_pulverizado(milho_pos):
				_marcar_milho_pulverizado(milho_pos)
				_milhos_pulverizados.append(milho_pos)
				pulverizou_algo = true
	
	if pulverizou_algo:
		_atualizar_progresso_pulverizacao()
		_agendar_salvar()

func _marcar_milho_pulverizado(posicao: Vector3) -> void:
	# Com MultiMesh não podemos mudar material por instância facilmente,
	# então marcamos apenas logicamente. Para visual, considere usar
	# uma cor diferente por instância via MultiMesh.INSTANCE_COLOR_8BIT.
	_salvar_milho_pulverizado(posicao)

func _salvar_milho_pulverizado(posicao: Vector3) -> void:
	var pulverizados: Array = SaveSystem.dados.get("milhos_pulverizados_posicoes", [])
	if pulverizados == null:
		pulverizados = []
	var chave := _chave_posicao(posicao)
	if _chaves_pulverizadas.has(chave):
		return
	pulverizados.append({"x": posicao.x, "y": posicao.y, "z": posicao.z})
	SaveSystem.dados["milhos_pulverizados_posicoes"] = pulverizados
	_chaves_pulverizadas[chave] = true

func _salvar_posicao_milho(posicao: Vector3, rotacao: Vector3) -> void:
	var posicoes: Array = SaveSystem.dados.get("milhos_plantados_posicoes", [])
	if posicoes == null:
		posicoes = []
	var chave := _chave_posicao(posicao)
	if _chaves_posicoes.has(chave):
		return
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

func _agendar_salvar() -> void:
	if not _salvar_agendado:
		_salvar_agendado = true
		call_deferred("_fazer_salvar")

func _fazer_salvar() -> void:
	_salvar_agendado = false
	# Salvamento em disco ocorre via Jogo ao concluir missão

func _chave_posicao(pos: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [pos.x, pos.y, pos.z]

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

func _restaurar_milhos_salvos() -> void:
	var posicoes: Array = SaveSystem.dados.get("milhos_plantados_posicoes", [])
	if posicoes == null or posicoes.is_empty():
		return
	if _cena_milho == null:
		return
	
	var restaurados := 0
	for entrada in posicoes:
		if not (entrada is Dictionary):
			continue
		if _milhos_plantados >= quantidade_maxima:
			break
		
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
		
		var t := Transform3D(Basis(Vector3.UP, rot.y), pos)
		_instancias_array[_milhos_plantados] = t
		_nos_milhos.append(pos)
		_milhos_plantados += 1
		restaurados += 1
		
		if _posicao_foi_pulverizada(pos):
			_milhos_pulverizados.append(pos)
	
	set_multi_meshes()
	print("[AreaPlantioMultiMesh] Milhos restaurados: ", restaurados)

func _posicao_foi_pulverizada(posicao: Vector3) -> bool:
	var chave := _chave_posicao(posicao)
	return _chaves_pulverizadas.has(chave)