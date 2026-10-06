# Islander Fear — Diseño

> Documento de diseño vivo. Leer junto con `PROGRESS.md` al empezar cada sesión.

## Concepto
Juego 3D low-poly de supervivencia (Godot 4.7, Forward+, Mac M1/Metal). Un náufrago (pelo largo, barba, túnica blanca rota) llega en una barca arrastrada por la corriente a una isla **viva**, con un "cerebro" que piensa, lo estudia y no lo quiere ahí.
La isla es un NPC más: tiene carácter, memoria y voz. **Primero es misterio; nunca ataca porque sí, solo si el jugador le hace mal.**

## Preferencias del usuario
- Habla español rioplatense (Montevideo, Uruguay). Quiere respuestas CORTAS, sin explicaciones largas.
- Trabaja paso a paso ("vamos por partes"): primero diseño, después jugabilidad.
- Arte: low-poly, solo primitivas, sin modelos con esqueleto. Pixel art NO.
- La isla NO tiene voz hablada (solo texto).
- Sonidos 100 % sintetizados por código ("por ahora usaremos esos sonidos").
- El reloj en pantalla es TEMPORAL (el usuario lo va a sacar).
- No agregar jugabilidad que no pidió.

## Mundo
- Isla de radio 60 m con laguna, meseta con cueva, flora, rocas, playa. Faro fuera de la isla en (-20, 0, -105).
- Elementos: cueva (puerta ~3 m, sello y cristales), piedras erguidas, árbol gigante, naufragio, mojones (cairns), círculos de hongos brillantes. Estos son `sacred_spots` (lugares sagrados).
- Día/noche en TIEMPO REAL con astronomía real (reloj del sistema, lat -34.9011 / lon -56.1645): sol, luna con fase, estrellas, brillo de luna en el agua.
- Faro: rota cada 30 s, luz con sombras, rebote falso con luces omni, apagado de día.
- Viento en follaje (shader), partículas ambientales, partículas de pasos.
- Agua con shader y mapa de altura del terreno (espuma en la costa).

## Barca y llegada
- Barca de tablas con cubierta, bancos, remo, cajón, rollo de cuerda, mástil, vela triangular con shader (se hincha y aletea), banderín.
- Llega sola, queda varada y quieta, baja una plancha de desembarco con rebote; recién entonces se habilita el control.
- El sonido de la isla sube de menos a más al acercarse (olas, viento, grillos, pájaros). Navegando se oyen crujidos de madera.

## Jugador (Castaway)
- CharacterBody3D con animación procedural. Controles: WASD (X retroceder), Shift correr, Espacio saltar, mouse cámara, Tab/M vista aérea, I panel de mente de la isla, Esc suelta mouse, F8 silencio, F9 +1 h, F10 mirar la luna, F11 pantalla completa.
- Sube escalones bajos (~40 cm) automáticamente.
- Salud con regeneración (más rápida en el refugio = cueva de día). `take_damage`, `heal`, `apply_slow`, `add_shake`.
- HUD de salud: corazón generado, marco azul, relleno rojo, rastro de daño, número y etiqueta "Refugio"; abajo a la izquierda, escala 0.85. Opción `segmented`.

