extends Node
## Autoload DialogoManager: gerencia reproducao de dialogos (audio + fila).
## Dialogos ficam em res://assets/audio/dialogos/<id>.wav (ou .mp3/.ogg).

signal dialogo_iniciado(id: String)
signal dialogo_finalizado(id: String)

const PASTA_DIALOGOS := "res://assets/audio/dialogos/"
const EXTS := ["wav", "mp3", "ogg"]

var _player: AudioStreamPlayer
var _fila: Array = []
var _tocando := false
var _id_atual := ""

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "DialogoPlayer"
	_player.bus = "Voz" if AudioServer.get_bus_index("Voz") >= 0 else "Master"
	add_child(_player)
	_player.finished.connect(_on_audio_finished)


func _caminho_audio(id: String) -> String:
	for ext in EXTS:
		var ext_str := String(ext)
		var caminho: String = PASTA_DIALOGOS + id + "." + ext_str
		if ResourceLoader.exists(caminho):
			return caminho
	return ""


func tocar(id: String) -> void:
	if id.is_empty():
		return
	_fila.append(id)
	_tentar_proximo()


func tocar_imediato(id: String) -> void:
	_fila.clear()
	if _tocando and _player.playing:
		_player.stop()
	_tocando = false
	_id_atual = ""
	_fila.append(id)
	_tentar_proximo()


func _tentar_proximo() -> void:
	if _tocando or _fila.is_empty():
		return
	var id := _fila.pop_front() as String
	var caminho: String = _caminho_audio(id)
	if caminho.is_empty():
		push_warning("DialogoManager: audio nao encontrado para '%s'" % id)
		_tentar_proximo()
		return
	var stream := load(caminho) as AudioStream
	if stream == null:
		push_warning("DialogoManager: falha ao carregar '%s'" % caminho)
		_tentar_proximo()
		return
	_id_atual = id
	_tocando = true
	_player.stream = stream
	dialogo_iniciado.emit(id)
	_player.play()


func _on_audio_finished() -> void:
	var id := _id_atual
	_tocando = false
	_id_atual = ""
	dialogo_finalizado.emit(id)
	_tentar_proximo()


func esta_tocando() -> bool:
	return _tocando


func id_atual() -> String:
	return _id_atual