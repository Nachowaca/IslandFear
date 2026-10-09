# Islander Fear — Progreso

> Estado actual. Actualizar al final de cada sesión. Diseño y decisiones en `DESIGN.md`.

## Estado: prototipo jugable de exploración + IA de la isla (sin supervivencia aún)

## Hecho y funcionando
- [x] Agua con shader + mapa de altura; ventana 1920x1080, F11 pantalla completa.
- [x] Escena principal `res://scenes/game.tscn`.
- [x] Isla de radio 60 m: laguna, meseta con cueva, flora, colisiones, `height_at`, `find_spot`.
- [x] Elementos especiales: cueva con sello y cristales, piedras, árbol gigante, naufragio, mojones, círculos de hongos.
- [x] Náufrago: movimiento, animación procedural, salto, correr, subir escalones bajos, salud, regeneración, refugio.
- [x] Barca nueva de tablas + vela con shader + plancha de desembarco con colisión real. Bajada verificada en juego.
- [x] Fix: el freno de "mar profundo" bloqueaba el control sobre la barca (corregido en `castaway.gd`).
- [x] Día/noche en tiempo real con astronomía, luna con fase, estrellas, faro.
- [x] Viento en follaje, partículas ambientales y de pasos, mariposas, pájaros, cangrejos (hostiles a pedido de la isla).
- [x] Audio sintetizado completo; sonido de la isla de menos a más al acercarse la barca; crujidos al navegar.
- [x] HUD de salud (corazón, marco, rastro de daño, "Refugio"), panel de mente (I), mensajes de la isla, pantalla de muerte con recarga.
- [x] Cerebro de la isla rehecho (ver DESIGN): estudio de 2–3 días, solo ataca por agravios, advertencia previa, perdón, humor errático, carácter por partida, estudio de movimiento, memoria entre muertes.
- [x] Voz de la isla variable (`island_voice.gd`), frases crípticas, apodos según tu conducta.
- [x] Presagios nuevos: `echo` (luz que repite tu camino), `footsteps`, `wisp` (`wisp.gd`).
- [x] Cargan sin errores (último smoke test del cerebro nuevo: 3 s en `game.tscn`).

- [x] Personaje rehecho (`castaway_rig.gd`, construido por código): piernas con muslo/rodilla/tobillo/pie con dedos, brazos con hombro/codo/muñeca/mano con dedos, cuello, cabeza de más polígonos con cara (cejas, párpados con parpadeo, ojos que miran, boca, mandíbula), barba, 7 mechones de pelo largo con inercia, túnica corta de 10 paneles rasgados que reaccionan al paso (se ven rodillas y pies). Marcha y carrera con apoyo en el suelo automático (la cadera sube y baja para que el pie toque), inclinación al acelerar/girar, rodillas flexionadas al aterrizar, pose de salto. Verificado en escena de prueba (caminar, correr, cara, dolor).
- [x] Expresiones: `Castaway.express(nombre, segundos)` con neutral, fear, pain, tired, smile, curious, determined, surprise, suspicious, scared_still. Automáticas: dolor al recibir daño, cansado con poca vida, determinado al correr, sorpresa al caer. El cerebro de la isla todavía NO las dispara (idea: miedo/sospecha ante presagios).

- Nota: el usuario dice que el personaje funciona pero NO le gusta del todo; retomar el pulido de diseño más adelante (cara, proporciones, ropa). Plan de jugabilidad/acciones del personaje: pendiente.

- [x] Prompt 1 (memoria + emociones) hecho: autoload `Isla` (`scripts/isla.gd`, registrado en project.godot). Contadores (total y de la vida actual), mapas `calor_paso`/`calor_dano` por celdas de 8 m, emociones confianza/enojo/miedo/curiosidad con base y decaimiento, `registrar_evento(tipo, zona, intensidad)`, `sumar_tiempo`, `sumar_paso`, señal `emocion_cambiada`, guardado en `user://isla.json` (autoguardado cada 30 s y al salir; `Isla.reiniciar_memoria()` borra todo). Vida 1 nace con carácter al azar. `island_brain.gd` ya le informa: pasos, explorar, correr, animales molestados, frutos, zona sagrada, muerte; la curiosidad del cerebro viene de Isla. Verificado con prueba unitaria (eventos, decaimiento, contadores). Eventos aún sin fuente en el juego: arbol_cortado, fuego, animal_cazado, ofrenda, cuidado.
- [x] Prompt 2 (decisión) hecho: `AccionIsla` (Resource, `scripts/accion_isla.gd`) con catálogo de 18 `.tres` en `res://data/acciones/` (editables en el inspector: base, peso_emocion, peso_contexto, cooldown, costo, dano, implementada). `island_brain._think()` corre cada 1–2 s: calcula contexto (noche, quieto, cueva, playa, bosque, sagrado...), puntúa con las emociones de `Isla`, elige por azar ponderado (score^1.5) y "nada" compite; entre acciones hay un hueco de silencio de cola larga. Las acciones nuevas (niebla, tormenta, sonidos, mover_vegetacion, criatura, regalo) solo quedan en el registro. Cada decisión se imprime y se escribe en `user://isla_decisiones.log` (se reinicia por partida) y las últimas 3 salen en el panel de mente (I). Los agravios del cerebro siguen en paralelo (decisión del usuario). Verificado en juego: elige, puntúa y registra; "nada" compite.
- Nota editor: a veces aparece "Identifier not found: Isla" en el log del editor (análisis viejo); en juego funciona. Reiniciar el editor lo limpia.
- [x] Prompt 3 hecho: (a) UI de 7 vidas (`lives_bar.gd`, gemas turquesa sobre el medidor de salud; se apagan con destello al morir; toast "Vida N de 7"). (b) Acciones reales: `niebla` (DayNight.fog_boost, sube 12 s, sostiene 25–55 s, se disipa 18 s; verificada visualmente), `sonidos` (AudioManager.play 3D cerca del jugador según lugar/hora; 1–3 sonidos que se mueven), `mover_vegetacion` (Wind.set_gust sacude todo el follaje con gust_strength). Quedan sin efecto: tormenta, criatura, regalo. (c) 7 vidas: `Isla.cerrar_vida()` desplaza las emociones base según cómo jugó (destructivo → más enojo/desconfianza, cuidadoso/pacífico → más confianza) y avanza la vida; persiste en disco. (d) Final tras la 7ª muerte: `Isla.calcular_final()` → convivir / no convivir según acumulado; texto compuesto con piezas variables (perfil destructor/cuidador/explorador/neutral); pantalla negra `Hud.show_ending`, luego `Isla.nuevo_ciclo()` (carácter distinto, sesgado según cómo terminó el anterior) y `IslandBrain.olvidar_todo()`. Verificado: lógica con prueba unitaria, pantalla de final y niebla en juego. Sin verificar: sonidos y racha de vegetación a oído/ojo, ciclo completo de 7 muertes reales.
- Pendiente (usuario): definir el fin del jugador (sobrevivir o desarrollar más sus acciones). Hoy los eventos arbol_cortado/fuego/animal_cazado/ofrenda no tienen fuente en el juego, así que el perfil depende de animales molestados, lugares sagrados y exploración.
- (histórico) Prompt 3 (acciones reales: niebla, sonido 3D, vegetación; 7 vidas, final). El enojo de Isla todavía NO reemplaza a `offense` del cerebro (siguen en paralelo).
- Ojo: `user://isla.json` persiste entre partidas de prueba y condiciona la isla; borrar con `Isla.reiniciar_memoria()` si hace falta.

