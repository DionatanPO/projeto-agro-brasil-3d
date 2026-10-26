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
var _caixa: Node3D = null
var _marcador: MeshInstance3D = null
var _indicador: Label3D = null
var _tempo_flutuacao := 0.0


func _ready() -> void:
	print("[AreaEncomenda] _ready - agrobot_coletado: ", SaveSystem.dados.get("agrobot_coletado", false))
	# Sessão anterior já coletou o Agrobot: restaura o companheiro e não recria a caixa.
	if bool(SaveSystem.dados.get("agrobot_coletado", false)):
		print("[AreaEncomenda] Save indica agrobot já coletado - pulando criação da caixa")
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
	# Carrega o modelo GLB exportado do Blender (caixa de madeira otimizada)
	var caixa_scene := preload("res://assets/models/caixa_missao1.glb") as PackedScene
	print("[AreaEncomenda] Preload GLB resultado: ", caixa_scene, " | tipo: ", caixa_scene.get_class() if caixa_scene else "null")
	if caixa_scene == null:
		push_error("[AreaEncomenda] Modelo da caixa não encontrado em res://assets/models/caixa_missao1.glb")
		# Fallback para caixa procedural
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
		print("[AreaEncomenda] FALLBACK: Caixa procedural criada")
		return

	var inst := caixa_scene.instantiate()
	print("[AreaEncomenda] Instância criada: ", inst, " | filhos: ", inst.get_children() if inst else "null")
	if inst == null:
		push_error("[AreaEncomenda] Falha ao instanciar modelo da caixa.")
		return

	inst.name = "CaixaCentral"
	# Ajuste de altura: 0.5 = metade da altura real do modelo (~1m total)
	# Mude este valor se ainda estiver flutuando ou afundando
	inst.position = Vector3(0, 0.5, 0)
	
	# ---- COLISÃO ----
	# Cria uma StaticBody3D como pai para a colisão funcionar corretamente
	var corpo_colisao := StaticBody3D.new()
	corpo_colisao.name = "CaixaCollision"
	corpo_colisao.collision_layer = 1
	corpo_colisao.collision_mask = 0
	
	# Adiciona a caixa instanciada como filha do corpo de colisão
	corpo_colisao.add_child(inst)
	
	# Cria CollisionShape3D com BoxShape3D aproximado ao modelo
	var shape := CollisionShape3D.new()
	# Ajuste estes valores conforme o tamanho real do seu modelo GLB
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(1.2, 1.0, 1.2)  # largura, altura, profundidade
	shape.position = Vector3(0, 0.5, 0)  # centraliza na caixa
	corpo_colisao.add_child(shape)
	
	add_child(corpo_colisao)
	_caixa = corpo_colisao  # referencia o corpo para poder dar queue_free depois
	print("[AreaEncomenda] Caixa adicionada à cena: ", _caixa, " | pos: ", _caixa.global_position)
	
	# Debug: verifica se a instância tem MeshInstance3D filhos
	for child in inst.get_children():
		print("[AreaEncomenda] Filho da caixa: ", child.name, " | tipo: ", child.get_class(), " | visível: ", child.visible if child is VisualInstance3D else "N/A")
	
	# ---- INDICADOR "Pressione [E] para abrir" ----
	_criar_indicador()
	
	# Adiciona rotação contínua (no corpo de colisão, que gira a caixa junto)
	_animar_rotacao_caixa(corpo_colisao)


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

	# Limpa o indicador de interação
	if _indicador != null and is_instance_valid(_indicador):
		_indicador.queue_free()
		_indicador = null

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


## Animação da caixa ────────────────────────────────────────────────────────────

func _animar_rotacao_caixa(caixa: Node3D) -> void:
	"""Faz a caixa girar suavemente no eixo Y."""
	var tween := create_tween()
	tween.set_loops()  # loop infinito
	tween.tween_property(caixa, "rotation:y", PI * 2, 20.0).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)


## Indicador de interação (Label3D flutuante acima da caixa) ────────────────────

const ALTURA_INDICADOR := 2.2          # altura do texto acima da base da caixa
const TAM_FONTE_INDICADOR := 72        # mesmo tamanho dos prompts do trator/drone
const AMP_FLUTUACAO := 0.12            # amplitude do sobe/desce (metros)
const FREQ_FLUTUACAO := 2.4            # velocidade da flutuação (rad/s)


func _criar_indicador() -> void:
	"""Cria um Label3D flutuante acima da caixa mostrando o botão de interagir.

	Segue o mesmo padrão dos prompts do trator/drone (Label3D com billboard),
	muito mais simples que o Label 2D projetado por câmera: não depende de
	CanvasLayer, unproject nem ficar atrás da câmera.
	"""
	if _indicador != null:
		return

	var lbl := Label3D.new()
	lbl.name = "IndicadorInteracao"
	lbl.text = _texto_indicador()
	lbl.font_size = TAM_FONTE_INDICADOR
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # sempre de frente pra câmera
	# Contorno escuro: legível sobre qualquer fundo (casa, céu, terreno).
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.modulate = Color.WHITE   # texto branco
	lbl.shaded = false      # não escurece com sombra: é uma dica de UI
	lbl.double_sided = false
	lbl.position = Vector3(0, ALTURA_INDICADOR, 0)
	lbl.visible = false     # aparece só quando o jogador chegar perto
	add_child(lbl)
	_indicador = lbl


