extends Node3D

## Loads region scenes around the player and frees them outside a larger radius.

@export var _alvo_streaming: NodePath
@export_range(0.0, 10000.0, 1.0) var raio_carregamento: float = 100.0
@export_range(0.0, 10000.0, 1.0) var raio_descarga: float = 200.0
@export var chunks: Array[ChunkData] = []
@export var debug_visivel: bool = false
@export var carregar_assincrono: bool = true
@export_range(0.05, 5.0, 0.05) var intervalo_atualizacao: float = 0.25
## Pré-carrega todas as regiões no início do jogo, uma por frame. As cenas de
## região são pequenas, mas instanciá-las no meio do caminho (quando o jogador
## entra na área) causa um pico de frame: os modelos .glb/.fbx importados são
## criados na thread principal e compilam pipeline na primeira renderização.
## Era um dos "engasgos" sentidos ao chegar na área do milho.
@export var precarregar_tudo: bool = true
## Não descarrega regiões depois de carregadas. Recarregar a mesma região toda
## vez que o jogador passa pelo limite custa outro pico de frame; com poucas
## regiões e cenas leves, manter tudo na memória é mais barato que o engasgo.
@export var manter_carregado: bool = true

const ESTADO_VAZIO := 0
const ESTADO_CARREGANDO := 1
const ESTADO_CARREGADO := 2

var _jogador: Node3D
var _chunks_carregados: Array[ChunkData] = []
var _chunks_carregando: Array[ChunkData] = []
var _proxima_tentativa_ms: Dictionary = {}
var _tempo_acumulado := 0.0

func _ready() -> void:
	if not _alvo_streaming.is_empty():
		_jogador = get_node_or_null(_alvo_streaming) as Node3D
	if _jogador == null:
		var alvo := get_tree().get_first_node_in_group("jogador")
		if alvo is Node3D:
			_jogador = alvo

	if debug_visivel:
		_desenhar_debug()
	_atualizar_chunks()
	if precarregar_tudo:
		# Carrega todas as regiões ainda na abertura, enquanto o jogador está
		# na cena inicial, em vez de engasgar ao andar até elas.
		for chunk in chunks:
			iniciar_carregamento_chunk(chunk)

func _process(delta: float) -> void:
	if carregar_assincrono:
		_verificar_chunks_carregando()

	if not is_instance_valid(_jogador):
		return
	_tempo_acumulado += delta
	if _tempo_acumulado >= intervalo_atualizacao:
		_tempo_acumulado = 0.0
		_atualizar_chunks()

func _atualizar_chunks() -> void:
	if not is_instance_valid(_jogador):
		return
	var pos := _jogador.global_position
	pos.y = 0.0

	for chunk in chunks:
		if chunk == null:
			continue
		var distancia := _distancia_ao_chunk(pos, chunk)
		if chunk in _chunks_carregados:
			if not manter_carregado and distancia > raio_descarga:
				descargar_chunk(chunk)
		elif chunk not in _chunks_carregando and distancia <= raio_carregamento:
			iniciar_carregamento_chunk(chunk)

func _distancia_ao_chunk(posicao: Vector3, chunk: ChunkData) -> float:
	# Distância horizontal até a borda do retângulo do chunk, não até seu centro.
	var dx := maxf(absf(posicao.x - chunk.centro.x) - chunk.tamanho.x * 0.5, 0.0)
	var dz := maxf(absf(posicao.z - chunk.centro.z) - chunk.tamanho.z * 0.5, 0.0)
	return Vector2(dx, dz).length()

func iniciar_carregamento_chunk(chunk: ChunkData) -> void:
	if chunk == null or chunk.cena_chunk.is_empty():
		if chunk != null:
			push_warning("[WorldStreamer] Chunk '%s' sem cena definida" % chunk.chunk_id)
		return
	if chunk in _chunks_carregados or chunk in _chunks_carregando:
		return
	var agora_ms := Time.get_ticks_msec()
	if agora_ms < int(_proxima_tentativa_ms.get(chunk.cena_chunk, 0)):
		return

	chunk.estado = ESTADO_CARREGANDO
	if not carregar_assincrono:
		_concluir_carregamento_chunk(chunk, load(chunk.cena_chunk) as PackedScene)
		return

	var status := ResourceLoader.load_threaded_get_status(chunk.cena_chunk)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or status == ResourceLoader.THREAD_LOAD_FAILED:
		var erro := ResourceLoader.load_threaded_request(chunk.cena_chunk)
		if erro != OK:
			chunk.estado = ESTADO_VAZIO
			_proxima_tentativa_ms[chunk.cena_chunk] = agora_ms + 3000
			push_error("[WorldStreamer] Falha ao iniciar '%s' (erro %d)" % [chunk.cena_chunk, erro])
			return
	_chunks_carregando.append(chunk)

