extends Node
## Autoload `SaveSystem`: salvamento local do progresso (user://savegame.json).

signal progresso_salvo
signal progresso_carregado(dados: Dictionary)

const CAMINHO_SAVE := "user://savegame.json"

var dados: Dictionary = {}


func _ready() -> void:
	carregar()


func tem_save() -> bool:
	return FileAccess.file_exists(CAMINHO_SAVE)


func carregar() -> Dictionary:
	if not tem_save():
		dados = _dados_padrao()
		return dados
	var arq := FileAccess.open(CAMINHO_SAVE, FileAccess.READ)
	if arq == null:
		push_error("SaveSystem: nao foi possivel ler o save.")
		dados = _dados_padrao()
		return dados
	var parsed: Variant = JSON.parse_string(arq.get_as_text())
	if parsed is Dictionary:
		dados = parsed
	else:
		push_error("SaveSystem: save corrompido, usando padrao.")
		dados = _dados_padrao()
	progresso_carregado.emit(dados)
	return dados


func salvar() -> void:
	dados["versao"] = 1
	var arq := FileAccess.open(CAMINHO_SAVE, FileAccess.WRITE)
	if arq == null:
		push_error("SaveSystem: nao foi possivel escrever o save.")
		return
	arq.store_string(JSON.stringify(dados, "\t"))
	progresso_salvo.emit()


func apagar() -> void:
	if tem_save():
		DirAccess.remove_absolute(CAMINHO_SAVE)
	dados = _dados_padrao()
	progresso_carregado.emit(dados)


func _dados_padrao() -> Dictionary:
	return {
		"versao": 1,
		"descobertas": [],
		"missoes_concluidas": [],
		"posicao_jogador": [0.0, 1.5, -11.91],
		"posicao_drone": [-3.5, 1.2, 2.5],
		"posicao_trator": [13.0, 0.7, -7.0],
		"veiculo": "jogador",
		"volume_efeitos": 70.0,
		"volume_musica": 70.0,
		"vsync": true,
		"controles_toque": "auto",
		"tutorial_drone_concluido": false,
		"intro_mundo_vista": false,
		"tempo_jogado_seg": 0.0,
		"xp": 0,
		"nivel": 1,
	}
