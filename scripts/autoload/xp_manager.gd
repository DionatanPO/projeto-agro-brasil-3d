extends Node
## XPManager: Gerencia experiência e progressão do personagem
## - Sistema de XP com níveis de 1 a 30
## - Integração com SaveSystem para persistência
## - Sinais para atualização de UI e eventos de jogo

signal xp_changed(amount: int, total: int)
signal level_changed(old_level: int, new_level: int)
signal level_up_reached(new_level: int)

# Configuração do sistema de níveis
const MAX_LEVEL := 30
const XP_BASE := 100          # XP necessário para nível 2
const XP_GROWTH := 1.5        # Fator de crescimento exponencial

# Cache dos dados para melhor desempenho
var _xp: int = 0
var _level: int = 1

func _ready() -> void:
	# Carrega dados salvos ao iniciar
	_load_from_save()
	
	# Conecta aos sinais do SaveSystem para manter sincronização
	SaveSystem.progresso_carregado.connect(_on_save_loaded)
	SaveSystem.progresso_salvo.connect(_on_save_saved)

func _load_from_save() -> void:
	"""Carrega XP e nível do SaveSystem"""
	var save_data = SaveSystem.dados
	_xp = save_data.get("xp", 0)
	_level = clamp(save_data.get("nivel", 1), 1, MAX_LEVEL)
	
	# NotificaListeners sobre o estado inicial
	emit_signal("xp_changed", 0, _xp)
	emit_signal("level_changed", 1, _level)

func _on_save_loaded(data: Dictionary) -> void:
	"""Callback quando o save é carregado"""
	_xp = data.get("xp", 0)
	_level = clamp(data.get("nivel", 1), 1, MAX_LEVEL)
	emit_signal("xp_changed", 0, _xp)
	emit_signal("level_changed", 1, _level)

func _on_save_saved() -> void:
	"""Callback quando o save é salvo - garante que nossos dados estejam atualizados"""
	var save_data = SaveSystem.dados
	save_data["xp"] = _xp
	save_data["nivel"] = _level
	# Não salva aqui para evitar loop infinito - o SaveSystem já está salvando

func get_xp() -> int:
	"""Retorna o XP atual"""
	return _xp

func get_level() -> int:
	"""Retorna o nível atual"""
	return _level

func get_xp_for_next_level() -> int:
	"""Retorna o XP necessário para alcançar o próximo nível"""
	if _level >= MAX_LEVEL:
		return 0
	return int(XP_BASE * pow(XP_GROWTH, _level - 1))

func get_xp_progress_to_next_level() -> float:
	"""Retorna o progresso para o próximo nível como um valor entre 0.0 e 1.0"""
	if _level >= MAX_LEVEL:
		return 1.0
	var xp_needed = get_xp_for_next_level()
	if xp_needed <= 0:
		return 1.0
	var xp_in_level = _xp - get_total_xp_for_level(_level)
	return clamp(float(xp_in_level) / float(xp_needed), 0.0, 1.0)

func get_total_xp_for_level(level: int) -> int:
	"""Retorna o XP total necessário para alcançar um determinado nível"""
	if level <= 1:
		return 0
	var total := 0
	for l in range(1, level):
		total += int(XP_BASE * pow(XP_GROWTH, l - 1))
	return total

func add_xp(amount: int) -> void:
	"""Adiciona XP ao personagem e verifica se houve nível up"""
	if amount <= 0 or _level >= MAX_LEVEL:
		return
		
	_xp += amount
	var old_level = _level
	
	# Verifica se subiu de nível
	while _level < MAX_LEVEL and _xp >= get_total_xp_for_level(_level + 1):
		_level += 1
		
	if _level > old_level:
		emit_signal("level_changed", old_level, _level)
		emit_signal("level_up_reached", _level)
		# Toque som de nível up se disponível
		_play_level_up_sound()
	
	emit_signal("xp_changed", amount, _xp)
	
	# Atualiza o SaveSystem
	var save_data = SaveSystem.dados
	save_data["xp"] = _xp
	save_data["nivel"] = _level
	SaveSystem.salvar()

func _play_level_up_sound() -> void:
	"""Toca som de nível up (se disponível)"""
	var caminho := "res://assets/audio/ui/switch1.ogg"
	if not ResourceLoader.exists(caminho):
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = load(caminho)
	sound.bus = "Efeitos"
	add_child(sound)
	sound.play()
	# Remove o nó após tocar o som
	sound.finished.connect(sound.queue_free)

# Métodos de conveniência para ganhos comuns de XP
func award_xp_for_discovery() -> void:
	"""Concede XP por descoberta"""
	add_xp(25)

func award_xp_for_mission_completed() -> void:
	"""Concede XP por missão concluída"""
	add_xp(100)

func award_xp_for_time_played(minutes: float) -> void:
	"""Concede XP baseado no tempo jogado"""
	var xp_amount = int(minutes * 2)  # 2 XP por minuto
	if xp_amount > 0:
		add_xp(xp_amount)
