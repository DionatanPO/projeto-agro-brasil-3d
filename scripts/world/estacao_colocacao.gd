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
var _em_missao_estacao: bool = false  # Processa apenas durante a missão "colocar_estacao"
var _mission_manager: Node = null
var _preview_frame_skip: int = 0  # Throttle de atualização do preview


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
	
	# Conecta ao MissionManager para ativar/desativar processamento por missão
	# Usa call_deferred para garantir que o MissionManager terminou seu _ready()
	var mm: Node = get_node_or_null("/root/MissionManager")
	_mission_manager = mm
	if mm != null and mm.has_signal("mission_changed") and not mm.is_connected("mission_changed", _on_missao_estacao_mudou):
		mm.mission_changed.connect(_on_missao_estacao_mudou)
	
	set_process_unhandled_input(true)
	set_process(false)  # Será habilitado por _verificar_missao_inicial após o frame
	
	# Esconde anel agora (padrão: oculto) e reavalia após todos os nós estarem prontos
	_atualizar_visibilidade_anel()
	call_deferred("_verificar_missao_inicial")


func _verificar_missao_inicial() -> void:
	"""Chamado via call_deferred para checar a missão após todos os autoloads estarem prontos."""
	var mm: Node = _mission_manager
	if mm == null:
		mm = get_node_or_null("/root/MissionManager")
		_mission_manager = mm
	var ativa: Variant = mm.get_missao_ativa() if mm != null else null
	_em_missao_estacao = (ativa != null and str(ativa.mission_id) == "colocar_estacao")
	set_process(_em_missao_estacao)
	_atualizar_visibilidade_anel()


func _process(delta: float) -> void:
	if not _em_missao_estacao:
		return
	if not _modo_preview or _estacao_colocada:
		return
	
	# Throttle: atualiza o preview a cada 3 frames (~10x/s a 30 FPS)
	_preview_frame_skip += 1
	if _preview_frame_skip < 3:
		return
	_preview_frame_skip = 0
	
	# Atualiza preview seguindo o mouse/raycast
	_atualizar_preview()


func _unhandled_input(event: InputEvent) -> void:
	# Filtra a ação PRIMEIRO: _unhandled_input recebe TODO evento, inclusive
	# movimento de mouse, que chega dezenas de vezes por segundo. Qualquer
	# consulta antes daqui rodaria nesse ritmo e derruba o FPS.
	if not _modo_preview:
		if not event.is_action_pressed("interagir"):
			return
	else:
		if not (event.is_action_released("interagir") or event.is_action_pressed("ui_cancel")):
			return
	
	if not _esta_ativa():
		return
	
	if not _modo_preview:
		# Fora do preview: pressionar "interagir" (E/X) entra no modo preview
		# (mesmo se a estação já foi colocada, permite reposicionar)
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
	
	# Desabilita sombras, GI e culling no preview para evitar spike de GPU
	_otimizar_preview(_preview_instance)
	
	# Adiciona o preview na árvore de cena (fallback para root se current_scene falhar)
	var pai := get_tree().current_scene
	if pai == null:
		pai = get_parent()
	if pai == null:
		pai = get_tree().root
	if pai:
		pai.add_child(_preview_instance)
	else:
		push_error("[EstacaoColocacao] _iniciar_preview: não foi possível adicionar preview à cena (pai null)")
	
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
		_definir_cor_preview(Color.RED)
		_posicao_preview = Vector3.ZERO
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
	
	# Esconde o anel ao colocar a estação
	_atualizar_visibilidade_anel()
	
	# Salva a posição
	_salvar_posicao_estacao(estacao.global_position, estacao.rotation)
	
	estacao_colocada.emit(estacao.global_position)
	colocacao_completa.emit()
	_completar_objetivo()


func _cancelar_preview() -> void:
	if _preview_instance != null:
		_preview_instance.queue_free()
		_preview_instance = null
	_modo_preview = false
	_posicao_preview = Vector3.ZERO


func _tornar_ghost(node: Node3D) -> void:
	"""Torna o nó semitransparente para preview (recursivo)."""
	if node is MeshInstance3D:
		var mat = node.get_surface_override_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			node.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.5, 0.8, 1.0, 0.4)
			mat.cull_mode = StandardMaterial3D.CULL_DISABLED
	for child in node.get_children():
		_tornar_ghost(child as Node3D if child is Node3D else node)


