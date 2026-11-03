# 📊 RELATÓRIO TÉCNICO DE OTIMIZAÇÃO - PROJETO FOREST
**Alvo:** Dispositivos Móveis (Android/iOS) | **Engine:** Godot 4.7  
**Data:** 03/11/2026 | **Status:** Diagnóstico Completo  
**Problema reportado:** FPS baixos em dispositivos móveis

---

## 1. RESUMO EXECUTIVO

O projeto **Forest** possui uma base de código bem estruturada, com sistemas já implementados que demonstram boas práticas (presets de qualidade, FSR, call_deferred para I/O, salva apenas ao concluir missão). No entanto, para lançamento em **dispositivos móveis**, existem **gargalos críticos de renderização e CPU** que explicam os FPS baixos relatados.

Os maiores culpados são: **(a) vegetação do Terrain3D sem LODs**, **(b) sombras direcionais ativas**, **(c) shader de água com 9-tap blur + refração**, **(d) milhares de nós individuais de milho**, e **(e) falta de shader baking**.

---

## 2. VISÃO GERAL DO PROJETO

### Arquitetura
| Componente | Caminho | Observação |
|------------|---------|------------|
| Cena principal | `world.tscn` | Mundo aberto 3D com Terrain3D, água, céu Sky3D, edifícios |
| Jogador | `character/scripts/jogador.gd` | CharacterBody3D, animação Mixamo, passos de áudio |
| Drone | `character/scripts/drone_jogador.gd` | Voo, pulverização, efeitos de velocidade |
| Trator | `character/scripts/trator_jogador.gd` | Direção, poeira, áudio motor |
| Agrobot | `character/scripts/agrobot.gd` | Segue jogador, física simples |
| Autoloads | `scripts/autoload/` | Jogo, SaveSystem, QualidadeGrafica, AudioConfig, etc. |
| UI | `scenes/ui/` | HUD, Diário, Menus, Controles de toque |
| Vegetação | `env models/plants/` | Árvores, arbustos, grama via Terrain3D MultiMesh |
| Shaders | `*.gdshader` | Água, árvore, grama, arbusto, céu |

### Configurações atuais do `project.godot`
- **Render method:** Forward+ (1)
- **Occlusion culling:** Habilitado ✓
- **VRAM compression (ETC2/ASTC):** Habilitado ✓
- **Shadow atlas:** 2048px (boa prática)
- **MSAA:** Desabilitado (boa prática)
- **Stretch mode:** `canvas_items` (questionável para 3D)
- **Window mode:** Fullscreen (modo 3)

---

## 3. ANÁLISE DE GARGALOS POR CATEGORIA

### 🔴 CRÍTICO - Impacto direto no FPS mobile

#### 3.1 Vegetação Terrain3D sem LODs (Pior problema)

**Evidência:** Em `world.tscn`, todos os `Terrain3DMeshAsset` têm:
```
lod0_range = 128.0
last_lod = 0
last_shadow_lod = 0
```

Isso significa: **nenhum LOD está configurado**. Todos os modelos de vegetação (árvores, arbustos, grama, rochas) são renderizados em full-detail independente da distância da câmera.

Densidades elevadas de grama:
- `grass_4`: densidade 9.86
- `grass_5`: densidade 8.13
- `grass main`: densidade 4.69
- `grass_1`: densidade 5.02

Com milhares de instâncias de grama em full LOD, o custo de vértices, draw calls e sombra é massivo em mobile.

**QualidadeGrafica já tem a lógica correta** (`DISTANCIA_VEGETACAO`, `LODS_TERRENO`), mas o problema é que os assets na cena não têm LODs definidos (`last_lod = 0`), então não há níveis de detalhe para alternar.

#### 3.2 Sombras direcionais ativas por padrão

**Evidência:** `world.tscn` linha 730-731:
```
shadow_enabled = true
shadow_opacity = 0.87
```

No `qualidade_grafica.gd`, o preset "baixo" desliga sombras, mas o padrão mobile é "baixo" — entretanto, se o usuário salvar "alto" ou "medio", as sombras voltam a custar caro. Sombras direcionais em Forward+ são uma das operações mais pesadas em GPUs móveis.

#### 3.3 Shader de água com 9-tap blur + refração + depth texture

**Evidência:** `watershader.gdshader` linhas 62-82:
```glsl
vec3 screen =
    texture(SCREEN_TEXTURE, refract_uv).rgb
    + texture(SCREEN_TEXTURE, refract_uv + vec2( blur.x, 0.0)).rgb
    // ... 9 amostras totais
screen /= 9.0;
```