## FASE 2 en curso: supervivencia básica (inventario, acciones, crafteo)
Orden acordado: 1) inventario + recoger/dejar + investigar ✅ · 2) probar/comer (+ hambre y sed, venenos) · 3) cortar (necesita piedra afilada: árboles → madera, ramas, fibra; evento `arbol_cortado`) · 4) combinar/crafteo (piedra+piedra→piedra afilada, hacha, cuerda, fuego; evento `fuego`) · 5) más objetos que la isla note (ofrendas, animales pequeños cazables), flora/cuevas/misterios con el pack de assets.
- [x] Pieza 1 hecha: autoload `Inventario` (`inventario.gd`, 10 espacios, pilas de 9, se vacía al morir); `ItemDB` (`item_db.gd`, catálogo con texto de "investigar" vago a propósito, color/forma, comida/ofrenda); `Interaccion` (`interaccion.gd`): **E** recoger/beber del estanque, **G** dejar 1 (Shift = todo), **F** investigar (objeto delante, lugar sagrado cercano u objeto elegido), **1-9/0 o rueda** elegir. `InventoryUi` (`inventory_ui.gd`): barra de 10 espacios abajo al centro, cartel de acción, avisos, texto de investigar. La vista aérea ahora es solo **M** (Tab liberado). La isla se entera: dejar una ofrenda (concha, comida, hierba) junto a un lugar sagrado → `Isla.registrar_evento("ofrenda")`; investigar → curiosidad; beber → `cuidado`; el cerebro solo cuenta como "tomado" la comida silvestre (no madera/piedras ni lo que el jugador dejó). Verificado en juego con secuencia forzada (recoger bayas y piedra, investigar, dejar). Sin verificar: investigar texto en pantalla, ofrenda en lugar sagrado, inventario lleno.
- [x] Pieza 2 hecha (hambre, sed y comer): `Castaway.hambre` y `Castaway.sed` (0–100, empiezan en 100; bajan 0.08 y 0.14 por segundo, ×1.6 al correr; export `hunger_decay`, `thirst_decay`). Con 0 drenan salud lento (`drain_health`, sin destello); con ≤10 % no hay regeneración de salud. `NeedsBar` (`needs_bar.gd`) dibuja los medidores a la derecha de la salud: verdes, rojos y titilantes al llegar al 10 % o menos, cada uno por separado; para sumar un medidor nuevo basta una entrada en `NeedsBar.METERS` y una propiedad 0–100 en el jugador (el usuario quiere más medidores más adelante). **R** prueba/come el objeto elegido (hambre/sed/salud según `ItemDB`); el hongo rojo envenena (daño + pierde hambre + cara de dolor); beber del estanque con E da +35 sed. Verificado en juego: barras verde/rojo y comer bayas. Sin verificar: hongo venenoso en pantalla, morir de hambre/sed. Falta: animal crudo (cuando haya caza).
- [x] Piezas 3 y 4 hechas (cortar, combinar, fuego): **Q** cortar, **C** abre el panel de recetas (rueda elige, E fabrica). Recetas (`recipes.gd`): cuchilla de piedra (2 piedras, gasta 1), cuerda de lianas (2) o de hojas grandes (3), hacha (rama + cuchilla), lanza (rama + cuchilla + cuerda; sin uso aún), encender fuego (2 piedras + paja, rama o madera: paja+leña 95 %, solo paja 85 %, solo leña 30 %; las piedras no se gastan). Objetos nuevos en `ItemDB`: piedra_afilada, hacha, cuerda, liana, hoja_grande, paja, lanza. Mundo: ~46 matas de paja y hasta 26 hojas grandes caídas bajo palmeras; la mitad de los árboles tiene 1–2 lianas colgando (visibles) y cada palmera 4 hojas. Con cuchilla: Q corta una liana (árbol) o una hoja (palmera). Con hacha: Q golpea (árbol 4–5 golpes, palmera 3), el árbol cae (`IslandTerrain.fell_tree`, sin colisión, tween) y deja 2 troncos + 2 ramas (palmera: troncos + hojas); sale de `tree_nodes`/`tree_positions`. Fogata (`campfire.gd`): llama, humo, brasas, luz parpadeante, crujidos; leña 120 s (madera), 50 s (rama), 18 s (paja), máx 360 s; E cerca con leña elegida la aviva; queda brasas 25 s. Comida más realista: coco sed 30/hambre 15, bayas 10/7, raíz 4/22, hongo pardo 7/5, hierba cura 12. La isla reacciona en vivo (`Isla.evento_registrado` → `IslandBrain._on_evento`): talar suma agravio ("trees") y dice frase de reacción; fuego idem ("fire"); ofrenda dice frase. Verificado en juego: panel, fabricar cuchilla/cuerda/hacha, fogata con humo y luz, talar con mensaje y reacción de la isla. Sin verificar: cortar lianas/hojas en pantalla, mantener fuego con leña, fuego solo con paja, lanza. Una de tres corridas de prueba no encendió el fuego (causa no determinada; en las otras dos sí): vigilar. No hay desgaste de herramientas aún.
- [x] Rediseño de interfaz (pedido del usuario: menús antiguos y letra chica): `UiTheme` (`ui_theme.gd`) con fuentes libres Cinzel (títulos) y Alegreya Sans (texto) descargadas a `res://assets/ui/` (OFL), paleta mar profundo + latón + turquesa, panel de madera oscura (`ui_panel_tile.png`) con remaches; letra base 22. Íconos pintados a mano generados con IA para los 18 objetos + fuego (`assets/generated/ui_icon_*.png`; si un ícono no está importado el tema lo lee directo). Rehechos: barra de objetos (64 px, ícono + cantidad + nombre del elegido), cartel de acciones con teclas en recuadros de latón, avisos y panel de investigar grandes, panel de combinar con ícono por receta, medidores de hambre/sed con marco y número, toasts de la isla en Cinzel 34, panel de mente con estilo. **H** abre `HelpUi` (`help_ui.gd`): ayuda en 5 secciones (Moverte, Actuar, Fabricar, Sobrevivir, Sistema) con para qué sirve cada tecla; arriba a la izquierda queda "H Ayuda". Verificado en juego. Pendiente de rediseñar al mismo estilo: medidor de salud (corazón), vidas, reloj temporal, pantalla de muerte/final. Nota: no se pudo navegar la web; no hay pack de UI de terceros (solo fuentes libres + arte generado).
- [x] Frases de la isla legibles: ahora en tipografía sans del sistema estilo Helvetica (`UiTheme.sans()`: Helvetica Neue / Helvetica / Arial), tamaño 30, dentro de un panel oscuro translúcido (negro 72 %) con borde fino; colores por tipo algo más claros (susurro lila, presagio ámbar, ataque rojizo, info gris claro). Verificado en juego. Mejoras de UI que el usuario ve pendientes: ir sumando.
- Idea para después: abrir cocos con cuchilla, antorcha (rama + paja + fuego), cocinar, calor/frío con la fogata, cuerda para balsa; fuego/talar cerca de lugares sagrados como agravio mayor.
- Assets: el pack Stylized Nature MEGAKIT está en la raíz del proyecto (`res://glTF`, también `OBJ`, `FBX`, `Textures`): árboles (CommonTree, DeadTree, TwistedTree, Pine), arbustos, helechos, pastos, flores, hongos (Mushroom_Common, Mushroom_Laetiporus), guijarros (Pebble_*), rocas (Rock_Medium_*), piedras de camino. Usar los `.gltf`. Todavía no se usan; pensado para mejorar flora, objetos recolectables (piedras, hongos) y misterios. FBX y OBJ sobran (se podrían borrar para acelerar importaciones; preguntar antes).

