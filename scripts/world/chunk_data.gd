## ChunkData: armazena informações de uma zona do mundo.
## Usado pelo WorldStreamer para saber o que carregar/descargar.
class_name ChunkData

extends Resource

@export var chunk_id: String = ""
@export var cena_chunk: String = ""  # caminho para o .tscn da zona
@export var centro: Vector3 = Vector3.ZERO
@export var tamanho: Vector3 = Vector3(100, 100, 100)  # tamanho da zona
# Estado mantido em tempo de execução pelo WorldStreamer.
var estado: int = 0  # 0=vazio, 1=carregando, 2=carregado
var instancia: Node = null  # referência à instância carregada
var cena: PackedScene = null  # recurso da cena carregado (assíncrono)

## Verifica se um ponto está dentro deste chunk (ignorando Y)
func contem_ponto(ponto: Vector3) -> bool:
	var dx: float = abs(ponto.x - centro.x)
	var dz: float = abs(ponto.z - centro.z)
	return dx <= tamanho.x * 0.5 and dz <= tamanho.z * 0.5

## Retorna true se o chunk está totalmente carregado e visível
func esta_carregado() -> bool:
	return estado == 2