Este shader usa:
- `DEPTH_TEXTURE` (leitura de textura de profundidade)
- `SCREEN_TEXTURE` (leitura do framebuffer)
- **9 amostras de textura por fragmento** (blur de refração)
- 3 normal maps animados com `TIME`

Em mobile (especialmente Mali/Adreno), ler `SCREEN_TEXTURE` e `DEPTH_TEXTURE` causa **bandwidth de memória enorme** e quebra otimizações de tile-based rendering. Este é um dos shaders mais caros da cena.

#### 3.4 Milhos plantados como nós individuais (sem instancing)

**Evidência:** `area_plantio.gd`:
- `_nos_milhos: Array[Node3D]` armazena cada milho como nó separado
- `quantidade_maxima = 400`
- Cada milho é instanciado via `_cena_milho.instantiate()` e adicionado como child individual
- Cada milho gera seu próprio draw call

400 milhos = 400 draw calls mínimos, mais custo de transformação e culling individual por nó. Em mobile, o limite seguro é ~100-200 draw calls por frame.

#### 3.5 Nenhum Shader Baking habilitado

**Evidência:** `export_presets.cfg`:
```
shader_baker/enabled=false
```
para todos os presets (Windows, Android, Web).

No mobile, compilar shaders em runtime causa **stutter perceptível** (micro-travamentos na primeira vez que cada material/shader é visível). Habilitar o Shader Baker pré-compila variantes no build.

---

### 🟡 MÉDIO - Impacto moderado, otimização recomendada

#### 3.6 Múltiplos AudioStreamPlayer3D ambientes em autoplay

**Evidência:** `world.tscn` linhas 596-675:
- 8 players de "Chirp" (pássaros)
- 2 players de "River"
- 2 players de "Air"
- Todos com `autoplay = true`, alguns com `unit_size = 100.0` (áudio ouvido em todo o mapa)

Em mobile, áudio posicional 3D consome CPU para cálculo de atenuação. 12+ players simultâneos é desnecessário para sons de fundo.

#### 3.7 Sinal de pulverização do drone emitido a cada frame

**Evidência:** `drone_jogador.gd` linha 421-422:
```gdscript
if ligado and spray.emitting:
    _avisar_pulverizacao(global_position)
```

E `area_plantio.gd` linha 330-340 itera sobre `_nos_milhos` (até 400 itens) a cada emissão:
```gdscript
for milho in _nos_milhos:
    # verifica distância ao quadrado
```

Se o drone pulveriza a 60 FPS, são 60 iterações por segundo sobre array de até 400 elementos = 24.000 verificações/segundo.

#### 3.8 Shaders duplicados (cópia e cola)

**Evidência:** `tree_shader.gdshader`, `fern_shader.gdshader`, `bush.gdshader` são **idênticos** (418 linhas cada). Três materiais separados com o mesmo código de shader. Isso consome mais memória de shader e impede batching eficiente.

#### 3.9 Rochas grandes e edifícios sem culling de distância

**Evidência:** `world.tscn` temos `MeshInstance3D` individuais para rochas grandes, silo, casa, galpão, etc., sem qualquer distância máxima de desenho. Eles são renderizados mesmo a 500m de distância.

---

### 🟢 BAIXO - Boas práticas já implementadas (manter)

| Item | Status | Comentário |
|------|--------|------------|
| `qualidade_grafica.gd` | ✅ Bom | Presets bem implementados, reaplica via `call_deferred` |
| FSR 1.0/2.0 | ✅ Bom | Upscaling configurável para mobile |
| VSync configurável | ✅ Bom | Pode desligar para desbloquear FPS |
| Occlusion culling | ✅ Bom | Habilitado no project.godot |
| Shadow atlas 2048 | ✅ Bom | Não usa 4096 desnecessário |
| 2 shadow splits | ✅ Bom | Reduz draw calls de sombra |
| MSAA desligado | ✅ Bom | FXAA usado em vez de MSAA |
| call_deferred para salvar | ✅ Bom | Não trava thread principal com I/O |
| Área de chuva localizada | ✅ Bom | Partículas só ao redor do jogador |
| Salvamento apenas por missão | ✅ Bom | Não há autosave a cada frame |

---

## 4. PLANO DE AÇÃO PRIORIZADO

### 🚨 FASE 1 - Crítico (Fazer imediatamente, maior ganho de FPS)