func _verificar_chunks_carregando() -> void:
	# Um chunk por frame: instanciar várias cenas de região no mesmo frame
	# concentra o custo (criar nós + primeira compilação de pipeline) e
	# produz um congelamento visível de um frame para o outro.
	for i in range(_chunks_carregando.size() - 1, -1, -1):
		var chunk := _chunks_carregando[i]
		var status := ResourceLoader.load_threaded_get_status(chunk.cena_chunk)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue

		_chunks_carregando.remove_at(i)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			chunk.estado = ESTADO_VAZIO
			_proxima_tentativa_ms[chunk.cena_chunk] = Time.get_ticks_msec() + 3000
			push_error("[WorldStreamer] Falha ao carregar '%s' (status %d)" % [chunk.cena_chunk, status])
			continue

		# Só obtém o recurso quando a thread informa que terminou; load_threaded_get
		# pode bloquear a thread principal se chamado antes desse ponto.
		var cena := ResourceLoader.load_threaded_get(chunk.cena_chunk) as PackedScene
		_proxima_tentativa_ms.erase(chunk.cena_chunk)
		if not manter_carregado and (not is_instance_valid(_jogador) or _distancia_ao_chunk(_jogador.global_position, chunk) > raio_carregamento):
			chunk.estado = ESTADO_VAZIO
			continue
		_concluir_carregamento_chunk(chunk, cena)
		return

func _concluir_carregamento_chunk(chunk: ChunkData, cena: PackedScene) -> void:
	if cena == null:
		chunk.estado = ESTADO_VAZIO
		push_error("[WorldStreamer] Não foi possível carregar: " + chunk.cena_chunk)
		return

	var instancia := cena.instantiate()
	instancia.name = chunk.chunk_id
	add_child(instancia)
	chunk.instancia = instancia
	chunk.cena = cena
	chunk.estado = ESTADO_CARREGADO
	_chunks_carregados.append(chunk)

func descargar_chunk(chunk: ChunkData) -> void:
	if chunk == null:
		return
	if is_instance_valid(chunk.instancia):
		chunk.instancia.queue_free()
	chunk.instancia = null
	chunk.cena = null
	chunk.estado = ESTADO_VAZIO
	_chunks_carregados.erase(chunk)

func adicionar_chunk(id: String, caminho_cena: String, centro: Vector3, tamanho: Vector3) -> void:
	var chunk := ChunkData.new()
	chunk.chunk_id = id
	chunk.cena_chunk = caminho_cena
	chunk.centro = centro
	chunk.tamanho = tamanho
	chunks.append(chunk)
	if is_instance_valid(_jogador):
		var pos := _jogador.global_position
		pos.y = 0.0
		if _distancia_ao_chunk(pos, chunk) <= raio_carregamento:
			iniciar_carregamento_chunk(chunk)

func get_chunks_carregados() -> int:
	return _chunks_carregados.size()

func get_chunk_instancia(id: String) -> Node:
	for chunk in _chunks_carregados:
		if chunk.chunk_id == id:
			return chunk.instancia
	return null

func recarregar_tudo() -> void:
	for chunk in _chunks_carregados.duplicate():
		descargar_chunk(chunk)
	# Pedidos de ResourceLoader não são canceláveis. Mantém os pendentes na fila;
	# ao terminarem, só serão instanciados se o jogador ainda estiver no raio.
	_atualizar_chunks()

func _desenhar_debug() -> void:
	for chunk in chunks:
		if chunk == null:
			continue
		var malha := BoxMesh.new()
		malha.size = Vector3(chunk.tamanho.x, 1.0, chunk.tamanho.z)
		var caixa := MeshInstance3D.new()
		caixa.mesh = malha
		caixa.name = "DebugBox_" + chunk.chunk_id
		caixa.position = Vector3(chunk.centro.x, 0.0, chunk.centro.z)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.0, 1.0, 0.0, 0.3)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		caixa.material_override = material
		add_child(caixa)
