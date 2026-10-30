extends Node3D
## Barreira invisível do rio.
##
## As paredes do rio no world.tscn são caixas alinhadas aos eixos X/Z, mas o
## rio é uma faixa sinuosa (o plano d'água está girado ~105°) e o terreno
## sobe e desce. Por isso caixas fixas não acompanham a margem: o personagem
## acha vãos, cai na água ou anda sobre o leito raso.
##
## Esta barreira lê a altura REAL do Terrain3D sob o alvo (jogador ou
## veículo):
##   - se o chão sob ele está abaixo do nível da água (leito do rio), e
##   - o pé dele está baixo o bastante para estar dentro/sobre a água,
## então ele volta para a última posição segura em terra firme.
##
## Como a checagem segue o terreno, ela acompanha o formato torto do rio.
## Pontes continuam funcionando: em cima delas o pé fica acima da água.

@export var terreno_path: NodePath = ^"../Terrain3D"
## Nó protegido (jogador ou veículo). Vazio cai no grupo "jogador".
@export var alvo_path: NodePath = ^"../Player"
## Altura Y da superfície da água (o nó "Water" está em 8.54921).
@export var nivel_agua: float = 8.54921
## Chão abaixo de (nível + margem) é considerado leito/água.
@export var margem_leito: float = 0.35
## O pé pode ficar até (nível + folga) acima da água sem contar como rio.
@export var folga_pe: float = 0.35
## Distância do pivô do nó até o pé (chão):
## jogador = 0.9 (o pivô fica no centro da cápsula);
## trator  = 0.0 (o pivô já fica na base).
@export var distancia_pe: float = 0.9
## Quanto o alvo recua para dentro da margem ao ser resgatado. Voltar para a
## última posição exata costuma deixá-lo preso na encosta/beirada: recuar um
## pouco o coloca em terreno firme de onde ele consegue sair sozinho.
@export var recuo_margem: float = 3.5
## Folga de terreno exigida para aceitar o ponto de retorno como seguro
## (chão acima de nível da água + esta folga). Se a margem ali for baixa, o
## recuo diminui até achar um ponto firme.
@export var folga_segura: float = 1.0

var _terreno: Terrain3D
var _alvo: CharacterBody3D
var _pos_segura: Vector3
var _tem_segura := false


func _ready() -> void:
	_resolver_terreno()
	_resolver_jogador()


func _resolver_terreno() -> void:
	_terreno = get_node_or_null(terreno_path) as Terrain3D


func _resolver_jogador() -> bool:
	var p := get_node_or_null(alvo_path)
	if p is CharacterBody3D:
		_alvo = p
	else:
		_alvo = get_tree().get_first_node_in_group("jogador") as CharacterBody3D
	if _alvo == null:
		return false
	_pos_segura = _alvo.global_position
	_tem_segura = true
	return true


func _altura_terreno(p: Vector3) -> float:
	if _terreno == null or _terreno.data == null:
		return nivel_agua
	return _terreno.data.get_height(p)


## Escolhe onde devolver o alvo: recua alguns metros da beira, no sentido
## oposto ao rio, e só aceita um ponto com terreno firme acima da água.
func _ponto_de_retorno(pos: Vector3) -> Vector3:
	var destino := _pos_segura
	var dir := _pos_segura - pos
	dir.y = 0.0
	if dir.length() < 0.01:
		# Veio caindo quase na vertical: recua para trás do alvo.
		dir = -_alvo.global_transform.basis.z
		dir.y = 0.0
	if dir.length() < 0.01:
		return destino
	dir = dir.normalized()

	var passo := recuo_margem
	var melhor := destino
	var melhor_chao := _altura_terreno(destino)
	while passo > 0.2:
		var cand := destino + dir * passo
		var chao := _altura_terreno(cand)
		if chao >= nivel_agua + folga_segura:
			cand.y = chao + distancia_pe + 0.05
			return cand
		# Margem baixa ali: guarda o ponto mais alto encontrado como reserva,
		# para nunca devolver o alvo exatamente na beirada.
		if chao > melhor_chao:
			melhor_chao = chao
			melhor = cand
		passo *= 0.5

	if melhor != destino:
		melhor.y = melhor_chao + distancia_pe + 0.05
	return melhor


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_alvo):
		if not _resolver_jogador():
			return
	if _terreno == null:
		_resolver_terreno()
		if _terreno == null:
			return

	var pos := _alvo.global_position
	var pe := pos.y - distancia_pe

	var chao := nivel_agua
	if _terreno.data != null:
		chao = _terreno.data.get_height(pos)

	var no_leito := chao <= nivel_agua + margem_leito
	var baixo := pe <= nivel_agua + folga_pe

	# Só barra quando está caindo ou já apoiado: não corta um pulo subindo.
	if no_leito and baixo and _alvo.velocity.y <= 0.0:
		_alvo.global_position = _ponto_de_retorno(pos)
		_alvo.velocity = Vector3.ZERO
		# Veículos guardam a velocidade do motor em _vel: zera para parar
		# de empurrar contra a margem.
		if _alvo.get("_vel") != null:
			_alvo.set("_vel", 0.0)
		if _alvo.get("_gas") != null:
			_alvo.set("_gas", 0.0)
		return

	# Em terra firme (ou em cima de uma ponte) guarda onde é seguro voltar.
	if _alvo.is_on_floor() and _tem_segura:
		_pos_segura = pos