## FASE "la isla viva y la convivencia" (en curso)
Plan en 5 pasos (acordado, ver reglas en DESIGN): 1) vínculo y ataques con descanso de días ✅ · 2) regalos reales (con sed/hambre/poca salud y confianza: aparecen cocos, bayas o agua en tu camino, hierba junto a la cueva, luciérnagas guía; si está enojada retira frutos de arbustos cercanos) · 3) silencios con significado (pacífico: pájaros y viento suave; hostil: se apagan y se cortan antes de una amenaza) · 4) noche y ataques en escalera: presagio → aviso → golpe, tormenta y criaturas (acciones `tormenta`, `criatura`, `regalo` aún sin implementar), tregua por ofrenda · 5) convivencia alimenta el final de convivir.
- [x] Paso 1 hecho: `Isla.vinculo` + etapas (6) + `etapa_cambiada` + `tick_paz`; `IslandBrain`: ataques bloqueados si Aceptante/Aliada, solo agravios graves si Tolerante, descanso largo `_attack_rest` tras cada golpe, `ambient_mood()`, tono de frases por etapa, frases al subir/bajar de etapa (`etapa_up_N`/`etapa_down_N`), cueva dorada (`IslandFeatures.set_cave_warmth`), pájaros según clima (`AudioManager`), línea "Vínculo" en el panel de mente (I). `Castaway.island_floor = 8`: rocas, raíces y cangrejos no matan (veneno, hambre y sed sí). Verificado con prueba unitaria (ofrendas, talar, cazar, paz con tope 40, no letal) y carga en juego. Sin verificar en partida larga: ritmo de ataques en días, cueva dorada en pantalla, frases de cambio de etapa. Ojo: `user://isla.json` guarda el vínculo entre partidas de prueba.

