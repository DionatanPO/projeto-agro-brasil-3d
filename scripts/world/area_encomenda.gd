extends Area3D
## Area que marca o local da encomenda (primeiro objetivo da missao 1).
## Exibe um disco colorido no chão para o jogador localizar a regiao.

func _ready() -> void:
	_marcar_area()
	body_entered.connect(_on_body_entered)


func _marcar_area() -> void:
	var mesh = CylinderMesh.new()
	mesh.radius = 6.0
	mesh.height = 0.2
	var inst = MeshInstance3D.new()
	inst.name = "MarcadorEncomenda"
	inst.mesh = mesh
	inst.position = Vector3(0, 0.11, 0)  # fica rente ao chão
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.8, 0.2, 0.6)  # amarelo translúcido
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	inst.material_override = mat
	add_child(inst)


func _on_body_entered(body: Node3D) -> void:
	if body == null:
		return
	if not body.is_in_group("jogador"):
		return
	if Jogo == null:
		return
	Jogo.registrar_descoberta("local_encomenda")
	print("Area encomenda: jogador chegou ao local.")
