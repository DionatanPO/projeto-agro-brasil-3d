extends Area3D
## Area que marca o local da encomenda (primeiro objetivo da missao 1).
## Area grande no centro do mapa (clareira com estrada).
## Anel transparente + caixa central com interacao E para abrir pacote.

var _player_perto_caixa := false
var _pacote_aberto := false
var _dialogo_local_tocado := false
var _aguardando_fim_dialogo_agrobot := false
var _agrobot: Node3D = null
var _caixa: MeshInstance3D = null
var _marcador: MeshInstance3D = null


func _ready() -> void:
	print("[AreaEncomenda] _ready - posicao: " + str(global_position))
	_montar_colisor()
	DialogoManager.dialogo_finalizado.connect(_on_dialogo_finalizado)

	# Se o agrobot ja foi recolhido numa sessao anterior, a caixa nao volta:
	# ele reaparece direto seguindo o jogador.
	if bool(SaveSystem.dados.get("agrobot_coletado", false)):
		_pacote_aberto = true
		_restaurar_agrobot.call_deferred()
		return

	_marcar_area()
	_caixa_central()
	_iniciar_verificacao_jogador()
	body_entered.connect(_on_body_entered)


## Recria o agrobot ao carregar o jogo (progresso salvo).
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


func _marcar_area() -> void:
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


func _caixa_central() -> void:
	print("[AreaEncomenda] Criando CaixaCentral em: " + str(global_position))
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
	print("[AreaEncomenda] CaixaCentral adicionada como filho: " + str(inst))


## Um unico Timer reaproveitado. Antes era criado um Timer novo a cada 0,5 s,
## o que acumulava milhares de nos na cena.
func _iniciar_verificacao_jogador() -> void:
	var timer = Timer.new()
	timer.name = "CheckPlayerTimer"
	timer.wait_time = 0.5
	timer.timeout.connect(_verificar_distancia_jogador)
	add_child(timer)
	timer.start()


func _verificar_distancia_jogador() -> void:
	if _pacote_aberto:
		_player_perto_caixa = false
		return
	var player = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if player == null:
		return
	var distancia = global_position.distance_to(player.global_position)
	var era_perto := _player_perto_caixa
	_player_perto_caixa = distancia <= 6.0
	if _player_perto_caixa and not era_perto:
		print("Area encomenda: jogador proximo da caixa (dist: " + str(distancia) + ") - pressione E para abrir pacote")


func _montar_colisor() -> void:
	var shape = CylinderShape3D.new()
	shape.radius = 50.0
	shape.height = 1.0
	var col = CollisionShape3D.new()
	col.name = "FormaEncomenda"
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	add_child(col)


func _on_body_entered(body: Node3D) -> void:
	if body == null:
		return
	if not body.is_in_group("jogador"):
		return
	if Jogo == null:
		return
	if _dialogo_local_tocado:
		return
	
	# Só toca o áudio se a descoberta for NOVA (primeira vez na área)
	# E se a missão 1 ainda não foi concluída.
	var descobertas: Array = SaveSystem.dados.get("descobertas", [])
	var missao1_concluida: bool = "primeira_entrega" in SaveSystem.dados.get("missoes_concluidas", [])
	
	if "local_encomenda" in descobertas or missao1_concluida:
		# Já veio aqui antes ou missão 1 já acabou: não repete o áudio
		_dialogo_local_tocado = true
		return
	
	_dialogo_local_tocado = true
	Jogo.registrar_descoberta("local_encomenda")
	DialogoManager.tocar("dialogo2")
	print("Area encomenda: jogador entrou na area central, dialogo 2 iniciado.")


func _unhandled_input(event: InputEvent) -> void:
	if not _player_perto_caixa or _pacote_aberto:
		return
	if event.is_action_pressed("interagir"):
		_pacote_aberto = true
		_abrir_pacote()


func _abrir_pacote() -> void:
	print("[AreaEncomenda] Abrindo pacote...")
	
	# Esconde a caixa (ela e criada em runtime, entao find_child("CaixaCentral")
	# nao a encontra: o dono e null e find_child filtra por owner por padrao).
	if _caixa != null and is_instance_valid(_caixa):
		print("[AreaEncomenda] Escondendo caixa: " + str(_caixa))
		_caixa.visible = false
		_caixa.queue_free()
	else:
		print("[AreaEncomenda] ERRO: CaixaCentral nao encontrada!")
	
	# O marcador gigante da area tambem sai, para nao poluir a visao.
	if _marcador != null and is_instance_valid(_marcador):
		_marcador.visible = false
	
	_instanciar_agrobot()
	DialogoManager.tocar("dialogo agrobot 1")
	_aguardando_fim_dialogo_agrobot = true


func _instanciar_agrobot() -> void:
	print("[AreaEncomenda] Instanciando Agrobot...")
	
	var agrobot_scene = preload("res://character/scenes/agrobot.tscn") as PackedScene
	if agrobot_scene == null:
		print("[AreaEncomenda] ERRO: cena do Agrobot nao encontrada em res://character/scenes/agrobot.tscn")
		return
	var agrobot = agrobot_scene.instantiate()
	if agrobot == null:
		print("[AreaEncomenda] ERRO: falha ao instanciar Agrobot")
		return
	agrobot.name = "Agrobot"
	
	# Adiciona como filho do pai (Node3D raiz do mundo) - mais confiável que current_scene
	var pai := get_parent()
	if pai == null:
		pai = get_tree().current_scene
	pai.add_child(agrobot)
	
	# Posicao de spawn: sobre a cabeca do jogador
	var player = get_tree().get_first_node_in_group("jogador") as Node3D
	var posicao_jogador := global_position
	if player != null:
		posicao_jogador = player.global_position
	else:
		print("[AreaEncomenda] AVISO: Jogador nao encontrado, usando posicao da area: ", global_position)
	
	if agrobot.has_method("ativar"):
		agrobot.ativar(posicao_jogador)
	print("[AreaEncomenda] Agrobot adicionado. Pos final: ", agrobot.global_position)
	
	# Marca que o agrobot foi coletado (persiste no save)
	if not bool(SaveSystem.dados.get("agrobot_coletado", false)):
		SaveSystem.dados["agrobot_coletado"] = true
		SaveSystem.salvar()
	
	# Guardar referência para o diálogo final
	_agrobot = agrobot


func _on_dialogo_finalizado(id: String) -> void:
	if _aguardando_fim_dialogo_agrobot and id == "dialogo agrobot 1":
		_aguardando_fim_dialogo_agrobot = false
		if Jogo != null:
			Jogo.registrar_descoberta("pacote")
		print("Area encomenda: dialogo agrobot 1 finalizado, pacote registrado, missao concluida.")