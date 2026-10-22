extends Node
## Autoload `QualidadeGrafica`: aplica os presets de gráficos (Baixo / Médio / Alto).
##
## Antes quem aplicava o preset era só o HUD do jogo, procurando os nós pelos
## nomes "Sol" e "MundoCeu" — que não existem no world.tscn (lá os nós são
## Sky3D/SunLight e Sky3D). A função desistia na primeira checagem e nada
## mudava ao trocar de nível.
##
## Aqui os nós são encontrados pela CLASSE (DirectionalLight3D, Terrain3D), o
## preset é reaplicado quando a cena 3D termina de montar (o Sky3D liga as
## sombras no _ready dele) e vale para qualquer cena, não só para o HUD.

const NIVEIS := ["baixo", "medio", "alto"]
const PADRAO := "alto"

## Valor de ShadowCasting do Terrain3D (e dos MeshAssets de vegetação).
const SOMBRA_OFF := 0
const SOMBRA_ON := 1

## LODs da malha do terreno por preset. É explícito de propósito: antes o
## valor "original" era lido no primeiro frame, enquanto o Terrain3D ainda
## montava a malha, e o Alto acabava travado em 3 LODs.
const LODS_TERRENO := {"baixo": 3, "medio": 5, "alto": 7}

## Distância máxima de desenho da vegetação, em metros a partir da câmera.
## 0.0 = mantém a distância definida na cena (usado nas árvores/rochas no Alto).
## Grama e arbusto somem cedo: de longe ocupam poucos pixels, mas continuam
## custando vértices, sombra e draw call.
const DISTANCIA_VEGETACAO := {
	"grama": {"baixo": 35.0, "medio": 50.0, "alto": 70.0},
	"arbusto": {"baixo": 50.0, "medio": 70.0, "alto": 95.0},
	"arvore": {"baixo": 85.0, "medio": 110.0, "alto": 0.0},
	"rocha": {"baixo": 80.0, "medio": 100.0, "alto": 0.0},
}

var nivel_atual: String = PADRAO

var _reaplicar_agendado := false
var _terreno_id := 0
var _vegetacao_range_original: Dictionary = {}
var _sombra_vegetacao_original: Dictionary = {}
var _ambiente_id := 0
var _nevoeiro_original := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	aplicar(nivel_salvo())
	# A cena pode terminar de montar depois deste autoload (o Sky3D liga as
	# sombras do sol no _ready dele), então reaplicamos quando entrarem na
	# árvore os nós que o preset controla.
	get_tree().node_added.connect(_on_no_adicionado)


func _on_no_adicionado(no: Node) -> void:
	if no is WorldEnvironment or no is DirectionalLight3D or no.get_class() == "Terrain3D":
		_agendar_reaplicacao()


func _agendar_reaplicacao() -> void:
	if _reaplicar_agendado:
		return
	_reaplicar_agendado = true
	call_deferred("_reaplicar")


func _reaplicar() -> void:
	_reaplicar_agendado = false
	aplicar(nivel_atual)


# ------------------------------------------------------------------ API

func nivel_salvo() -> String:
	var n := str(SaveSystem.dados.get("grafico", PADRAO))
	return n if NIVEIS.has(n) else PADRAO


## Aplica e salva o preset (chamado pelos botões do HUD).
func definir(nivel: String) -> void:
	if not NIVEIS.has(nivel):
		nivel = PADRAO
	SaveSystem.dados["grafico"] = nivel
	SaveSystem.salvar()
	aplicar(nivel)


## Aplica o preset sem salvar nada.
func aplicar(nivel: String) -> void:
	if not NIVEIS.has(nivel):
		nivel = PADRAO
	nivel_atual = nivel
	_aplicar_viewport(nivel)
	var cena := get_tree().current_scene
	if cena == null:
		return
	var sol := _achar_sol(cena)
	if sol != null:
		_aplicar_sol(sol, nivel)
	_aplicar_ambiente(cena, nivel)
	_aplicar_lens_flare(cena, nivel)
	_aplicar_terreno(cena, nivel)


# ------------------------------------------------------- ajustes globais

func _aplicar_viewport(nivel: String) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	match nivel:
		"baixo":
			# Sem anti-aliasing e com LOD bem agressivo nas malhas.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = false
			vp.mesh_lod_threshold = 6.0
			vp.positional_shadow_atlas_size = 1024
			RenderingServer.directional_shadow_atlas_set_size(1024, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		"medio":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
			vp.mesh_lod_threshold = 2.5
			vp.positional_shadow_atlas_size = 2048
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		_:
			# FXAA em vez de MSAA 2x: no teste em 1080p o MSAA custava ~14%
			# do frame e o FXAA entrega ~12% com as bordas ainda suavizadas.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
			vp.mesh_lod_threshold = 1.0
			# Atlas 2048 em vez de 4096: metade do custo de preencher o mapa
			# de sombra, sem diferença visível a olho nu nessa distância.
			vp.positional_shadow_atlas_size = 2048
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)


# ----------------------------------------------------------- cena atual

func _achar_sol(raiz: Node) -> DirectionalLight3D:
	var sol := raiz.find_child("SunLight", true, false) as DirectionalLight3D
	if sol != null:
		return sol
	var luzes := raiz.find_children("*", "DirectionalLight3D", true, false)
	for luz in luzes:
		var d := luz as DirectionalLight3D
		if d != null and d.shadow_enabled:
			return d
	return luzes[0] as DirectionalLight3D if not luzes.is_empty() else null