func _otimizar_preview(node: Node) -> void:
	"""Desabilita sombras, GI e occlusion culling em todo o preview para evitar spike de GPU."""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.ignore_occlusion_culling = true
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children():
		_otimizar_preview(child)


func _definir_cor_preview(cor: Color) -> void:
	if _preview_instance == null:
		return
	_aplicar_cor_recursivo(_preview_instance, cor)


func _aplicar_cor_recursivo(node: Node, cor: Color) -> void:
	"""Aplica a cor ghost recursivamente em toda hierarquia do preview."""
	if node is MeshInstance3D:
		var mat = (node as MeshInstance3D).get_surface_override_material(0)
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).albedo_color = Color(cor.r, cor.g, cor.b, 0.4)
	for child in node.get_children():
		_aplicar_cor_recursivo(child, cor)


func _atualizar_visibilidade_anel() -> void:
	"""Mostra o anel vermelho apenas enquanto a missão estiver ativa e a estação não colocada."""
	var anel := get_node_or_null("AreaEstacaoVisual") as MeshInstance3D
	if anel != null:
		anel.visible = _em_missao_estacao and not _estacao_colocada


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
	
	# Cria o StaticBody com colisão DESABILITADA inicialmente (layer 0, mask 0).
	# Isso evita que o colisor estático recém-criado empurre o drone ou o
	# trator fisicamente caso estejam sobrepostos com a estação. Eles ficam
	# exatamente onde estão, sem ser movidos.
	var static_body = StaticBody3D.new()
	static_body.name = "EstacaoCollision"
	static_body.collision_layer = 0
	static_body.collision_mask = 0
	
	# Estima o tamanho baseado no bounds do mesh
	var aabb := _calcular_aabb(node)
	var shape = BoxShape3D.new()
	shape.size = aabb.size
	
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position = aabb.position + aabb.size * 0.5
	
	static_body.add_child(collision)
	node.add_child(static_body)
	
	# Habilita a colisão no próximo frame, depois que a posição já está
	# estabelecida e não há risco de empurrão físico nos veículos.
	call_deferred("_habilitar_colisao_estacao", static_body)


func _habilitar_colisao_estacao(static_body: StaticBody3D) -> void:
	if is_instance_valid(static_body):
		# Camada 2 = estruturas/ambiente (mesma de pedras e árvores)
		# Mask 4 = colide apenas com o terreno, nunca com jogador/trator/drone (camada 1)
		static_body.collision_layer = 2
		static_body.collision_mask = 4


func _calcular_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var primeiro := true
	for child in node.get_children():
		var child_aabb: AABB
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			child_aabb = (child as MeshInstance3D).mesh.get_aabb()
			child_aabb = (child as MeshInstance3D).transform * child_aabb
		elif child is Node3D:
			child_aabb = _calcular_aabb(child as Node3D)
		else:
			continue
		if primeiro:
			aabb = child_aabb
			primeiro = false
		else:
			aabb = aabb.merge(child_aabb)
	return aabb


func _on_missao_estacao_mudou(mission_id: Variant) -> void:
	var mid: String = str(mission_id)
	_em_missao_estacao = (mid == "colocar_estacao")
	set_process_unhandled_input(true)  # Mantém input ativo; _esta_ativa() filtra dentro de _unhandled_input
	set_process(_em_missao_estacao)  # _process só roda se a missão estiver ativa (atualiza preview)
	_atualizar_visibilidade_anel()
	if not _em_missao_estacao:
		_modo_preview = false
		if _preview_instance != null:
			_preview_instance.queue_free()
			_preview_instance = null
		_posicao_preview = Vector3.ZERO


func _esta_ativa() -> bool:
	if mission_id.is_empty():
		return true
	var mm: Node = _mission_manager
	if mm == null or not is_instance_valid(mm):
		return false
	var ativa: Variant = mm.get_missao_ativa()
	return ativa != null and str(ativa.mission_id) == mission_id


func _completar_objetivo() -> void:
	if is_instance_valid(Jogo):
		Jogo.registrar_descoberta("estacao_colocada")
	
	var mm: Node = _mission_manager
	if mm != null and is_instance_valid(mm):
		mm.completar_objetivo(mission_id, objective_id)


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
	# Gravacao em disco ocorre apenas ao concluir missao/subobjetivo (via Jogo)


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
		
		# Completa o objetivo da missão se ainda não estiver completo
		var mm: Node = _mission_manager
		if mm != null and is_instance_valid(mm):
			mm.completar_objetivo(mission_id, objective_id)


func get_estacao_colocada() -> bool:
	return _estacao_colocada