## Revisión de assets para el diseño de la isla (hecha)
- **Stylized Nature MegaKit** (`res://glTF/*.gltf`, 68 modelos, ya importados): CommonTree 1–5 (~7 m, 6k tris, copa roja en la vista previa), TwistedTree 1–5 (13–17 m, 9k tris: muy grandes, ideales como árboles místicos únicos), DeadTree 1–5, Pine 1–5 (~7 m, 4k tris), Bush_Common(+Flowers) 0.9k, Fern, Grass_Common/Wispy short/tall (~300 tris), Flower_3/4 group/single, Plant_1/7 (+Big), Clover, Mushroom_Common/Laetiporus (0.9k), Rock_Medium 1–3 (0.3k), Pebble_Round/Square 1–6, RockPath (caminos de piedra, 3.5k tris cada uno: usar con moderación), Petal 1–5. Estilo pintado suave, más rico que nuestros primitivos. Todo con colores/texturas propias.
- **Terrain3D v1.0.2** (addon con GDExtension): **no tiene binario macOS arm64 usable**: sí trae `libterrain.macos.*.framework` (hay que comprobar que cargue). Es un terreno editable por clipmap, pensado para terrenos grandes; nuestra isla es chica y procedural, así que lo dejamos como opción, no como base.
- **SimpleXTerrain** (C#): requiere C#/.NET, el proyecto es GDScript. Descartado. Sus texturas de demo (Grass003/008, Ground067/090, Rock026/029/032/050, RockFace) sirven como **texturas PBR para arena/tierra/roca** del terreno actual.
- Plan: mantener nuestro terreno procedural (colisiones y vida ya funcionan) y mejorarlo: texturas PBR por altura/pendiente, flora del MegaKit con MultiMesh (rendimiento), árboles místicos únicos, misterios (piedras, hongos, claros), agua (espuma/olas), fauna chica con primitivos.

## Rediseño visual de la isla (en curso)
- [x] `scripts/nature_kit.gd` (`NatureKit`): carga modelos del MegaKit corrigiendo materiales (las hojas del pack son una textura blanca; se usa la `_C` verde; las de TwistedTree son rojas de otoño y se reemplazan por la verde; sin culling; sin color de vértices), distancia de dibujado limitada y `multi()` para instancias múltiples.
- [x] Árboles del bosque = CommonTree 1–5 (y Pine en altura), escala 0.62–1.0, con colisión, lianas y talado como antes. Arbustos = Bush_Common(+Flowers). Rocas = Rock_Medium 1–3 con colisión esférica. Las palmeras siguen siendo las nuestras (primitivas): **pendiente cambiarlas**.
- [x] Cobertura del suelo (`IslandLife._spawn_kit_ground`, tabla `GROUND_KIT`, MultiMesh): helechos, pasto alto/corto/ralo, flores, tréboles, plantas grandes, piedritas. El pasto viejo se redujo a 900 puntos.
- [x] Terreno: variación de tono por triángulo (ruido) + grano de detalle triplanar (NoiseTexture2D) para romper lo liso.
- [x] Misterio 1 — **árbol corazón** (`_spawn_heart_tree`): TwistedTree_2 gigante en un punto fijo por semilla (con seed 7: (-19, 5, -2)), círculo de 14 hongos y piedras, luz turquesa y puntos luminosos que brillan de noche (no está registrado aún como lugar sagrado de la isla).
- [x] Palmeras poligonales eliminadas (árboles de la costa con CommonTree inclinados; mecánica de palma intacta). Plan de assets y misterios (piedras de náufragos, etc.) en `docs/PLAN_VISUAL.md`.
- Pendiente: textura PBR por pendiente (texturas de SimpleXTerrain), más misterios (camino de piedras a la cueva, flores nocturnas, claros), fauna chica (mariposas, luciérnagas, lagartijas), agua (espuma/olas), viento en la vegetación nueva, rendimiento en partida larga (los árboles tienen ~6k tris; si baja el FPS, bajar `tree_count` o usar menos variantes).

## Decisión pendiente: el fin del jugador (retomar mañana)
Dos direcciones, combinables; el usuario elige el eje:
1. **Sobrevivir:** hambre, sed, frío/temperatura, fogata, refugio, qué restaura salud (frutos, cocos, raíces, hierbas, agua dulce, descansar en la cueva de día). El jugador intenta durar; las acciones de la isla (niebla, tormenta, criaturas) ponen la presión. Requiere: interacción (E), inventario, medidores.
2. **Desarrollar sus acciones:** cortar árboles, cazar, hacer fuego, ofrendar, construir. Activa los eventos que `Isla` ya espera (`arbol_cortado`, `fuego`, `animal_cazado`, `ofrenda`, `cuidado`) y vuelve más rico el perfil del final (destructor / cuidador). Hoy esos eventos no tienen fuente en el juego.
Después de elegir: armar plan de jugabilidad y acciones del personaje. Aún sin implementar: acciones de isla `tormenta`, `criatura`, `regalo`. Pulido pendiente: diseño del personaje (al usuario no le gusta del todo).

## Para mañana: frases más inteligentes (pedido del usuario)
- Problema: las frases de la isla a veces parecen sueltas y sin sentido; solo reaccionan bien al entrar al templo (cueva) y al correr.
- Objetivo: que reaccionen a momentos EN VIVO (lo que el jugador hace ahora: entra/sale de un lugar, se acerca a un animal o a un lugar sagrado, toma algo, se detiene, cambia de día a noche, recibe daño, se esconde, vuelve a un sitio) y tengan hilo conversacional (referirse a lo dicho antes, no repetir tema, escalar según el humor).
- Ideas: sistema de "disparadores" por evento (señales/transiciones de estado) con prioridad sobre el comentario aleatorio de `whisper`; comentarios sobre lo que acaba de pasar (últimos 5–10 s) en vez de la ventana larga; memoria de temas recientes; frases ligadas al lugar concreto (nombre real del sitio); silencio cuando no hay nada relevante en vez de frases genéricas.
- Archivos: `island_brain.gd` (`_speak_about_player`, `_study_movement`), `island_voice.gd` (POOLS).

## Sin verificar en juego largo
- Estudio completo (2–3 días de 300 s), veredicto y ataque por agravios.
- Presagios nuevos (eco, pasos, luz): visual y volumen a oído.
- Plural/género de las frases críptica y nombres de lugares sagrados (se corrigió " de el " → " del ").
- Sonido de la isla al acercarse: no se pudo escuchar desde el entorno de pruebas.

## Próximos pasos (orden sugerido)
1. Decidir con el usuario qué restaura salud; luego interacción (E), inventario, comer/beber.
2. Medidores de hambre/sed/temperatura.
3. Clima controlado por el cerebro.
4. Sacar el reloj temporal.
5. Ajustes finos: tamaño de vela, velocidad del fade de sonido, HUD segmentado.

## Archivos clave (`res://scripts`)
main.gd (llegada, vista aérea) · castaway.gd · boat.gd · island_terrain.gd · island_life.gd · island_features.gd · island_brain.gd · island_voice.gd · wisp.gd · rockfall.gd · thorn_roots.gd · watcher_eyes.gd · hud.gd · day_night.gd · lighthouse.gd · wind.gd · ambient_fx.gd · audio_manager.gd · sound_bank.gd · bird.gd · crab.gd · butterfly.gd. Shaders en `res://shaders` (water_island, wind_foliage, sail).

## Perillas de ajuste
- `island_brain.gd`: `aggression`, `day_length_seconds` (bajar a ~20 para probar el estudio rápido), `study_days_min/max`.
- Nodo `Audio`: `master_db`. Faro: `rotation_period`, `bounce_count`. HUD: `segmented`.

## Trucos de prueba (quirks del entorno)
- `run_scene`: las entradas inyectadas NO llegan al polling de Input. Forzar estado en código marcado `TEMPTEST`, probar, quitar y comprobar que no queda (`grep TEMPTEST`).
- `grep_code`/`Glob` a veces devuelven resultados viejos o vacíos: releer el archivo con Read.
- `print()` no se captura; escribir a un archivo temporal si hace falta.
- Diagnósticos de `edit_file` suelen ir desfasados: confiar en `run_scene`.
- Para ver de día: poner `_offset_hours = 12` en `day_night.gd` (temporal).
- Tras reiniciar Ziva, verificar qué ediciones se aplicaron.
- Si el editor tiene la escena vieja en memoria, cerrar pestaña sin guardar y reabrir.


## Piedras talladas y viento (sesión actual)
- `stela.gd` / `stela_texts.gd`: piedras talladas legibles (Label3D claro + oscuro simulan el relieve), pistas cortas en 4 bloques temáticos; el bloque cambia cada 5 muertes. Hasta 8 piedras por la isla + tumbas de las vidas anteriores (`Isla.tumbas`, epitafio con causa y hechos). Se leen con F; una ofrenda cerca cuenta como ofrenda.
- Piedra procedural gris (ruido celular triplanar). Las texturas atlas del MegaKit no sirven para esto.
- `wind_leaf.gdshader` + `NatureKit._fixed`: árboles, arbustos y pastos del MegaKit se mecen con el viento y reaccionan a las rachas (`Wind.register`).
- Pendiente: mariposas de día, restos de naufragio, camino de piedras al árbol corazón, espuma del agua, terreno PBR por pendiente. Nada de esto está subido a GitHub.


## Fase 1 visual: terreno y forma de la isla (hecha)
- Isla 4 veces más grande (radio 60 → 120 m). Laguna (-32,28) y cueva (48,-40) movidas; conteos de árboles/recursos x2-2.5; barca arranca en (236,0,88); gaviotas y cámara aérea escaladas.
- `terrain_island.gdshader`: 4 capas PBR (arena, pasto, suelo de bosque, roca; ambientCG CC0, 1K, VRAM comprimido con mipmaps, en `assets/terrain/`), mezcladas por altura, pendiente y ruido; roca triplanar; arena mojada en la orilla; el pasto se seca o se avive según `Isla.vinculo` (sin mostrarlo).
- Forma: playa ancha (17% del radio), acantilados al oeste (meseta de ~9 m con pared casi vertical y terrazas), colinas más altas, malla 240x240 con diagonales alternadas. El `.tscn` ya no guarda la malla (se genera al cargar; `@tool` quitado).
- `bridge.gd`: puente de madera de la costa norte al faro, ROTO a mitad (5.5 m sin tablones, tablones colgando, sogas sueltas, tocones). Sin forma de cruzar aún: reparación pendiente de diseñar (recoger tablas y soga).
- `floating_rock.gd`: roca flotante misteriosa sobre un círculo de piedras con runas; gira, flota, fragmentos orbitan, brilla de noche. Lugar sagrado "Roca flotante".
- El faro ahora se calcula según la costa (islote a 46 m de la orilla).
- Rendimiento medido: ~45-60 fps en M1 Max con la isla grande.
- Pendiente: espuma de olas, naufragio, camino de piedras, mariposas, ideas para reparar el puente, revisar noche en la isla nueva.


## Contacto y ecología (hecho)
- `foot_fx.gd` (FootFx): el jugador deja huellas en la arena (decals, se borran en ~2 min, más marcadas en arena mojada) y levanta arena/hojas al pisar.
- `foliage_push.gdshaderinc` + globales `foot_0..3`: pasto, helechos y arbustos se doblan, se aplastan y vuelven con retraso (inercia) al pasar; los árboles no.
- Ecología en `island_terrain.gd`: arena casi sin árboles (solo troncos secos DeadTree), costa con árboles inclinados, bosque por manchas (`forest_value`), humedad junto a la laguna (`moisture_at`, árboles retorcidos), pinos en altura, matorral costero, derrumbe de rocas al pie del acantilado. `island_life.gd` `GROUND_RULES`: pradera, sotobosque, duna y orilla.
- Pendiente: huellas de animales, olas/espuma, ver la noche.

## Pack Ultimate Stylized Nature (Quaternius, CC0)
- En `assets/ultimate_nature/` (`glTF/` solo tiene 36 modelos: abedul, arce, muertos, arbustos, flores, pasto; palmeras/pinos/árbol normal/rocas están SOLO en `FBX/`, que extraje de esas categorías). Texturas grandes limitadas a 1K en el import.
- `NatureKit.make_uq(model)` carga FBX del pack (escala 100 en el nodo; palmera ~5 m), asigna texturas y viento. Las palmeras de costa ahora son `PalmTree_1..5` reales (472 tris).
- Pendiente: abedul/arce en el bosque, arbustos y flores del pack, rocas.

### Pack Quaternius integrado (2.ª parte)
- Bosque: 22% abedules y 18% arces (arce teñido de verde con la textura BW; la original es roja de otoño), troncos secos `DeadTree_1..10` del pack en la arena, 45% de arbustos y 55% de rocas del pack (`make_uq`).
- `main.gd` `skip_voyage = true`: la barca arranca a 6 m de la orilla para probar rápido. Poner `false` para recuperar el viaje completo desde el horizonte.
- Cuidado: `NatureKit.make_uq` usa caché con prefijo `uq:` (los nombres DeadTree_* chocan con los del MegaKit).
- Pendiente: flores/pasto del pack, pinos y árboles normales del pack (FBX), probar rendimiento largo.
- Flores del pack (`Flower_1..5_Clump`, `Flower_1`, `Flower_2`) en `GROUND_KIT` con prefijo `UQ:` (MultiMesh, vis 75-120 m); las flores MegaKit bajadas de 130 a 40. El pasto del pack NO se usa (decisión: ahorrar memoria).

## EcoMap capas 2-5 + memoria de bioma (hecho)
- `eco_map.gd`: agua (`get_dist_agua`), humedad (`get_humedad`), suelo (`get_suelo`, enum Suelo), bioma (`get_bioma`, `get_bioma_pesos`, enum Bioma). Overlay F6/F7 con 7 capas. Parámetros nuevos en `eco_params.gd` (`base_humidity`, `humidity_reach`, `sea_humidity`, `valley_radius`, `sand_width`, `sand_max_height`, `fertile_humidity`).
- `Isla` guarda `bioma_tiempo` y `bioma_eventos` (persisten en isla.json), `bioma_favorito()`, `eventos_en_bioma()`. El cerebro suma tiempo por bioma y a veces comenta el bioma favorito (`obs_bioma_*` en island_voice). Todavía NO cambia ataques ni regalos.
- Pendiente: capa 6 (vegetación; decidir reemplazar vs convivir) y 7 (zonas misteriosas).

## EcoMap capa 6 (vegetación por bioma, primera versión)
- Decisión: el EcoMap REEMPLAZA las reglas viejas de plantado. `IslandTerrain.eco` lo crea la isla antes de plantar; `main.gd` lo reutiliza.
- `_scatter_flora`: densidad de árboles, mezcla abedul/arce, arbustos y afloramientos de roca salen de `eco.get_bioma_pesos()`. Palmeras, árboles secos y talud de acantilados siguen con sus reglas.
- Pendiente: flores/MultiMesh por bioma (`island_life.gd` GROUND_RULES todavía usa las reglas viejas), separación mínima tipo Poisson, capa 7 zonas misteriosas.

## EcoMap completo (capas 6 y 7)
- Flores, pasto y helechos (`island_life.gd` `_ground_ok`) siguen los pesos de bioma. Separación mínima de 2,6 m entre árboles (`_too_close`).
- Capa 7: `get_misterio(pos)`; 6 claros (~6 % de la tierra), semilla propia `mystery_seed`, distancia mínima 40 m. Dentro: casi sin árboles, más rocas y flores. Overlay F7 capa 7. Visualmente falta ver un claro de cerca.

## Sesión: cueva pozo, pack nuevo, personaje nuevo
- Cueva = pozo de 8 m con paredes/techo de rocas del pack nuevo y rampa; luces flotantes.
- Vegetación solo del pack Quaternius (árboles, arbustos, rocas, plantas, pétalos). Árbol ancestral y árbol corazón = MapleTree. Pasto del pack nuevo NO usado (memoria).
- Clima/lluvia (weather.gd, SoundBank.rain) escrito pero DESACTIVADO en main.gd (memoria).
- Personaje nuevo: castaway_model.gd + castaway_pose.gd (glb Quaternius). Ctrl = agacharse; gestos recoger/comer/beber/cortar. castaway_rig.gd borrado. Escena de prueba: scenes/test_character.tscn.
- Pendiente: probar el personaje caminando, medir fps/memoria, vestimenta, memoria de biomas -> acciones de la isla, convivencia pasos 2-5.


## Sesión: bloques 2 y 3 (hechos)
- Bloque 2: fogata con quads suaves, flores ámbar, luna/agua nocturnas, luciérnaga activa.
- Bloque 3: flora/viento según ánimo de la isla (`Wind.set_mood/get_mood`); claros misteriosos con anillo pisado y huellas (`scripts/island_marks.gd`, usa `Isla.calor_paso/calor_dano`); flores nocturnas con `shaders/glow_flower.gdshader` que se inclinan hacia/lejos del jugador. SIN daño al pisar (pedido del usuario).
- Verificado solo con cámara aérea forzada; huellas muy tenues. Flores inclinándose no vistas.
- Se borró la línea TEMPTEST de hora fija 14:00 en main.gd.
- Pendiente: bloque 4 (limpieza técnica), bloque 5 (fases 5.1-5.8).

## Bloque 4: limpieza (hecho)
- Movidos a ~/islander-fear-backup (fuera del proyecto): main.tscn, world.tscn, addons simplex_terrain/terrain_3d/lowpolyterrain/FoliageFlow, demo/, OBJ/, FBX/, FBX (Unity)/, Sound FX Starter Pack, Biolumina.flac, __MACOSX, previews.
- Se mantienen assets/ultimate_nature/glTF (usado) y addons/simplegrasstextured (una textura).
- Pendiente: revisar memoria (texturas >1K).

## Integración de kits (hecho)
- Bush_Small(+Flowers) de ultimate_nature en 25% de arbustos del matorral.
- TwistedTree_1..5 (MegaKit): selva y bordes de claros misteriosos (island_terrain.gd).
- Clover_2, Petals_4, Flower_3/4_Single en GROUND_KIT/GROUND_RULES (island_life.gd).
- RockPath_*: senderos fijos de piedras planas desde cada claro hacia el centro (island_marks.gd `_make_stone_path`).
- Verificado solo: arranca sin errores; senderos y retorcidos no inspeccionados de cerca.

## Bloque 4 cerrado: memoria
- Texturas de 2K del MegaKit (Textures/ y glTF/) con process/size_limit=1024 en su .import (24 archivos). ultimate_nature ya lo tenía.
- Sin medir RAM/fps reales; solo verificado que arranca.

## Estado al cierre de sesión
- Bloques 1-4 cerrados y subidos (84733a7). Kits integrados, memoria revisada.
- Siguiente: el usuario quiere primero planificar OBJETOS, luego BLOQUE 6 (mecánicas), y después el bloque 5. Ver DESIGN.md, "Planes nuevos guardados". Mañana: proponer ideas y organizar; el usuario elige por dónde seguir.
- Pendiente: que mire árboles retorcidos y senderos de piedras; 4 preguntas de PERSONALITY.md.


## Sesión del agua y caminos
- Agua del mar: fondo sucio, mini olas, motas; peces (sea_life.gd), ballena de día.
- Estanque verdoso con camalotes y musgo.
- Mantaraya luminosa nocturna con canto (night_manta.gd).
- Caminos de tierra en el shader del terreno (island_terrain.gd _build_paths, is_on_path); sendas chicas de náufragos anteriores.
- Pendiente: suciedad del piso, ordenar objetos en carpetas, física de objetos decorativos.


## Próximos pasos (en orden)
1. **ARTE Y LUZ ARTÍSTICA DE LA ISLA (prioridad del usuario).** Dar dirección de arte: iluminación artística, paleta, atmósfera, luces cálidas/frías, referencias en res://docs/ref/.
2. Probar caminos a pie (ancho/color).
3. Suciedad del piso: polvo, hojas, ramas caídas, vegetación seca.
4. Ordenar objetos en carpetas (usables / solo estéticos).
5. Física de objetos decorativos (después del orden).
6. Plan OBJETOS (4.5), luego BLOQUE 6, luego bloque 5.
7. Pendientes: espuma de orilla, chorro de la ballena, volumen del canto de la manta, preguntas de PERSONALITY.md, revertir pantalla completa cuando el usuario diga.


## Terreno nuevo: silueta de Sudamérica (sin commit aún)
- Referencias: docs/ref/islarefe.jpg (vista aérea exacta) e islarefe2.jpg (arte/textura/luz pintada).
- tools/make_mask.gd y tools/make_heightmap.gd generan assets/terrain/island_height.res (Image RF en metros; 1 px = 0.714 m; mapa 375x550, ±134 x ±196 m) + height_preview.png + mask_clean.png.
- island_terrain.gd: radius 160, RES 300, _hmap_h() bilineal, _base_height usa el mapa, _cliff_mask por pendiente, _random_spot rectangular. POND_CENTER (-30,-30), CAVE_CENTER (-45,30) en la cordillera oeste. EcoMap y landmarks adaptados.
- Hora fija 17:30 con línea FIXHOUR en main.gd (quitar cuando el usuario diga).
- Pendiente: pintado estilo islarefe2 (paleta, texturas, luz), ríos finos, verificar faro/barca/costa, ballena R330.


## HERRAMIENTAS DE DESARROLLO (quitar o rediseñar antes de terminar el juego)
- **Cámara del cielo** (scripts/sky_cam.gd, creada en main.gd como nodo "SkyCam"): tecla O, WASD, Space/E sube, Ctrl/Q baja, Shift rápido, rueda zoom, clic derecho mira. ANTES DE FINALIZAR: borrar esa cámara (script + las 5 líneas de main.gd que la crean) o reemplazarla por algo nuevo.
- Hora fija 17:30: línea con comentario FIXHOUR en main.gd. Quitar para volver a la hora real.
- Pantalla completa temporal (display/window/size/mode = 3): revertir cuando el usuario diga.
- Cámara de mapa M (_overview_cam en main.gd) existía de antes.
- Carpeta tools/ (make_mask.gd, make_heightmap.gd): solo para generar el terreno.
- Cambios de esta sesión: estanque que sigue el terreno (_pond_mesh), arena caribeña en el shader, playa grande/médanos/calas en el heightmap.


## Estado para retomar (caminos importantes)
- Referencia del usuario: sendero de bosque nocturno con escalones de piedra, follaje denso en bordes, luces ámbar tipo farol, luciérnagas, bruma teal (imagen en el chat; el usuario buscará más referencia o un glb).
- Plan propuesto (esperando OK): 1) caminos normales (shader) + caminos importantes (cueva, estanque, claros misteriosos) con escalones de piedra en pendiente, bordes de helechos/arbustos/flores y copa cerrada; 2) luz ámbar con flores brillantes/faroles (de noche); 3) luciérnagas y bruma concentradas; 4) variación por bioma (selva cubierta, árido abierto con piedras, costa con arena y troncos). Prueba inicial: camino a la cueva.
- Pendientes: revisar texturas triangulares del terreno (facetas en lomas, piedras grises de bordes rectos, bordes de calas), pintado estilo islarefe2, luz artística/HDRI, ríos finos, reducir senderos.
- Sin commit desde b9092d4/d91b380: faltan terreno Sudamérica, playas/médanos/calas, arena caribeña, estanque, cámara del cielo, hora fija.


