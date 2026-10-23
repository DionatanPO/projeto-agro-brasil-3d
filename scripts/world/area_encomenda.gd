extends Area3D
## Area que marca o local da encomenda (primeiro objetivo da missao 1).

func _ready() -> void:
	var shape = CylinderShape3D.new()
	shape.radius = 6.0
	shape.height = 4.0
	var col = CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body == null:
		return
	if not body.is_in_group("jogador"):
		return
	if Jogo == null:
		return
	Jogo.registrar_descoberta("local_encomenda")
	print("Area encomenda: jogador chegou ao local.")
