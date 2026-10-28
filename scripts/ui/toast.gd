extends CanvasLayer
## Toast: notificação simples estilo "toast" (aparece, fica, some).
##
## Uso:
##   var toast = preload("res://scenes/ui/toast.tscn").instantiate()
##   get_tree().root.add_child(toast)
##   toast.mostrar("Texto", 4.0)
##
## Para missões:
##   toast.mostrar_missao("Primeira Entrega", "Vá até o local da encomenda", 5.0)

class_name Toast

signal finished

const SOM_TOAST := "res://assets/audio/ui/toast.wav"

var _painel: PanelContainer
var _label: Label
var _tween: Tween
var _som: AudioStreamPlayer
var _stream_som: AudioStream


func _ready() -> void:
	layer = 200
	visible = false

	# Busca nós filhos (robusto para instanciação dinâmica)
	_painel = get_node_or_null("Painel") as PanelContainer
	if _painel != null:
		_label = _painel.get_node_or_null("Label") as Label

	if _painel == null or _label == null:
		push_error("Toast: estrutura inválida. Espera: Toast -> Painel -> Label")
		queue_free()
		return

	_painel.modulate.a = 0.0
	_painel.scale = Vector2.ONE

	# Som de notificação (usa "load" em runtime para não criar dependência
	# de compilação com o recurso e nunca derrubar quem faz preload do toast).
	_som = AudioStreamPlayer.new()
	_som.name = "SomToast"
	_som.volume_db = -3.0
	if AudioServer.get_bus_index("Efeitos") >= 0:
		_som.bus = "Efeitos"
	add_child(_som)
	if ResourceLoader.exists(SOM_TOAST):
		_stream_som = load(SOM_TOAST) as AudioStream


## Mostra o toast (chamado na instância, não estático).
func mostrar(texto: String, duracao: float = 4.0) -> void:
	if _painel == null or _label == null:
		push_error("Toast: nós não inicializados")
		return

	# Cancela uma exibição anterior para não sobrepor tweens.
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_label.text = texto
	visible = true
	_painel.modulate.a = 0.0
	_painel.scale = Vector2.ONE
	_tocar_som()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_painel, "modulate:a", 1.0, 0.25)
	_tween.parallel().tween_property(_painel, "scale", Vector2(1.05, 1.05), 0.15)
	_tween.tween_property(_painel, "scale", Vector2.ONE, 0.15)
	_tween.tween_interval(duracao)
	_tween.tween_property(_painel, "modulate:a", 0.0, 0.35)
	_tween.tween_callback(_ao_terminar)


## Atalho para anunciar missão: título + objetivo.
func mostrar_missao(titulo: String, objetivo: String = "", duracao: float = 5.0) -> void:
	var texto := "NOVA MISSÃO\n%s" % titulo
	if not objetivo.is_empty():
		texto += "\n\n" + objetivo
	mostrar(texto, duracao)


func _tocar_som() -> void:
	if _som == null or _stream_som == null:
		return
	_som.stream = _stream_som
	_som.play()


func _ao_terminar() -> void:
	visible = false
	_painel.scale = Vector2.ONE
	_painel.modulate.a = 0.0
	finished.emit()
	queue_free()  # limpa a instância após sumir