## Referencias Temple Ruins (.blend)
- Movidos a docs/ref_blend/ (con .gdignore y en .gitignore: pesan 415 MB y 880 MB, GitHub no los acepta). Previews en docs/ref/temple_library_preview.png y temple_scene_preview.png. Blender 4.0.1 está en /Applications/Blender.app (se usa en modo -b con scripts python).
- Asset Library: Bridge (puente de piedra), Gate (arco, 240k polis), Stairs, Column (estela), Broken Wall, Building, Cliff, Rocks 1-6, Rubble, ferns, calathea, dry_branches, fir_sapling, tree_small_02, Ivy. Muy alto poly: hay que decimar y texturas <=1K antes de usar.
- Example Scene: terreno esculpido con ruina; no se usa directo.
- Pendiente: elegir qué piezas exportar a GLB (escalones, puente, arco, estela, muro, escombros, helechos) y confirmar licencia con el usuario.


## Caminos importantes (hecho, sin commit)
- island_terrain.gd: path_lines (trazado de caminos principales), canal B del mapa de caminos = importante; playa de llegada (125,38) conectada.
- scripts/path_decor.gd (nodo CaminosDecor, creado en island_life): lajas RockPath (escalones en pendiente, más cerca de destinos), follaje de borde por bioma (tabla _make_table), faroles ámbar con halo (de noche), luciérnagas, árboles que cierran copa. Shader: tierra rojiza oscura en caminos importantes.
- Verificado solo con capturas; fps/memoria NO medidos. Pendiente: bruma baja, más densidad, ajustar color de tierra, escalones reales en cuestas.

