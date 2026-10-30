extends Area3D
## EstacaoColocacao: área onde o jogador pode colocar a estação meteorológica.
##
## Uso:
## 1. Colocar um Area3D na área desejada do mapa
## 2. Adicionar este script
## 3. Configurar: mission_id, objective_id, cena_estacao
## 4. O jogador pressiona "interagir" (E) dentro da área para colocar a estação

class_name EstacaoColocacao

signal estacao_colocada(posicao: Vector3)
signal colocacao_completa()

@export var mission_id: String = ""
@export var objective_id: String = ""
@export var cena_estacao: String = "res://assets/models/estacao.glb"
@export var distancia_max_colocacao: float = 10.0
@export var requer_superficie_plana: bool = true
@export var tolerancia_inclinacao: float = 15.0  # graus

var _estacao_colocada: bool = false
var _cena_estacao: PackedScene
var _player: Node3D = null
var _camera: Camera3D = null
var _posicao_preview: Vector3 = Vector3.ZERO
var _preview_instance: Node3D = null
var _modo_preview: bool = false


func _ready() -> void:
	_cena_estacao = load(cena_estacao) as PackedScene
	if _cena_estacao == null:
		push_error("EstacaoColocacao: cena da estação não encontrada: " + cena_estacao)
	
	add_to_group("estacao_colocacao")
	
	_player = get_tree().get_first_node_in_group("jogador") as Node3D
	_camera = get_viewport().get_camera_3d()
	
	# Restaura estação já colocada (persistência)
	if SaveSystem != null and SaveSystem.dados.has("estacao_posicao"):
		call_deferred("_restaurar_estacao_salva")
	
	set_process_input(true)
	set_process(true)


func _process(delta: float) -> void:
	if not _modo_preview or _estacao_colocada:
		return
	
	# Atualiza preview seguindo o mouse/raycast
	_atualizar_preview()


func _unhandled_input(event: InputEvent) -> void:
	if _estacao_colocada:
		return
	
	if not _esta_ativa():
		return
	
	if not _modo_preview:
		# Fora do preview: pressionar "interagir" (E/X) entra no modo preview
		if event.is_action_pressed("interagir"):
			_iniciar_preview()
	else:
		# Dentro do preview:
		# Soltar a tecla em posição válida (verde) = confirma colocação
		# Soltar em posição inválida (vermelho/amarelo) = cancela
		if event.is_action_released("interagir"):
			if _posicao_preview != Vector3.ZERO:
				_tentar_colocar_estacao()
			else:
				_cancelar_preview()
		elif event.is_action_pressed("ui_cancel"):
			# ESC cancela o preview
			_cancelar_preview()


func _iniciar_preview() -> void:
	var player = get_tree().get_first_node_in_group("jogador") as Node3D
	if player == null:
		return
	
	var dist := global_position.distance_to(player.global_position)
	if dist > distancia_max_colocacao:
		return
	
	_modo_preview = true
	
	# Instancia o preview (versão semitransparente/ghost)
	_preview_instance = _cena_estacao.instantiate()
	if _preview_instance == null:
		push_error("EstacaoColocacao: falha ao instanciar preview da estação")
		_modo_preview = false
		return
	
	# Torna o preview semitransparente (ghost)
	_tornar_ghost(_preview_instance)
	
	var pai := get_tree().current_scene
	if pai == null:
		pai = get_parent()
	if pai:
		pai.add_child(_preview_instance)
	
	_atualizar_preview()


func _atualizar_preview() -> void:
	if _preview_instance == null:
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
	
	# Verifica se está dentro da área
	if not _ponto_dentro_da_area(ponto):
		# Mostra preview vermelho (inválido)
		_definir_cor_preview(Color.RED)
		_posicao_preview = Vector3.ZERO
		return
	
	# Verifica inclinação do terreno
	if requer_superficie_plana:
		var normal := resultado.normal as Vector3
		var angulo := rad_to_deg(acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)))
		if angulo > tolerancia_inclinacao:
			_definir_cor_preview(Color.YELLOW)
			_posicao_preview = Vector3.ZERO
			return
	
	# Posição válida - verde
	_definir_cor_preview(Color.GREEN)
	_posicao_preview = ponto
	_preview_instance.global_position = ponto + Vector3(0, 0.1, 0)


func _tentar_colocar_estacao() -> void:
	if _posicao_preview == Vector3.ZERO:
		print("[EstacaoColocacao] Posição inválida para colocação")
		return
	
	if _cena_estacao == null:
		return
	
	# Instancia a estação real
	var estacao := _cena_estacao.instantiate()
	if estacao == null:
		push_error("EstacaoColocacao: falha ao instanciar estação")
		return
	
	var pai := get_tree().current_scene
	if pai == null:
		pai = get_parent()
	if pai == null:
		estacao.queue_free()
		return
	
	# Salva a posição ANTES de cancelar o preview.
	# _cancelar_preview() zera _posicao_preview, então capturamos primeiro.
	var pos_final := _posicao_preview + Vector3(0, 0.1, 0)
	
	# Remove o preview
	_cancelar_preview()
	
	# Adiciona a estação real na posição do preview
	pai.add_child(estacao)
	estacao.global_position = pos_final
	
	# Adiciona collider se não tiver
	_adicionar_collider_se_precisar(estacao)
	
	_estacao_colocada = true
	estacao.add_to_group("estacao_meteorologica")
	
	# Salva a posição
	_salvar_posicao_estacao(estacao.global_position, estacao.rotation)
	
	estacao_colocada.emit(estacao.global_position)
	colocacao_completa.emit()
	_completar_objetivo()
	
	print("[EstacaoColocacao] Estação colocada em: ", estacao.global_position)


