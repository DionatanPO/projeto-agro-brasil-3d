extends RefCounted
class_name Dispositivo
## Deteccao simples de plataforma/entrada, usada pelos controles de toque.
##
## Importante: no PC (Windows/Linux/macOS) `movel()` e sempre falso, entao os
## controles de toque NAO aparecem, mesmo em notebook com tela sensivel ao
## toque. Quem quiser forcar o uso no PC usa a opcao "Sempre" nas configuracoes.


## Verdadeiro apenas em builds/runtimes de celular ou tablet.
static func movel() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)


## Verdadeiro em qualquer aparelho com tela sensivel ao toque.
static func tem_toque() -> bool:
	return movel() or DisplayServer.is_touchscreen_available()
