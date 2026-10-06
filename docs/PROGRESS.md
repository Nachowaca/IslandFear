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
