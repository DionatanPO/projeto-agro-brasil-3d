extends Node3D
## AreaEncomenda: lógica específica da missão "Primeira Entrega".
## - Cria a caixa central e gerencia a interação (E)
## - Spawna o Agrobot e registra a descoberta "pacote" ao abrir
##
## O diálogo de chegada (dialogo 2) fica num AreaTrigger separado na cena,
## configurado via inspector e resolvido pelo DialogueManager.
## O diálogo ao abrir a caixa é disparado pelo trigger "objective_completed"
## de "encontrar_encomenda" (data/dialogues/missions/primeira_entrega.json).

class_name AreaEncomenda

@export var mission_id: String = "primeira_entrega"
@export var objective_id_caixa: String = "encontrar_encomenda"
@export var discovery_pacote: String = "pacote"
@export var distancia_interacao: float = 6.0

var _pacote_aberto := false
var _agrobot: Node3D = null
var _caixa: MeshInstance3D = null
var _marcador: MeshInstance3D = null


func _ready() -> void:
	# Sessão anterior já coletou o Agrobot: restaura o companheiro e não recria a caixa.
	if bool(SaveSystem.dados.get("agrobot_coletado", false)):
		_pacote_aberto = true
		_restaurar_agrobot.call_deferred()
		return

	_montar_marcador()
	_criar_caixa()


func _montar_marcador() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 35.0
	mesh.bottom_radius = 35.0
	mesh.height = 2.0

	var inst := MeshInstance3D.new()
	inst.name = "MarcadorEncomenda"
	inst.mesh = mesh
	inst.position = Vector3(0, 3.0, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.3, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = mat

	add_child(inst)
	_marcador = inst


func _criar_caixa() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 2.0, 2.0)

	var inst := MeshInstance3D.new()
	inst.name = "CaixaCentral"
	inst.mesh = mesh
	inst.position = Vector3(0, 1.0, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 1.0)
	inst.material_override = mat

	add_child(inst)
	_caixa = inst


## Interação com a caixa ─────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _pacote_aberto:
		return
	if not event.is_action_pressed("interagir"):
		return

	var player := get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if player == null:
		return
	if global_position.distance_to(player.global_position) > distancia_interacao:
		return

	_abrir_pacote()


func _abrir_pacote() -> void:
	if _pacote_aberto:
		return
	_pacote_aberto = true

	if _caixa != null and is_instance_valid(_caixa):
		_caixa.queue_free()
		_caixa = null

	if _marcador != null and is_instance_valid(_marcador):
		_marcador.queue_free()
		_marcador = null

	_instanciar_agrobot()

	# Descoberta "pacote" -> objetivo "encontrar_encomenda" -> diálogo + missão concluída.
	if is_instance_valid(Jogo):
		Jogo.registrar_descoberta(discovery_pacote)
	print("[AreaEncomenda] Pacote aberto; descoberta '", discovery_pacote, "' registrada.")


func _instanciar_agrobot() -> void:
	var agrobot_scene := preload("res://character/scenes/agrobot.tscn") as PackedScene
	if agrobot_scene == null:
		push_error("[AreaEncomenda] cena do Agrobot não encontrada.")
		return

	var agrobot := agrobot_scene.instantiate()
	if agrobot == null:
		push_error("[AreaEncomenda] falha ao instanciar o Agrobot.")
		return
	agrobot.name = "Agrobot"

	var pai := get_parent()
	if pai == null:
		pai = get_tree().current_scene
	pai.add_child(agrobot)

	var player := get_tree().get_first_node_in_group("jogador") as Node3D
	var pos_spawn: Vector3 = player.global_position if player != null else global_position

	if agrobot.has_method("ativar"):
		agrobot.ativar(pos_spawn)
	else:
		agrobot.global_position = pos_spawn

	_agrobot = agrobot

	if not bool(SaveSystem.dados.get("agrobot_coletado", false)):
		SaveSystem.dados["agrobot_coletado"] = true
		SaveSystem.salvar()


## Restauração de progresso salvo ────────────────────────────────────────────

func _restaurar_agrobot() -> void:
	for _i in 60:
		await get_tree().process_frame
		var player := get_tree().get_first_node_in_group("jogador") as Node3D
		if player == null:
			continue
		if get_tree().get_first_node_in_group("agrobot") != null:
			return
		print("[AreaEncomenda] Restaurando Agrobot do save.")
		_instanciar_agrobot()
		return