- Estado: el usuario NO está convencido aún de los caminos importantes (se dejan como progreso). Prueba de noche (FIXHOUR en 22:30). Después de la prueba, el usuario pedirá mejoras de luz de amanecer, mediodía, tarde y noche.

## Arte sin luz (en curso)
- Orden acordado: 1 facetas/rocas/calas, 2 estilo pintado terreno+follaje, 3 suciedad de piso, 4 ríos finos, 5 caminos importantes. Luz (HDRI, amanecer/mediodía/tarde/noche) se retoma DESPUÉS.
- Hecho 1a: normales suaves en el terreno (`_grid_normal` en island_terrain.gd), facetado solo en pendientes fuertes. Pendiente: rocas grises de bordes rectos, bordes de calas. Esperando que el usuario pruebe a pie.
- Sueltos hechos sin probar: aviso de recetas (no avisa lo que ya tenías al arrancar), huellas más duraderas (foot_fx.gd).
- Sin commit todavía.


## Pendientes de arte (esperando prueba del usuario)
- Rocas sueltas del pack (`Rock_1..5`): normales suavizadas 70 % en `nature_kit.gd` (`_soften_rocks`). Sin verificar de cerca.
- Peña de la cueva: subir resolución del mallado para redondearla (aguardando OK).
- Bordes de las calas: sin resolver; falta saber cuál cala y vista a pie.
- Estanque: orilla arreglada (`mesh_height_at`, fondo `_pond_bed`); agua se ve grande y pálida, ajustar si molesta.

- Pendiente (4.5): colisión en objetos estéticos, decidido dejarla para después.

## Bloque 4.5 paso 1 hecho (sin commit)
- `scripts/objetos/`: `catalogo_objetos.gd` (ITEMS + ZONAS), `objeto_builder.gd` (17 formas low-poly con color por vértice, una malla por id), `objetos_isla.gd` (colocador por semilla, MultiMesh por tipo, sin colisión). Enganchado en `island_life.gd` como `ObjetosDecorativos`.
- 33 piezas por vida: playa (15), paseo junto a caminos (10), orilla del estanque (8). Probado: sin errores, formas vistas en vitrina de prueba. Fps/memoria NO medidos.
- Falta: ver cómo quedan colocados de noche y a pie, más ideas del usuario, nivel B (recogibles).

## Bloque 4.5 recogibles paso 1 hecho (sin commit)
- `item_db.gd`: 10 items de uso nuevos (tela_grande, tela_chica, linterna, bateria, botella_vacia, semilla_azul [brilla + OmniLight], resina, espina, pala_concha, sal) con forma low-poly.
- `scripts/objetos/recogibles_isla.gd` (nodo RecogiblesUso en island_life): tabla REPARTO por altura y separación; 37 piezas por vida (linterna 1 cerca de la playa, bateria 8, semilla_azul 6...). Arranca sin errores; formas vistas en vitrina. NO probado: recoger en juego a pie, luz de semillas con muchas a la vez, fps.
- Falta: usos reales (linterna+baterías+batería gastada, botella con agua, semillas->plantar, telas/tienda tras frío/sueño), pistas de la isla para semillas, ofrendas y contaminantes.


## Bloque 4.5 OBJETOS: recogibles y usos (sin commit)
- `held_item.gd` (HeldItem): objeto de mano en la mano derecha + brazo levantado (`CastawayPose.hold/use_w`, `Castaway.set_hold/pulse_use/hand_transform`). **T** usa el objeto elegido.
- Linterna: SpotLight3D de mano, batería = 300 s, parpadea al final, deja `bateria_gastada` (contaminante).
- Botella: T cerca del estanque la llena (`botella_agua`); T bebe o riega un brote seco.
- `semilla_azul`: T planta (`planta_azul.gd`); regada crece 120 s y da 3 `fruto_dorado` (comida + ofrenda).
- 10 ofrendas (caracola, perla, vidrio marino, pluma, cristal, flor luminosa, moneda, figurilla [receta 2 arcilla], fruto dorado) y 5 contaminantes en `recogibles_isla.gd` (62 piezas por vida).
- Contaminante dejado en la cueva: evento `limpieza` (+vínculo); tirado fuera: `contaminacion` (leve).
- NO probado: ver de cerca la mano/linterna, regar+crecer en juego a pie, fps, entrega en cueva a pie. Pendiente: tienda/telas (con frío/sueño), pistas de la isla sobre semillas, baúl de madera en la playa (idea del usuario: ampliar inventario).

- Reparto de recogibles rehecho POR ZONA (playa 24, orilla 7, playa alta 4, caminos 12, estanque 8, cueva 7, bosque 22 = 84), objetos x1.5 y con destello visible a 40 m (antes eran de 5-15 cm tapados por el pasto y muy pocos). Pendiente: probar a pie que se encuentren; ajustar cantidades según el usuario.

