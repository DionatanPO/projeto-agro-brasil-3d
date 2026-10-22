extends Node
## Autoload `AudioConfig`: cria os barramentos "Efeitos" e "Musica"
## (saida -> Master) e aplica os volumes salvos no [Tab] caderno.
## Listado no project.godot logo apos o SaveSystem, pois le os
## volumes de `SaveSystem.dados` no _ready.
##
## Como usar:
## - Efeitos (motor do drone, vento, passos, buzina, argolas): no _ready
##   do player, apos criar o AudioStreamPlayer*, faca:
##       if AudioServer.get_bus_index("Efeitos") >= 0:
##           player.bus = "Efeitos"
## - Musicas futuras: `player.bus = "Musica"` (mesmo padrao).

const BUS_EFEITOS := "Efeitos"
const BUS_MUSICA := "Musica"


func _ready() -> void:
	_garantir_bus(BUS_EFEITOS)
	_garantir_bus(BUS_MUSICA)
	aplicar_volumes()


func aplicar_volumes() -> void:
	definir_volume_efeitos(float(SaveSystem.dados.get("volume_efeitos", 70.0)), false)
	definir_volume_musica(float(SaveSystem.dados.get("volume_musica", 70.0)), false)


func definir_volume_efeitos(valor_0_100: float, salvar := true) -> void:
	_definir_volume(BUS_EFEITOS, valor_0_100)
	if salvar:
		SaveSystem.dados["volume_efeitos"] = clampf(valor_0_100, 0.0, 100.0)
		SaveSystem.salvar()


func definir_volume_musica(valor_0_100: float, salvar := true) -> void:
	_definir_volume(BUS_MUSICA, valor_0_100)
	if salvar:
		SaveSystem.dados["volume_musica"] = clampf(valor_0_100, 0.0, 100.0)
		SaveSystem.salvar()


func volume_efeitos() -> float:
	return _volume_de(BUS_EFEITOS)


func volume_musica() -> float:
	return _volume_de(BUS_MUSICA)


func _garantir_bus(nome: String) -> void:
	if AudioServer.get_bus_index(nome) >= 0:
		return
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, nome)
	AudioServer.set_bus_send(i, "Master")


func _definir_volume(bus: String, valor_0_100: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	
	# Mapear slider linear (0-100) para faixa decibel mais natural (0dB a -60dB)
	# Isso fornece controle mais preciso perceptualmente
	var db_range_min := -60.0  # Volume mínimo em decibels
	var db_range_max := 0.0    # Volume máximo em decibels
	var db_value := db_range_min + (valor_0_100 / 100.0) * (db_range_max - db_range_min)
	
	AudioServer.set_bus_volume_db(idx, db_value)


func _volume_de(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return 80.0
	var db_value := AudioServer.get_bus_volume_db(idx)
	
	# Converter decibels de volta para valor do slider (0-100) usando a mesma faixa
	var db_range_min := -60.0  # Volume mínimo em decibels
	var db_range_max := 0.0    # Volume máximo em decibels
	if db_range_max == db_range_min:
		return 50.0  # Evitar divisão por zero
	var slider_value := ((db_value - db_range_min) / (db_range_max - db_range_min)) * 100.0
	return clampf(slider_value, 0.0, 100.0)