| # | Ação | Arquivo(s) | Impacto estimado |
|---|------|------------|------------------|
| 1 | Configurar LODs nos MeshAssets do Terrain3D (last_lod > 0, lod0_range menor para grama) | `world.tscn` | **Alto** (30-50% FPS) |
| 2 | Desligar sombras direcionais por padrão em mobile (forçar preset baixo) | `qualidade_grafica.gd`, `project.godot` | **Alto** (20-30% FPS) |
| 3 | Substituir shader de água por versão simplificada para mobile (sem 9-tap blur, sem refração de tela) | `watershader.gdshader` | **Alto** (15-25% FPS) |
| 4 | Converter milhos plantados para MultiMesh3D (renderização em lote) | `area_plantio.gd`, `milho_plantavel.tscn` | **Alto** (20-40% FPS com 400 milhos) |
| 5 | Habilitar Shader Baker no export Android | `export_presets.cfg` | **Médio** (reduce stutter) |

### ⚠️ FASE 2 - Médio (Otimizações importantes)

| # | Ação | Arquivo(s) | Impacto estimado |
|---|------|------------|------------------|
| 6 | Unificar shaders de vegetação (tree/fern/bush) em um único material compartilhado | 3 arquivos `.gdshader` | **Médio** |
| 7 | Adicionar distância máxima de draw (LOD0 range) para rochas e edifícios estáticos | `world.tscn` | **Médio** |
| 8 | Otimizar sinal de pulverização: throttling (ex: emitir a cada 0.1s, não todo frame) | `drone_jogador.gd`, `area_plantio.gd` | **Médio** |
| 9 | Reduzir número de AudioStreamPlayer3D ambientes (misturar sons de pássaro em poucos players) | `world.tscn` | **Baixo-Médio** |
| 10 | Limitar `Engine.max_fps` em mobile (ex: 60) para evitar aquecimento/bateria | `qualidade_grafica.gd` ou HUD | **Baixo** |

### 🔧 FASE 3 - Baixo (Polimento e boas práticas)

| # | Ação | Arquivo(s) |
|---|------|------------|
| 11 | Aplicar qualidade gráfica automaticamente com base no desempenho detectado em mobile | `qualidade_grafica.gd` |
| 12 | Occluders para edifícios grandes (silo, casa, galpão) | `world.tscn` |
| 13 | Usar `VisibilityNotifier`/`VisibilityEnabler` para milhos distantes | `area_plantio.gd` |
| 14 | Texture compression ASTC 4x4 ou 6x6 para mobile | Import settings |

---

## 5. RECOMENDAÇÕES DETALHADAS COM CÓDIGO

### 5.1 Configurar LODs no Terrain3D

Em `world.tscn`, alterar cada `Terrain3DMeshAsset`. Exemplo para grama:

```ini
[sub_resource type="Terrain3DMeshAsset" id="Terrain3DMeshAsset_w44yn"]
name = "grass main"
scene_file = ExtResource("5_gggvi")
density = 4.692052
last_lod = 2          # <-- adicionar LODs
last_shadow_lod = 1   # <-- sombra em LOD menor
lod0_range = 25.0     # <-- reduzir de 128 para 25 (grama distante não precisa de full detail)
```

Para árvores:
```ini
lod0_range = 60.0     # árvores podem ter LOD a 60m
last_lod = 2
```

### 5.2 Forçar preset baixo em mobile

No `qualidade_grafica.gd`, a função `padrao_plataforma()` já retorna "baixo" para mobile. Garantir que isso seja respeitado no início:

```gdscript
# Em _ready, forçar baixo em mobile se não houver save prévio
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile") and not SaveSystem.dados.has("grafico"):
		aplicar(PADRAO_MOBILE)  # forçar baixo no primeiro launch mobile
	else:
		aplicar(nivel_salvo())
	# ...
```

### 5.3 Shader de água simplificado para mobile

Criar uma variante `watershader_mobile.gdshader` sem:
- 9-tap blur (usar 1 amostra ou nenhum)
- Refração de `SCREEN_TEXTURE`
- Múltiplos normal maps animados

Manter apenas: cor por profundidade, fresnel simples, 1 normal map.

### 5.4 MultiMesh para milhos plantados

Substituir a instânciação individual de milhos por um `MultiMesh3D`:

```gdscript
# Em vez de criar 400 MeshInstance3D individuais:
var multimesh = MultiMesh3D.new()
var mm = MultiMesh.new()
mm.mesh = load("res://scenes/world/milho_plantavel.tscn").mesh
mm.instance_count = 400
mm.transform_format = MultiMesh.TRANSFORM_3D
multimesh.multimesh = mm
add_child(multimesh)

# Atualizar transformes por instância
for i in range(quantidade_plantada):
	mmultimesh.multimesh.set_instance_transform(i, Transform3D(Basis(), posicao))
```