- Luciérnaga guía (sin commit): de noche, siguiéndote, vuela suave (vel 1.6) sobre el recogible 'guia' más cercano a <12 m (meta `guia` puesta en `recogibles_isla.gd`: 'util' = linterna, batería, botella, semilla, tela grande, pala, contaminantes; 'ofrenda' = luz azul suave). No guía comida ni materiales de fabricación. Se quitó el destello billboard de los recogibles. NO visto en juego (hay que vínculo>=15 y noche).
- Estado de esta sesión SIN commit: objeto en mano + linterna (T), botella/semilla/planta azul, 10 ofrendas, 5 contaminantes + limpieza en cueva, reparto por zona (84), luciérnaga guía, todo lo de arte previo.
- Dev tools aún a quitar: sky cam, FIXHOUR 22:30, fullscreen temporal, tools/.

## Baúl de la playa (sin commit)
- `cofre_playa.gd` (CofrePlaya): baúl fijo a ~5 m del desembarco, de frente al mar, con grabado 'Welcome!', tapa que se abre. `main._build_chest()`.
- `cofre_ui.gd` (CofreUi): 30 celdas (6x5) + mochila, mismo estilo; clic = pasar pila, clic derecho = pasar una; E o botón cierra; el personaje queda quieto (`Castaway.ui_lock`).
- `Inventario.cofre`, `cofre_agregar`, `mover`. Mochila llena: lo recogido va solo al baúl. El baúl se vacía con la vida (como la mochila).
- `icon_render.gd`: los objetos sin PNG (todos los nuevos) ahora tienen ícono dibujando su modelo 3D (cache, se apaga tras 4 cuadros). Antes salían en blanco en la barra.
- NO probado a pie: abrir con E, clics reales, desborde automático al baúl, choque con la plancha de desembarco.


## Look y noche (sesión de arte)
- Sistema de look: LookDirector (ambiente_preset, look_haces, look_contacto, look_noche). F2 on/off, F3 overlay, F4 calidad, F5 medir.
- Noche oscura y azulada: visibilidad local (luna, copas, hondonadas, cueva, reflejo en playa). MINIMO 0.06 en look_noche.gd.
- Luna de juego (arco propio 19h-7h, fase 0.55-1), disco con manchas/cráteres, luz de luna sin haces duros.
- Agua: reflejo suave de luna, noctilucas (shader), luz y brillo de la mantaraya, mar turquesa con algas, espuma de orilla en bandas, más oleaje.
- Niebla: sin capas de bruma; niebla de altura con humedad variable por día (35%-180%).
- Pendiente: noctilucas en rompiente a pie, ajustes finos de espuma, commit de cada ajuste.


## Arte: costa, rio y ambiente (sesion posterior)
- Costa suavizada (island_terrain._smooth_shore).
- Rio fino estanque->mar: island_river.gd, river_water.gd, shaders/river_island.gdshader.
- Terreno: hojarasca/suciedad de piso y pinceladas (terrain_island.gdshader).
- Roca de la cueva con mas resolucion (seg 32, anillos 48/50).
- EcoMap: capa 8 'Densidad de follaje' (F6/F7).
- ambient_art.gd: 4 fogatas abandonadas, flores/luces ambar en la cueva y claros (max 3 luces reales cerca del jugador).
- Estanque con agua turquesa-verdosa acorde al rio.
- No hecho: bruma baja en caminos (contradice la decision de no usar capas de niebla); escalones y faroles ya existian en path_decor.gd; vegetacion de orilla del rio; revision de coherencia de assets; mas follaje por bioma (solo mapa de calor).
- Sin medir fps ni memoria.


## Follaje y ribera (sesion actual)
- Pasto por bioma (paja en arido/costa/roquedal, verde profundo en selva), capa GrassGround (9000 matas cortas), 3600 parches.
- BIOME_PLANTS: plantas medianas por bioma (~3000, MultiMesh). RIVER_PLANTS: juncos/helechos/treboles en las orillas del rio (_spawn_river_banks).
- Fogatas del mapa usan cozy_campfire.glb. Pendiente: campfire.gd (la del jugador) con ese modelo.
- No medido: fps con estas capas, de noche, a pie.


## Retoques visuales (sesión reciente)
- Roca de la cueva: menos rugosidad y más oscura.
- Estanque: agua más oscura/profunda.
- Terreno (shader): hojas caídas, barro y manchas de humus.
- Fogata única low poly con durabilidad 0-100 y apagado animado; fogatas del mapa desactivadas.
- Pendiente: caminos importantes (bruma baja, densidad, escalones), calas, espuma de cerca.

- Caminos importantes: más lajas/escalones, más follaje, bruma baja (path_decor.gd).
- Naufragio: tablas paradas, vela rota, musgo + senda de lajas hacia el árbol corazón (island_features.gd). Sin verificar a pie.
- Glow (Media+) y DOF (solo Alta, apagado por defecto) ya existían en look_director.gd; no se cambió nada.

## Arte y rendimiento (sesión reciente)
- Barco hundido (`main.gd::_build_old_ship`, estático, sin colisión, ~200 m); decorado del mar `sea_decor.gd` (corales en MultiMesh, boyas, peces).
- Barra de combustible sobre la fogata (`campfire.gd`, máx 100 min: leña 20, rama ~8, paja 3).
- Rocas de la isla = pack `stylized_stones_minipack.glb` (`NatureKit.make_stone`); emisión 0.22 para tono propio. Cueva y decoración de caminos siguen con `Rock_*`.
- Colisiones por modelo y evitar caminos, baúl persistente, plantas que se pisan y se mecen, pantalla completa (modo 3; Cmd+Enter).
- RENDIMIENTO (medido en editor, noche, playa): antes 48-54 fps, 4.8 M tri, ~5.700 draws. Causas: sombras de la luna (~2.6 M tri), árboles (~2.2 M), recogibles sueltos (~4.350 draws).
  Cambios: luna 2 cortes/70 m (`day_night.gd`), árboles visibles hasta 110 m (`TREE_VIS` en `island_terrain.gd`), recogibles ocultos a 60 m (`island_life.gd::_mesh`), agua 200x200 subdivisiones. Playa: 60 fps, ~3.400 draws, 2.7 M tri. Bosque (usuario): ~50 fps.
- Pendiente rendimiento: recogibles en MultiMesh, distancia de pasto/arbustos, medir en calidad Alta y fuera del editor.
- DEV a quitar: `fps_meter.gd` (F12) + 1 línea en `main.gd`; cámara del cielo.

## 5.7 Voz de la isla (Pasos A y B hechos, a corregir jugando)
- `scripts/island_phrases.gd`: 200 frases nuevas `[voz, tema, texto]` (curiosa 45, seria 35, confiada 45 con 15 pistas, feliz 35, contemplativa 20, clima 20 dormidas). Corregirlas es editar ese archivo.
- `island_voice.gd`: `ambient(voz, temas, solo_tema)` (prefiere tema específico, no repite hasta agotar el grupo; `s_dichas` persiste entre vidas) y `pista()` (una vez por vida).
- `island_brain.gd`: `_voz()` (seria si enojo>=35 o etapa<=1; contemplativa si sentado/zoom/quieto y calma; feliz etapa>=4; confiada etapa 3; si no curiosa), `_temas()` (hora, niebla, bioma, cueva, sentado, zoom, quieto, correr, fruto, animal, agua), `_director()` (silencio mínimo por voz: seria 45-90 s, curiosa 70-130, confiada 100-170, feliz 120-200, contemplativa 200-320; 25% de las veces calla más; sentarse = 50% de una frase; pistas cada >=240 s solo confiada/feliz, 40%). Toda frase (`_say`) reinicia el silencio. La acción "susurrar" respeta el silencio.
- Las reacciones a tala/fuego/ofrenda usan 60% frase nueva por voz. Frases viejas siguen en `POOLS`, sin reclasificar por voz.
- Pendiente: tema `pesca` sin detección; clima dormido hasta que exista; revisar frases jugando.

