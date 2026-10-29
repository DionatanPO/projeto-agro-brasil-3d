extends SceneTree
## Script temporário de diagnóstico: mede o terreno e a escala do milho.

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var cena: Node = load("res://world.tscn").instantiate()
	root.add_child(cena)
	await process_frame
	await process_frame

	var terreno: Node = cena.get_node_or_null("Terrain3D")
	if terreno == null:
		print("SEM TERRAIN3D")
		quit()
		return

	print("--- Alturas do terreno (x, z -> y) ---")
	var xs: Array = []
	var zs: Array = []
	for x in range(140, 236, 8):
		xs.append(float(x))
	for z in range(110, 236, 8):
		zs.append(float(z))
	for z in zs:
		var linha := ""
		for x in xs:
			var h: float = terreno.data.get_height(Vector3(x, 0.0, z))
			linha += "%6.1f " % h
		print("z=%5.0f | %s" % [z, linha])
	print("x     = ", xs)

	# Teste de planicidade em blocos de 24x24
	print("--- Blocos planos (desvio máx < 1.2m) ---")
	var melhor := Vector2.ZERO
	var melhor_desvio := 999.0
	for cz in range(130, 226, 8):
		for cx in range(140, 226, 8):
			var hmin := 9999.0
			var hmax := -9999.0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var h: float = terreno.data.get_height(Vector3(cx + dx * 8.0, 0.0, cz + dz * 8.0))
					hmin = minf(hmin, h)
					hmax = maxf(hmax, h)
			var desvio := hmax - hmin
			if desvio < melhor_desvio:
				melhor_desvio = desvio
				melhor = Vector2(cx, cz)
			if desvio < 1.2:
				print("centro (%d, %d) desvio %.2f  y=%.2f" % [cx, cz, desvio, (hmin + hmax) * 0.5])
	print("Melhor bloco: ", melhor, " desvio ", melhor_desvio)

	# Escala do milho
	var milho_cena: PackedScene = load("res://scenes/world/milho_plantavel.tscn")
	if milho_cena != null:
		var milho: Node = milho_cena.instantiate()
		root.add_child(milho)
		var aabb := _aabb_recursivo(milho as Node3D, Transform3D.IDENTITY)
		print("--- Milho ---")
		print("AABB: ", aabb)
		print("Tamanho: ", aabb.size)
		milho.queue_free()

	quit()


func _aabb_recursivo(no: Node3D, base: Transform3D) -> AABB:
	var resultado := AABB()
	var primeiro := true
	var t: Transform3D = base * no.transform
	if no is MeshInstance3D and (no as MeshInstance3D).mesh != null:
		resultado = t * (no as MeshInstance3D).mesh.get_aabb()
		primeiro = false
	for filho in no.get_children():
		if filho is Node3D:
			var a := _aabb_recursivo(filho as Node3D, t)
			if a.size != Vector3.ZERO:
				if primeiro:
					resultado = a
					primeiro = false
				else:
					resultado = resultado.merge(a)
	return resultado
