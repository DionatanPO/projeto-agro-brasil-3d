extends Control
## Menu inicial: Novo jogo / Continuar / Sair.

@onready var botao_continuar: Button = $Centro/Painel/VBox/BotaoContinuar
@onready var info: Label = $Centro/Painel/VBox/Info


func _ready() -> void:
	var descobertas: Array = SaveSystem.dados.get("descobertas", [])
	if SaveSystem.tem_save() and descobertas.size() > 0:
		botao_continuar.disabled = false
		info.text = "Progresso: %d descoberta(s), %d/%d missoes concluidas." % [
			descobertas.size(), Missoes.total_concluidas(), Missoes.total_missoes()
		]
	else:
		botao_continuar.disabled = true
		info.text = "Nenhum progresso salvo. Comece um novo jogo!"


func _on_novo_jogo() -> void:
	SaveSystem.apagar()
	get_tree().change_scene_to_file("res://world.tscn")


func _on_continuar() -> void:
	get_tree().change_scene_to_file("res://world.tscn")


func _on_sair() -> void:
	get_tree().quit()
