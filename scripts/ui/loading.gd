class_name Loading
extends Control
## Tela de loading moderna com barra de progresso real, dicas agrícolas e transição suave.

static var proxima_cena := ""
static var titulo_carga := "Carregando a fazenda..."

const CENA_SEGURA := "res://world.tscn"
const TEMPO_MINIMO := 1.2

@onready var status_label: Label = $MargemConteudo/VBoxPrincipal/SecaoInferior/LinhaInfo/StatusLabel
@onready var porcentagem_label: Label = $MargemConteudo/VBoxPrincipal/SecaoInferior/LinhaInfo/PorcentagemLabel
@onready var barra_progresso: ProgressBar = $MargemConteudo/VBoxPrincipal/SecaoInferior/BarraProgresso
@onready var dica_texto: Label = $MargemConteudo/VBoxPrincipal/PainelDica/MargemDica/VBoxDica/DicaTexto
@onready var painel_dica: PanelContainer = $MargemConteudo/VBoxPrincipal/PainelDica
@onready var fade_trans: ColorRect = $FadeTrans

const DICAS: Array[String] = [
	"A agricultura de precisão utiliza sensores e GPS para aplicar insumos na medida exata, reduzindo custos e impacto ambiental.",
	"O Sistema de Plantio Direto (SPD) conserva a umidade do solo, evita erosão e enriquece a matéria orgânica da lavoura.",
	"Drones agrícolas são capazes de mapear falhas de plantio e infestações de pragas em minutos com câmeras multiespectrais.",
	"A integração Lavoura-Pecuária-Floresta (ILPF) otimiza o uso da terra, gerando múltiplos ciclos produtivos na mesma área.",
	"O Brasil é pioneiro mundial no uso de bioinsumos e controle biológico, substituindo defensivos químicos por agentes naturais.",
	"A energia solar fotovoltaica e o biogás no campo transformam resíduos em autonomia energética limpa e sustentável."
]

var _tempo_passado := 0.0
var _progresso_atual := 0.0
var _progresso_alvo := 0.0
var _mudando_cena := false
var _array_progresso: Array = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	_estilizar_interface()

	if proxima_cena.is_empty():
		proxima_cena = CENA_SEGURA

	status_label.text = titulo_carga
	dica_texto.text = DICAS[randi() % DICAS.size()]

	barra_progresso.min_value = 0.0
	barra_progresso.max_value = 100.0
	barra_progresso.value = 0.0
	porcentagem_label.text = "0%"

	fade_trans.modulate.a = 0.0

	# Requisita carregamento assíncrono em thread
	ResourceLoader.load_threaded_request(proxima_cena)
	set_process(true)


func _estilizar_interface() -> void:
	# Painel de Dica no estilo Glassmorphism
	var estilo_dica := StyleBoxFlat.new()
	estilo_dica.bg_color = Color(0.02, 0.07, 0.04, 0.75)
	estilo_dica.set_corner_radius_all(10)
	estilo_dica.set_border_width_all(1)
	estilo_dica.border_color = Color(0.24, 0.82, 0.46, 0.35)
	estilo_dica.shadow_color = Color(0, 0, 0, 0.5)
	estilo_dica.shadow_size = 8
	painel_dica.add_theme_stylebox_override("panel", estilo_dica)

	# Fundo da barra de progresso
	var barra_bg := StyleBoxFlat.new()
	barra_bg.bg_color = Color(0.08, 0.12, 0.09, 0.85)
	barra_bg.set_corner_radius_all(4)
	barra_bg.set_border_width_all(1)
	barra_bg.border_color = Color(1, 1, 1, 0.08)

	# Preenchimento da barra de progresso
	var barra_fill := StyleBoxFlat.new()
	barra_fill.bg_color = Color(0.32, 0.95, 0.56, 1.0)
	barra_fill.set_corner_radius_all(4)
	barra_fill.shadow_color = Color(0.2, 0.9, 0.45, 0.6)
	barra_fill.shadow_size = 6

	barra_progresso.add_theme_stylebox_override("background", barra_bg)
	barra_progresso.add_theme_stylebox_override("fill", barra_fill)


func _process(delta: float) -> void:
	if _mudando_cena:
		return

	_tempo_passado += delta

	_array_progresso.clear()
	var estado := ResourceLoader.load_threaded_get_status(proxima_cena, _array_progresso)

	if not _array_progresso.is_empty():
		_progresso_alvo = float(_array_progresso[0]) * 100.0
	else:
		_progresso_alvo = minf(_progresso_alvo + delta * 25.0, 90.0)

	# Sobe a barra fluidamente até a meta
	if _progresso_alvo >= 100.0:
		_progresso_atual = move_toward(_progresso_atual, 100.0, delta * 80.0)
	else:
		_progresso_atual = lerpf(_progresso_atual, _progresso_alvo, delta * 7.0)
	barra_progresso.value = _progresso_atual
	porcentagem_label.text = "%d%%" % int(round(_progresso_atual))

	match estado:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pass

		ResourceLoader.THREAD_LOAD_LOADED:
			_progresso_alvo = 100.0
			# Aguarda a barra completar 100% visualmente e respeitar o tempo mínimo
			if _tempo_passado < TEMPO_MINIMO or _progresso_atual < 100.0:
				return

			_progresso_atual = 100.0
			barra_progresso.value = 100.0
			porcentagem_label.text = "100%"
			status_label.text = "Tudo pronto!"
			_mudando_cena = true
			set_process(false)
			_concluir_e_transicionar()

		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			status_label.text = "Erro ao carregar o mapa. Voltando..."
			set_process(false)
			await get_tree().create_timer(1.5).timeout
			proxima_cena = ""
			get_tree().change_scene_to_file(CENA_SEGURA)


func _concluir_e_transicionar() -> void:
	# Pega a cena pré-carregada da memória
	var empacotada := ResourceLoader.load_threaded_get(proxima_cena) as PackedScene
	if empacotada == null:
		proxima_cena = ""
		get_tree().change_scene_to_file(CENA_SEGURA)
		return

	proxima_cena = ""

	# Transiciona diretamente para a cena já carregada
	get_tree().change_scene_to_packed(empacotada)
