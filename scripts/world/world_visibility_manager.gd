extends Node3D

## WorldVisibilityManager: percorre o mundo e adiciona VisibleOnScreenNotifier3D
## nos objetos estáticos grandes (edifícios, rochas, pontes) para desligá-los
## quando saem da tela, economizando GPU em dispositivos móveis.
##
## Adicione este nó como filho do nó raiz do world.tscn.

@export var ativar_otimizacao: bool = true
@export var distancia_maxima_visibilidade: float = 300.0
@export var nomes_para_otimizar: PackedStringArray = [
	"Silo", "Casa", "Galpao", "Galpão", "Bridge", "Ponte",
	"WaterTower", "Well", "ChickenCoop", "rock", "Big", "barn", "Barn"
]

var _nos_otimizados: int = 0

func _ready() -> void:
	if not ativar_otimizacao:
		return
	_processar_nos(self)
	print("[WorldVisibilityManager] Objetos otimizados: ", _nos_otimizados)

func _processar_nos(no: Node) -> void:
	for filho in no.get_children():
		if filho is MeshInstance3D:
			var nome := str(filho.name)
			for alvo in nomes_para_otimizar:
				if nome.contains(alvo):
					# Evita duplicar se já existir
					if filho.get_node_or_null("VisibilityOptimizer") != null:
						break
					var opt := VisibilityOptimizer.new()
					opt.name = "VisibilityOptimizer"
					opt.distancia_maxima_visibilidade = distancia_maxima_visibilidade
					filho.add_child(opt)
					_nos_otimizados += 1
					break
		# Recursão em filhos
		_processar_nos(filho)