## El cerebro de la isla (`island_brain.gd`) — IA procedural LOCAL (no es un LLM)
### Principios
1. **Misterio primero.** Estudia al jugador entre 2 y 3 "días" (1 día = `day_length_seconds` = 300 s de juego). Durante ese tiempo solo presagios, nunca daño.
2. **Nunca ataca por sí sola.** Solo el mal que le hacés sube sus *agravios* (`offense`): molestar animales, quedarse en lugares sagrados, tomar frutos (apenas). Estar quieto, ir a la cueva o caminar de noche NO la enoja.
3. **Avisa antes de castigar** (una advertencia por episodio).
4. **Perdona**: los agravios bajan solos (más rápido los chicos), con altibajos por humor.
5. **No lineal / impredecible**: hostilidad = 100·(1−e^(−offense/22)); humor `_noise` como caminata aleatoria; curiosidad que sube con lugares nuevos; cada partida nace con `_forgive` y `_sens` distintos; tiempos de pensamiento y enfriamientos de cola larga (log-normal); a veces calla.
6. **Estudia cada movimiento**: distancia, tiempo quieto, corriendo, en cueva/playa/bosque, de noche, en sitios sagrados, cerca de animales, frutos tomados, giros bruscos (dudas), regresos sobre sus pasos, primeras veces (cueva, correr, noche). Guarda la ruta (cada 0,4 s, 600 muestras).
7. **Veredicto** al terminar el estudio: el rasgo dominante (`_grievance`: animals / sacred / taken / cave / still / restless / calm) decide cómo castigaría SI hay agravios. Solo animals/sacred/taken producen un veredicto amenazante; el resto solo se anota.
8. **Memoria entre muertes** (`static`): intentos/aciertos por ataque, mapa de calor, puntería (`s_lead`), muertes, veredicto. Tras morir, el estudio es corto (0.3–0.8 días).

### Acciones
- Presagios (sin daño): `whisper` (comenta lo que hacés), `tremor`, `scare_birds`, `eyes` (noche), `echo` (una luz repite un tramo de tu propio recorrido), `footsteps` (pasos detrás tuyo), `wisp` (luz lejana que se aleja, de noche).
- Daño (solo con agravios y tras el estudio): `rockfall`, `thorns`, `crab_rush` (venganza si el veredicto es animals), `cave_trap` (de noche, si estás en la cueva).
- Reglas: la cueva protege de día (no puede atacar adentro), es trampa de noche. Cada acción cuesta energía y tiene enfriamiento.

### Voz (`island_voice.gd`)
- Más de 45 grupos de frases con plantillas `{who}`, `{place}`, `{n}`; evita repetir las últimas 16; aperturas y remates según tono (curioso / seco / cruel).
- Te llama distinto según lo que vio de vos (cazador, ladrón, ermitaño, durmiente, caminante, profanador…).
- `riddle()` genera frases crípticas combinando sujeto + verbo + objeto (concordancia en plural).

## Audio (todo sintetizado por código)
- `sound_bank.gd` sintetiza; `audio_manager.gd` mezcla camas (olas, viento, hojas, grillos, zumbido), eventos (pájaros, búho, ranas, crujidos), pasos por superficie (arena, pasto, agua, piedra, madera), filtro y reverb en la cueva. `AudioManager.play(tree, id, pos, db)` para eventos 3D.
- IDs: step_sand/grass/water/stone/wood, bird, gull, owl, frog, pad, creak, crack, drip, heart, boom, rumble.

## Decisiones técnicas
- Evitar SDFGI, niebla volumétrica y shaders con depth texture: crashean Godot (Metal abort) en la Mac del usuario. El rebote de luz es falso con luces omni.
- No sobrescribir con `create_file` escenas abiertas en el editor (conflictos, scripts embebidos). Usar `edit_file`.
- Escena principal: `res://scenes/game.tscn`. `main.tscn` y `world.tscn` son copias rotas que el editor recrea con pestañas de script viejas abiertas; borrarlas.
- El nodo `Boat` en game.tscn NO debe tener `script = null` (anula `boat.gd`).

## Planeado (no hecho)
1. Sistema de interacción (E), inventario, comer/beber, medidores de hambre, sed y temperatura.
2. Qué restaura salud: frutos, cocos, raíces, hierbas medicinales, agua dulce, descansar en la cueva de día, fogata, refugio construido. (En discusión con el usuario; nada implementado.)
3. Clima controlado por el cerebro de la isla.
4. Sacar el reloj temporal.
5. Ajustar a oído: pasos fantasma, luz lejana, volumen general del audio.