Isso reduz 400 draw calls para **1 draw call**.

### 5.5 Throttling do sinal de pulverização

Em `drone_jogador.gd`, alterar `_process`:

```gdscript
var _ultima_pulverizacao := 0.0

func _process(delta: float):
	# ... código existente ...
	if ligado and spray.emitting:
		if Time.get_ticks_msec() / 1000.0 - _ultima_pulverizacao >= 0.1:
			_avisar_pulverizacao(global_position)
			_ultima_pulverizacao = Time.get_ticks_msec() / 1000.0
```

### 5.6 Habilitar Shader Baker para Android

Em `export_presets.cfg`, preset Android (preset.1):
```
shader_baker/enabled=true
```

---

## 6. CONFIGURAÇÕES DE EXPORTAÇÃO PARA MOBILE

### Android (`export_presets.cfg`)

Recomendações para o preset Android:

```ini
[preset.1.options]
architectures/arm64-v8a=true
architectures/x86_64=false   # manter falso a menos que precise de emulador
shader_baker/enabled=true    # ✅ HABILITAR
graphics/opengl_debug=false
screen/immersive_mode=true   # ✅ esconder barras do sistema
vram_texture_compression/etc2_astc=true  # ✅ já habilitado no project.godot
```

### Recomendações de runtime para mobile

| Configuração | Valor recomendado para mobile | Onde configurar |
|-------------|------------------------------|-----------------|
| Qualidade gráfica | "baixo" (padrão) | `qualidade_grafica.gd` |
| Upscaling | FSR 1.0, escala 0.67 | HUD > Gráficos |
| VSync | Desligado (deixa o dispositivo controlar) | HUD > Tela |
| Max FPS | 60 | `Engine.max_fps = 60` em `_ready` do jogo |
| Sombra direcional | Desligada | `qualidade_grafica.gd` |
| Água shader | Versão simplificada | `watershader.gdshader` |

---

## 7. MATRIZ DE IMPACTO VS ESFORÇO

| Ação | Impacto no FPS | Esforço | Prioridade |
|------|---------------|---------|------------|
| LODs Terrain3D | ⭐⭐⭐⭐⭐ | Médio | P1 |
| Desligar sombras mobile | ⭐⭐⭐⭐ | Baixo | P1 |
| Shader água simplificado | ⭐⭐⭐⭐ | Médio | P1 |
| MultiMesh milhos | ⭐⭐⭐⭐ | Médio-Alto | P1 |
| Shader Baker | ⭐⭐⭐ | Baixo | P2 |
| Unificar shaders vegetação | ⭐⭐ | Médio | P2 |
| Throttling pulverização | ⭐⭐ | Baixo | P2 |
| Reduzir players áudio | ⭐ | Baixo | P3 |

---

## 8. CHECKLIST DE TESTE EM MOBILE

Após aplicar as otimizações, testar em:

- [ ] Dispositivo Android de entrada (Snapdragon 4xx/6xx, 4GB RAM)
- [ ] Dispositivo Android intermediário (Snapdragon 7xx/8xx, 6-8GB RAM)
- [ ] Dispositivo iOS (iPhone SE ou similar)
- [ ] Medir FPS com o Debug > Monitor do Godot ou `Engine.get_frames_per_second()`
- [ ] Testar com 400 milhos plantados (pior caso de cena)
- [ ] Testar com drone pulverizando (pior caso de CPU)
- [ ] Testar aquecimento após 10 min de jogo contínuo
- [ ] Verificar consumo de bateria

---

## 9. CONCLUSÃO

O projeto **Forest** tem uma base sólida com sistemas de qualidade gráfica já implementados. Os FPS baixos em mobile são explicados principalmente por:

1. **Vegetação sem LODs** (milhares de instâncias em full detail)
2. **Sombras direcionais ativas**
3. **Shader de água caro** (9-tap blur + refração de tela)
4. **400 milhos como nós individuais** (400 draw calls)

Ao aplicar as otimizações da **Fase 1**, espera-se um **ganho de 40-60% no FPS** em dispositivos móveis de entrada/intermediário, tornando o jogo jogável com taxas acima de 30-45 FPS estáveis.

---

*Relatório gerado automaticamente com base na análise estática do código-fonte do projeto Forest (Godot 4.7).*