func _aplicar_sol(sol: DirectionalLight3D, nivel: String) -> void:
	match nivel:
		"baixo":
			sol.shadow_enabled = false
		"medio":
			sol.shadow_enabled = true
			sol.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sol.directional_shadow_max_distance = 45.0
		_:
			sol.shadow_enabled = true
			# 2 splits em vez de 4: o mesmo mapa de sombra deixa de ser
			# redesenhado em 4 cascatas. No teste, ~4% de FPS e 37% menos
			# draw calls, com as sombras ainda chegando aos 110 m.
			sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sol.directional_shadow_max_distance = 110.0


func _aplicar_ambiente(raiz: Node, nivel: String) -> void:
	var ceu := _achar_primeiro(raiz, "WorldEnvironment") as WorldEnvironment
	if ceu == null or ceu.environment == null:
		return
	var env := ceu.environment
	var id := env.get_instance_id()
	if id != _ambiente_id:
		_ambiente_id = id
		_nevoeiro_original = env.fog_enabled
	# O Sky3D cuida do céu/ambiente; aqui só mexemos no nevoeiro (custo de
	# tela cheia) e devolvemos o valor original nos níveis mais altos.
	env.fog_enabled = false if nivel == "baixo" else _nevoeiro_original


## Lens flare (addon SIsilicon) é um quad de tela cheia: no Baixo ele é
## desligado; nos outros níveis volta ao estado original da cena.
func _aplicar_lens_flare(raiz: Node, nivel: String) -> void:
	for no in raiz.find_children("*", "", true, false):
		if not _e_lens_flare(no) or not ("enabled" in no):
			continue
		if not no.has_meta("_qualidade_flare_original"):
			no.set_meta("_qualidade_flare_original", bool(no.get("enabled")))
		var alvo := false if nivel == "baixo" else bool(no.get_meta("_qualidade_flare_original"))
		if bool(no.get("enabled")) != alvo:
			no.set("enabled", alvo)


func _e_lens_flare(no: Node) -> bool:
	var script: Script = no.get_script()
	if script == null:
		return false
	var caminho := str(script.resource_path).to_lower()
	return caminho.contains("lens") and caminho.contains("flare")


func _aplicar_terreno(raiz: Node, nivel: String) -> void:
	var terreno := _achar_primeiro(raiz, "Terrain3D")
	if terreno == null:
		return

	if terreno.get_instance_id() != _terreno_id:
		_terreno_id = terreno.get_instance_id()
		_vegetacao_range_original.clear()
		_sombra_vegetacao_original.clear()

	var alvo_lods := int(LODS_TERRENO.get(nivel, 7))
	if int(terreno.call("get_mesh_lods")) != alvo_lods:
		terreno.call("set_mesh_lods", alvo_lods)

	var alvo_sombra := SOMBRA_OFF if nivel == "baixo" else SOMBRA_ON
	if int(terreno.call("get_cast_shadows")) != alvo_sombra:
		terreno.call("set_cast_shadows", alvo_sombra)

	_aplicar_vegetacao(terreno, nivel)


## Árvores, mato e grama são MultiMeshes do Terrain3D. Aqui ajustamos a
## distância de desenho e quem projeta sombra — o maior ganho de FPS da
## floresta, porque a grama é o que mais aparece e o que mais custa.
func _aplicar_vegetacao(terreno: Node, nivel: String) -> void:
	var assets: Object = terreno.call("get_assets")
	if assets == null:
		return
	var total := int(assets.call("get_mesh_count"))
	for i in total:
		var asset: Object = assets.call("get_mesh_asset", i)
		if asset == null:
			continue
		var tipo := _tipo_vegetacao(str(asset.call("get_name")).to_lower())

		if not _vegetacao_range_original.has(i):
			_vegetacao_range_original[i] = float(asset.call("get_lod0_range"))
		var distancia := float(_vegetacao_range_original[i])
		if DISTANCIA_VEGETACAO.has(tipo):
			var valor := float(DISTANCIA_VEGETACAO[tipo].get(nivel, 0.0))
			if valor > 0.0:
				distancia = valor
		if not is_equal_approx(float(asset.call("get_lod0_range")), distancia):
			asset.call("set_lod0_range", distancia)

		if not _sombra_vegetacao_original.has(i):
			_sombra_vegetacao_original[i] = int(asset.call("get_cast_shadows"))
		var original := int(_sombra_vegetacao_original[i])
		var alvo := original
		if nivel == "baixo":
			alvo = SOMBRA_OFF
		elif tipo == "grama" or (nivel == "medio" and tipo == "arbusto"):
			# A sombra da grama é quase invisível a olho nu e custa ~4% do
			# frame; no Médio o arbusto também sai.
			alvo = SOMBRA_OFF
		if int(asset.call("get_cast_shadows")) != alvo:
			asset.call("set_cast_shadows", alvo)


func _tipo_vegetacao(nome: String) -> String:
	if nome.contains("grass") or nome.contains("grama"):
		return "grama"
	if nome.contains("bush") or nome.contains("arbusto"):
		return "arbusto"
	if nome.contains("pine") or nome.contains("maple") or nome.contains("tree") or nome.contains("arvore"):
		return "arvore"
	if nome.contains("rock") or nome.contains("rocha"):
		return "rocha"
	return ""


func _achar_primeiro(raiz: Node, classe: String) -> Node:
	if raiz.get_class() == classe:
		return raiz
	for filho in raiz.get_children():
		var achado := _achar_primeiro(filho, classe)
		if achado != null:
			return achado
	return null