func _texto_indicador() -> String:
	"""Texto do indicador: E (teclado) / X (controle Xbox), ou toque no mobile."""
	if Dispositivo.movel():
		return "Toque em AÇÃO para abrir a caixa"
	return "Pressione [E / X] para abrir a caixa"


func _process(delta: float) -> void:
	"""Mostra o indicador quando o jogador está perto e o faz flutuar."""
	if _indicador == null or not is_instance_valid(_indicador):
		return

	# Caixa aberta ou jogador fora do alcance: indicador escondido.
	if _pacote_aberto:
		_indicador.visible = false
		return

	var player := get_tree().get_first_node_in_group("jogador") as Node3D
	if player == null or global_position.distance_to(player.global_position) > distancia_interacao:
		_indicador.visible = false
		return

	# Flutuação suave para chamar atenção.
	_tempo_flutuacao += delta
	var altura := ALTURA_INDICADOR + sin(_tempo_flutuacao * FREQ_FLUTUACAO) * AMP_FLUTUACAO
	_indicador.position = Vector3(0, altura, 0)
	_indicador.visible = true


func _obter_texto_acao_interagir() -> String:
	"""Retorna o nome amigável da tecla/botão configurado para a ação 'interagir'."""
	# Pega todos os eventos mapeados para "interagir"
	var eventos := InputMap.action_get_events("interagir")
	
	for evento in eventos:
		if evento is InputEventKey:
			# Teclado: retorna nome da tecla (ex: "E", "Space", "Enter")
			return _nome_tecla(evento.keycode)
		elif evento is InputEventJoypadButton:
			# Controle: retorna nome do botão (ex: "A", "B", "X", "Y", "Cross", "Circle")
			return _nome_botao_controle(evento.button_index)
		elif evento is InputEventMouseButton:
			# Mouse: retorna botão (ex: "Left Click", "Right Click")
			return _nome_botao_mouse(evento.button_index)
	
	# Fallback se não encontrar
	return "E"


func _nome_tecla(keycode: int) -> String:
	"""Converte keycode para nome legível."""
	# Usa match para teclas comuns, fallback para string do keycode
	match keycode:
		KEY_A: return "A"
		KEY_B: return "B"
		KEY_C: return "C"
		KEY_D: return "D"
		KEY_E: return "E"
		KEY_F: return "F"
		KEY_G: return "G"
		KEY_H: return "H"
		KEY_I: return "I"
		KEY_J: return "J"
		KEY_K: return "K"
		KEY_L: return "L"
		KEY_M: return "M"
		KEY_N: return "N"
		KEY_O: return "O"
		KEY_P: return "P"
		KEY_Q: return "Q"
		KEY_R: return "R"
		KEY_S: return "S"
		KEY_T: return "T"
		KEY_U: return "U"
		KEY_V: return "V"
		KEY_W: return "W"
		KEY_X: return "X"
		KEY_Y: return "Y"
		KEY_Z: return "Z"
		KEY_SPACE: return "Espaço"
		KEY_ENTER: return "Enter"
		KEY_ESCAPE: return "Esc"
		KEY_TAB: return "Tab"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_F1: return "F1"
		KEY_F2: return "F2"
		KEY_F3: return "F3"
		KEY_F4: return "F4"
		KEY_F5: return "F5"
		KEY_F6: return "F6"
		KEY_F7: return "F7"
		KEY_F8: return "F8"
		KEY_F9: return "F9"
		KEY_F10: return "F10"
		KEY_F11: return "F11"
		KEY_F12: return "F12"
		KEY_UP: return "Seta Cima"
		KEY_DOWN: return "Seta Baixo"
		KEY_LEFT: return "Seta Esquerda"
		KEY_RIGHT: return "Seta Direita"
		KEY_0: return "0"
		KEY_1: return "1"
		KEY_2: return "2"
		KEY_3: return "3"
		KEY_4: return "4"
		KEY_5: return "5"
		KEY_6: return "6"
		KEY_7: return "7"
		KEY_8: return "8"
		KEY_9: return "9"
		_: return "Tecla %d" % [keycode]


func _nome_botao_controle(indice: int) -> String:
	"""Converte índice do botão do controle para nome legível (layout Xbox/PS)."""
	# Layout padrão Godot (baseado em Xbox)
	match indice:
		0: return "A (Xbox) / Cross (PS)"
		1: return "B (Xbox) / Circle (PS)"
		2: return "X (Xbox) / Square (PS)"
		3: return "Y (Xbox) / Triangle (PS)"
		4: return "LB"
		5: return "RB"
		6: return "Back / Select"
		7: return "Start / Options"
		8: return "LS Click"
		9: return "RS Click"
		10: return "D-Pad Up"
		11: return "D-Pad Down"
		12: return "D-Pad Left"
		13: return "D-Pad Right"
		14: return "Guide"
		15: return "Touchpad"
		_: return "Botão %d" % [indice]


func _nome_botao_mouse(indice: int) -> String:
	"""Converte índice do botão do mouse para nome legível."""
	match indice:
		1: return "Clique Esquerdo"
		2: return "Clique Direito"
		3: return "Clique Meio (Scroll)"
		4: return "Botão Lateral 1"
		5: return "Botão Lateral 2"
		_: return "Mouse %d" % [indice]
