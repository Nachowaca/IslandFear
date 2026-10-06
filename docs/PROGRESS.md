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

## Decisión pendiente: el fin del jugador (retomar mañana)
Dos direcciones, combinables; el usuario elige el eje:
1. **Sobrevivir:** hambre, sed, frío/temperatura, fogata, refugio, qué restaura salud (frutos, cocos, raíces, hierbas, agua dulce, descansar en la cueva de día). El jugador intenta durar; las acciones de la isla (niebla, tormenta, criaturas) ponen la presión. Requiere: interacción (E), inventario, medidores.
2. **Desarrollar sus acciones:** cortar árboles, cazar, hacer fuego, ofrendar, construir. Activa los eventos que `Isla` ya espera (`arbol_cortado`, `fuego`, `animal_cazado`, `ofrenda`, `cuidado`) y vuelve más rico el perfil del final (destructor / cuidador). Hoy esos eventos no tienen fuente en el juego.
Después de elegir: armar plan de jugabilidad y acciones del personaje. Aún sin implementar: acciones de isla `tormenta`, `criatura`, `regalo`. Pulido pendiente: diseño del personaje (al usuario no le gusta del todo).

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