func _cancelar_preview() -> void:
	if _preview_instance != null:
		_preview_instance.queue_free()
		_preview_instance = null
	_modo_preview = false
	_posicao_preview = Vector3.ZERO


func _tornar_ghost(node: Node3D) -> void:
	"""Torna o nó semitransparente para preview."""
	for child in node.get_children():
		_tornar_ghost(child)
	
	if node is MeshInstance3D:
		var mat = node.get_surface_override_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			node.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.5, 0.8, 1.0, 0.4)
			mat.cull_mode = StandardMaterial3D.CULL_DISABLED


func _definir_cor_preview(cor: Color) -> void:
	if _preview_instance == null:
		return
	for child in _preview_instance.get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat is StandardMaterial3D:
				mat.albedo_color = Color(cor.r, cor.g, cor.b, 0.4)


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
	elif shape.shape is CylinderShape3D:
		raio_efetivo = (shape.shape as CylinderShape3D).radius
	
	return dist <= raio_efetivo


func _achar_collision_shape() -> CollisionShape3D:
	for filho in get_children():
		if filho is CollisionShape3D:
			return filho as CollisionShape3D
	return null


func _adicionar_collider_se_precisar(node: Node3D) -> void:
	"""Adiciona StaticBody3D + CollisionShape3D se a estação não tiver colisão."""
	# Verifica se já tem StaticBody3D
	for child in node.get_children():
		if child is StaticBody3D:
			return  # Já tem colisão
	
	# Cria um StaticBody3D simples com BoxShape3D aproximado
	var static_body = StaticBody3D.new()
	static_body.name = "EstacaoCollision"
	
	# Estima o tamanho baseado no bounds do mesh
	var aabb := _calcular_aabb(node)
	var shape = BoxShape3D.new()
	shape.size = aabb.size
	
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position = aabb.position + aabb.size * 0.5
	
	static_body.add_child(collision)
	node.add_child(static_body)
	static_body.collision_layer = 1
	static_body.collision_mask = 1


func _calcular_aabb(node: Node3D) -> AABB:
	var aabb = AABB()
	var primeiro = true
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var mesh_aabb = child.mesh.get_aabb()
			var transformed = mesh_aabb * child.global_transform
			if primeiro:
				aabb = transformed
				primeiro = false
			else:
				aabb = aabb.merge(transformed)
	for child in node.get_children():
		aabb = aabb.merge(_calcular_aabb(child))
	return aabb


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
		Jogo.registrar_descoberta("estacao_colocada")
	
	var mm: Variant = get_node_or_null("/root/MissionManager")
	if mm != null and mm.has_method("check_progress"):
		mm.check_progress({"mission_id": mission_id, "objective_id": objective_id})


func _salvar_posicao_estacao(posicao: Vector3, rotacao: Vector3) -> void:
	var entrada: Dictionary = {
		"x": posicao.x,
		"y": posicao.y,
		"z": posicao.z,
		"rx": rotacao.x,
		"ry": rotacao.y,
		"rz": rotacao.z,
	}
	SaveSystem.dados["estacao_posicao"] = entrada
	SaveSystem.dados["estacao_rotacao"] = entrada
	SaveSystem.salvar()


func _restaurar_estacao_salva() -> void:
	if _cena_estacao == null:
		return
	
	var pos_data: Dictionary = SaveSystem.dados.get("estacao_posicao", {})
	if not pos_data or not pos_data.has("x"):
		return
	
	if _estacao_colocada:
		return
	
	var estacao := _cena_estacao.instantiate()
	if estacao == null:
		return
	
	var pos := Vector3(
		float(pos_data.get("x", 0)),
		float(pos_data.get("y", 0)),
		float(pos_data.get("z", 0)),
	)
	var rot := Vector3(
		float(pos_data.get("rx", 0)),
		float(pos_data.get("ry", 0)),
		float(pos_data.get("rz", 0)),
	)
	
	var pai := get_tree().current_scene
	if pai == null:
		pai = get_parent()
	if pai:
		pai.add_child(estacao)
		estacao.global_position = pos
		estacao.rotation = rot
		_adicionar_collider_se_precisar(estacao)
		estacao.add_to_group("estacao_meteorologica")
		_estacao_colocada = true
		print("[EstacaoColocacao] Estação restaurada do save: ", pos)


func get_estacao_colocada() -> bool:
	return _estacao_colocada