## Castigo del templo y calma (offense/calm)
- `scripts/templo_castigo.gd` (nodo `TemploCastigo`, grupo "templo", creado en main.gd). Templo = sacred_spots kind "heart".
- Quieto 20 s en el templo: aviso "Ya verás lo que es ofender a la isla." y 6 s para irse (si se va: +12 ofensa, sin castigo). Fuego en el templo: aviso 3 s, sin escape, castigo más largo y rencor mayor.
- Castigo: temblor + tormenta (oscuro, lluvia, rayos, trueno sintetizado) -> el personaje asciende con luz blanca hacia el bote -> `died` con `death_cause "ofensa"` (sin tumba, cartel "Ofendiste a la isla") -> -1 vida. `IslandBrain.s_rencor` hace que la próxima vida empiece con ofensa.
- Calma: item `semilla_paz` (una por vida, `Inventario.sembrar_paz()` la deja en el baúl). T en el templo: ofensa/hostilidad/rencor a 0, ofrenda +, se consume.
- Ofrendas (`interaccion._calma_ofrenda`): la del bioma baja ofensa 10, otra 4, y 1.5 si la isla está furiosa (>70).
- NO probado en vivo: tiempos reales, fuego en el templo, uso de la semilla, ofrendas por bioma. Clima real queda para después.

## Clima (Weather) + reloj de la isla
- Reloj: 2 h reales = 24 h de juego (`DayNight.TIME_SCALE = 12`), fecha fija (equinoccio), fase lunar real. F9 = +1 hora de juego.
- `weather.gd` reescrito: estados SOL, NUBLANDO, LLOVIZNA, LLUVIA, TORMENTA, CLAREANDO, PAZ. Se anuncia: nubes (`DayNight.cloud` -> LookDirector baja sol/cielo/saturación), niebla (`fog_clima`), viento (`Wind.set_clima`); la lluvia solo arranca con cielo cerrado.
- La isla decide tras el sol (emociones + hostilidad): sol en paz / lluvia / llovizna / tormenta. Frases "lluvia"/"tormenta" ya activas.
- Lluvia tranquila: baja la ofensa muy despacio y hace rebrotar árboles talados (`IslandTerrain.felled` / `regrow_tree`, ~1 cada 30 s). Fin de tormenta: 6–10 charcos que se secan solos. Sin flores arrancables.
- Sonido de lluvia al 40 % de noche. Truenos solo en tormenta.
- Panel de pruebas `clima_panel.gd`: botón "Clima (K)" o tecla K: forzar estados, hora +1, charcos, rebrote, interruptor "Clima activo".
- Gancho: `Weather.wetness` (personaje mojado), sin uso. Probado: tormenta forzada visible, rebrote de árbol por script, panel. NO probado: ciclo automático completo, charcos a la vista, sonido, fps en bosque bajo lluvia.

## Ajuste a reloj 12x: fuego, hambre y sed
- Fuego: `MAX_FUEL` 1200 s (20 min reales); leña madera 240 / rama 100 / paja 36. Tecla N apaga la fogata cercana (quedan brasas) para guardar recursos.
- Hambre/sed: `hunger_decay` 0.037 (~45 min reales), `thirst_decay` 0.06 (~28 min). Multiplicador por actividad: correr x1.8, cortar/recoger x1.5 (6 s), sentado x0.5; x1.25 si una necesidad está en 0.
- Quitado el medidor de fps (`fps_meter.gd` queda en disco sin uso). Sin cambios: canto, estudio de la isla, clima.

## Vela, sombras y arranque de pruebas
- Vela: botavara alta (SAIL_FOOT 2.3) y girada (SAIL_YAW), tela suelta con ráfagas y ondas (sail.gdshader). Ya no atraviesa al jugador.
- Sombras del sol: filtro soft high, shadow_blur 2.5, distancia 100 m.
- Humor de la isla más lento (caminata aleatoria 0.03).
- Arranque de pruebas (TEMPORAL): reloj a las 6:00 (START_HOUR) y vínculo mínimo 30 (VINCULO_INICIO). Quitar antes de publicar.

## Bosque en arboledas y claros + palmera nueva
- Árboles: tope 250; el ruido de manchas separa claros (casi sin árboles) de arboledas densas; separación 3.4 m en bordes, 2.3 m en el centro.
- Palmeras de costa: modelo assets/terrain/stylized_palm_tree_1k_pbr.glb (3 troncos, ~23k tris, escalado a ~7 m), colisión radio 0.45. Sin medir fps aún.
- Pendiente: rodales por especie y bordes graduales.

## Rodales, bordes y palmerales
- Especie por ruido de rodales (_stand_value, ~55 m): selva torcidos/grandes/juntos, bosque manchas de abedul y arce, matorral bajos y sueltos. 5 % fuera de rodal.
- Bordes: árboles más chicos y espaciados en transición claro/arboleda y entre biomas; troncos caídos y arbustos marcan el límite (_add_edge_markers).
- Palmeras en grupos de 2-3 modelos, solo en tramos de costa (ruido), inclinadas hacia el agua (_water_dir). Sin medir fps.

## Colision de piedras de sendero y vuelo de pajaros
- NatureKit.add_box_colliders/add_box_collider: caja por piedra de sendero (RockPath, Rock_) en path_decor, island_features (senda naufragio) e island_marks.
- bird.gd: posadas dentro de la copa, huyen si talan el arbol, estado ROAM (vuelo libre 3-5 puntos), gaviotas con orbita que deriva.
- Pendiente: mariposas e insectos; guijarros (Pebble) siguen sin colision.

## Sesion arte (look del dia/noche) - EN AJUSTE
- Shader hojas wind_leaf: oscurece, desatura, autosombra por altura, sin specular. Haces: look_haz.gdshader tenia error de sintaxis (rectangulos), corregido.
- Cielo/niebla dia y noche retocados en ambiente_preset.gd; noche aprobada por el usuario. Luna 1.0.
- Dia NO convence: amarillento/fluor en pastos y flores. Ultimo ajuste: sat 0.92, contraste 1.05, sol 0.9. Revisar color propio del pasto/flores y terreno.
- Troncos: tono calido (0.8,0.76,0.68) en nature_kit._bark_tone.
- Calidad Alta (F4) da look fluor: usar Media (look.cfg calidad=1). Evitar F4.

## PRESET DE LUZ GUARDADO: look-v1 (dia y noche) - usuario conforme
- Cielo con nubes procedurales (sky_daynight.gdshader: cloud_cover 0.42, cloud_soft 0.22, cloud_speed 0.006). Ventana 1600x900 (modo ventana).
- Dia: ambiente_preset.gd dia() sat 0.92, contraste 1.05, sol 0.9. Noche aprobada. Calidad Media (look.cfg calidad=1).
- Para volver a este punto: git checkout look-v1 -- scripts/look shaders scripts/day_night.gd scripts/weather.gd
- Proximos pasos: separar clima del color del mundo (nub), sol suave/brillante segun humedad, mas bruma de noche, pasto/flores fluor.

## Preset look-v2 (cielo con nubes, clima separado del color, rayos variados dorados, mas bruma de noche) - usuario conforme
- look_director: hum_n por fecha, sol suave/brillante, rayos segun humedad, clima menos gris. look_haz: boost/warm por haz.
- Siguiente: sol +, particulas, suciedad en suelo, troncos humedos (volver con git checkout look-v2 si no gusta).

## Preset look-v3 (dia) 
- Dia: sol 1.3 dorado (1.0,0.86,0.6), niebla 0.0009, nubes minimas 0.15, saturacion 1.08, sombras frias, hojas a contraluz, polvo brillante, sombras definidas (shadow_blur 0.55), mancha bajo el personaje, destello de lente (look_destello.gd), rocas grises calidas, particulas suaves, suciedad del suelo del bosque, troncos oscuros.
- Restaurar: git checkout look-v3 -- .
