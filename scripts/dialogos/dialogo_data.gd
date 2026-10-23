extends Resource
## Define um diálogo do jogo.
## Use como Resource (.tres) ou crie instâncias em código.

class_name DialogoData

@export var id: String = ""
@export var audio_path: String = ""
@export var texto: String = ""
@export var duracao: float = 0.0  # 0 = usa duração do áudio
@export var personagem: String = ""
