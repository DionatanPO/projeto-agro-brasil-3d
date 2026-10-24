extends Node3D
## AreaEncomenda: Lógica específica da missão "Primeira Entrega".
## - Cria a caixa central e gerencia interação (E)
## - Spawna Agrobot e toca diálogo ao abrir
## - Registra descoberta "pacote" ao fim do diálogo
##
## A área de entrada (dialogo2 + discovery "local_encomenda") é um
## AreaTrigger separado na cena (world.tscn) configurado via inspector.

class_name AreaEncomenda

# Configuração via inspector
@export var mission_id: String = "primeira_entrega"
@export var objective_id_caixa: String = "encontrar_encomenda"
@export var discovery_pacote: String = "pacote"
@export var dialogo_agrobot: String = "dialogo agrobot 1"

# Estado interno
var _pacote_aberto := false
var _aguardando_fim_dialogo := false
var _agrobot: Node3D = null
var _caixa: MeshInstance3D = null
var _marcador: MeshInstance3D = null
var _timer_verificacao: Timer = null


func _ready() -> void:
	print("[AreaEncomenda] _ready - posicao: ", global_position)
	
	# Se já coletou o agrobot em sessão anterior, restaura e não cria caixa
	if bool(SaveSystem.dados.get("agrobot_coletado", false)):
		_pacote_aberto = true
		_restaurar_agrobot.call_deferred()
		return
	
	_montar_visual()
	_criar_caixa()
	_iniciar_verificacao_jogador()
	
	# Conecta fim de diálogo
	DialogoManager.dialogo_finalizado.connect(_on_dialogo_finalizado)


func _montar_visual() -> void:
	# Marcador visual da área (cilindro transparente)
	var mesh = CylinderMesh.new()
	mesh.top_radius = 35.0
	mesh.bottom_radius = 35.0
	mesh.height = 2.0
	var inst = MeshInstance3D.new()
	inst.name = "MarcadorEncomenda"
	inst.mesh = mesh
	inst.position = Vector3(0, 3.0, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.3, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = mat
	add_child(inst)
	_marcador = inst


func _criar_caixa() -> void:
	print("[AreaEncomenda] Criando CaixaCentral em: ", global_position)
	var mesh = BoxMesh.new()
	mesh.size = Vector3(2.0, 2.0, 2.0)
	var inst = MeshInstance3D.new()
	inst.name = "CaixaCentral"
	inst.mesh = mesh
	inst.position = Vector3(0, 1.0, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 1.0)
	inst.material_override = mat
	add_child(inst)
	_caixa = inst
	print("[AreaEncomenda] CaixaCentral adicionada: ", inst)


func _iniciar_verificacao_jogador() -> void:
	_timer_verificacao = Timer.new()
	_timer_verificacao.name = "CheckPlayerTimer"
	_timer_verificacao.wait_time = 0.5
	_timer_verificacao.timeout.connect(_verificar_distancia_jogador)
	add_child(_timer_verificacao)
	_timer_verificacao.start()


func _verificar_distancia_jogador() -> void:
	if _pacote_aberto:
		return
	var player = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if player == null:
		return
	var distancia = global_position.distance_to(player.global_position)
	# Apenas log - o prompt visual é gerenciado pelo AreaTrigger de interação
	if distancia <= 6.0:
		print("AreaEncomenda: jogador proximo da caixa (dist: ", distancia, ")")


## Restauração de progresso salvo ──────────────────────────────────────────

func _restaurar_agrobot() -> void:
	for i in 60:
		await get_tree().process_frame
		var player := get_tree().get_first_node_in_group("jogador") as Node3D
		if player == null:
			continue
		if get_tree().get_first_node_in_group("agrobot") != null:
			return
		print("[AreaEncomenda] Restaurando Agrobot do save.")
		_instanciar_agrobot()
		return


## Interação com a caixa ──────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _pacote_aberto:
		return
	
	var player = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if player == null:
		return
	
	var distancia = global_position.distance_to(player.global_position)
	if distancia > 6.0:
		return
	
	if event.is_action_pressed("interagir"):
		_abrir_pacote()


func _abrir_pacote() -> void:
	print("[AreaEncomenda] Abrindo pacote...")
	_pacote_aberto = true
	
	# Esconde caixa
	if _caixa != null and is_instance_valid(_caixa):
		print("[AreaEncomenda] Escondendo caixa: ", _caixa)
		_caixa.visible = false
		_caixa.queue_free()
	
	# Esconde marcador
	if _marcador != null and is_instance_valid(_marcador):
		_marcador.visible = false
	
	# Spawna Agrobot
	_instanciar_agrobot()
	
	# Toca diálogo do Agrobot
	DialogoManager.tocar(dialogo_agrobot)
	_aguardando_fim_dialogo = true


func _instanciar_agrobot() -> void:
	print("[AreaEncomenda] Instanciando Agrobot...")
	
	var agrobot_scene = preload("res://character/scenes/agrobot.tscn") as PackedScene
	if agrobot_scene == null:
		print("[AreaEncomenda] ERRO: cena não encontrada")
		return
	var agrobot = agrobot_scene.instantiate()
	if agrobot == null:
		print("[AreaEncomenda] ERRO: falha ao instanciar")
		return
	agrobot.name = "Agrobot"
	
	# Adiciona na árvore ANTES de setar posição
	var pai := get_parent()
	if pai == null:
		pai = get_tree().current_scene
	pai.add_child(agrobot)
	
	# Posiciona sobre a cabeça do jogador
	var player = get_tree().get_first_node_in_group("jogador") as Node3D
	var pos_spawn := global_position
	if player:
		pos_spawn = player.global_position
	
	if agrobot.has_method("ativar"):
		agrobot.ativar(pos_spawn)
	print("[AreaEncomenda] Agrobot adicionado. Pos: ", agrobot.global_position)
	
	# Marca coletado no save
	if not bool(SaveSystem.dados.get("agrobot_coletado", false)):
		SaveSystem.dados["agrobot_coletado"] = true
		SaveSystem.salvar()
	
	_agrobot = agrobot


## Fim do diálogo → registra "pacote" → MissionManager completa missão ──────

func _on_dialogo_finalizado(id: String) -> void:
	if _aguardando_fim_dialogo and id == dialogo_agrobot:
		_aguardando_fim_dialogo = false
		if is_instance_valid(Jogo):
			Jogo.registrar_descoberta(discovery_pacote)
		print("AreaEncomenda: diálogo finalizado, '", discovery_pacote, "' registrado.")


## Cleanup ────────────────────────────────────────────────────────────────

func _exit_tree() -> void:
	if _timer_verificacao and is_instance_valid(_timer_verificacao):
		_timer_verificacao.stop()
		_timer_verificacao.queue_free()
	if DialogoManager.has_signal("dialogo_finalizado"):
		DialogoManager.dialogo_finalizado.disconnect(_on_dialogo_finalizado)