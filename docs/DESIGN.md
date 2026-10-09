# Islander Fear — Diseño

> Documento de diseño vivo. Leer junto con `PROGRESS.md` al empezar cada sesión.

## Concepto
Juego 3D low-poly de supervivencia (Godot 4.7, renderer Mobile, Mac M1/Metal). Un náufrago (pelo largo, barba, túnica blanca rota) llega en una barca arrastrada por la corriente a una isla **viva**, con un "cerebro" que piensa, lo estudia y no lo quiere ahí.
La isla es un NPC más: tiene carácter, memoria y voz. **Primero es misterio; nunca ataca porque sí, solo si el jugador le hace mal.**

## Historia y final (definido por el usuario)
- El jugador tiene **7 vidas**. Cada muerte es una vida; la isla recuerda y cambia su personalidad según cómo jugó esa vida (destructivo → desconfiada, cuidadoso → abierta).
- **Final:** tras la vida 7, la isla calcula un final según el acumulado (convivir o no) y **el jugador se convierte en la isla**. Después el ciclo se reinicia, distinto en cada juego.
- Hoja de ruta de la IA (3 prompts del usuario, cada uno: proponer enfoque y esperar OK antes de escribir código):
  1. Memoria + emociones: contadores (árboles cortados, fuegos, animales cazados, ofrendas, tiempo corriendo/explorando), mapa de calor de zonas (dónde pasa / dónde rompe), emociones 0..1 (confianza, enojo, miedo, curiosidad) con valor base y decaimiento, `registrar_evento(tipo, zona)`, señal `emocion_cambiada`.
  2. Decisión: catálogo de acciones como Resources (niebla, tormenta, sonidos, mover_vegetacion, criatura, regalo, nada) con cooldown; puntúa cada 1–2 s según emociones + contexto; azar ponderado; "nada" también puntúa; por ahora solo imprime puntajes.
  3. Acciones reales + 7 vidas: niebla (WorldEnvironment), sonido 3D ambiente, mover vegetación; guardar personalidad al morir (Resource/JSON) y cargarla en la vida siguiente; final en la vida 7.
- Sin LLM, solo variables.
- Decisión implementada (enfoque A): catálogo de `AccionIsla` (.tres), puntaje = base + emociones×pesos + contexto×pesos, azar ponderado, "nada" compite, hueco de silencio de cola larga tras cada acción. Si no gusta cómo se siente, anotar acá el enfoque B y comparar.

## Reglas de la isla (definidas por el usuario, mandan sobre todo lo demás)
- La isla **evoluciona y cambia; no ataca porque sí**. El juego trata de **convivir, no de lastimarse**: la isla aprende del jugador y el jugador de la isla.
- El jugador **no ve** la relación (sin barra ni ícono): la isla **advierte con el escenario** (cueva que se calienta o se enfría, pájaros o silencio hostil, niebla, frases).
- Los ataques **hieren o intentan herir, no matan** (`Castaway.island_floor`: el golpe de la isla deja ≥ 8 de salud) y **pasan días** entre uno y otro (`_attack_rest` = 1–3 días de juego, menos si está muy enojada). Antes siempre hay presagio y aviso.
- Los agravios del cerebro (`offense`) siguen **en paralelo** con las emociones de `Isla` (decisión del usuario).
- **Vínculo** (`Isla.vinculo`, −100…+100, guardado en disco, a la mitad al morir, a 0 en cada ciclo nuevo): etapas Hostil < −40 < Desconfiada < −10 < Extraña < 15 < Tolerante < 45 < Aceptante < 75 < Aliada. Sube: ofrenda +7, cuidado +1, explorar +0.2, y paz (90 s sin ofensas: +0.02/s hasta tope 40; sana heridas viejas). Baja: talar −8, cazar −12, fuego −3, molestar animales −0.6, tomar fruta −0.15, lugar sagrado −0.5/s. Efectos: Aceptante/Aliada **nunca atacan**; Tolerante solo reacciona a ofensas graves (agravios ≥ 35); tono de frases según etapa; cueva dorada con confianza; más pájaros con confianza y silencio hostil sin ella; frases al cambiar de etapa.
- Hoja de ruta de convivencia (pendiente): regalos reales cuando confía y el jugador sufre, silencios con significado, noche/tormenta/criaturas en escalera (presagio → aviso → golpe, con tregua por ofrenda), y que la convivencia alimente el final.

## Preferencias del usuario
- Habla español rioplatense (Montevideo, Uruguay). Quiere respuestas CORTAS, sin explicaciones largas.
- Trabaja paso a paso ("vamos por partes"): primero diseño, después jugabilidad.
- Arte: low-poly, solo primitivas, sin modelos con esqueleto. Pixel art NO.
- La isla NO tiene voz hablada (solo texto).
- Sonidos 100 % sintetizados por código ("por ahora usaremos esos sonidos").
- No hay reloj en la isla: el tiempo se muestra solo con el medallón de fases sol/luna (arriba a la izquierda). Nada de horas en pantalla.
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
- CharacterBody3D con animación procedural. Controles: WASD (X retroceder), Shift correr, Espacio saltar, mouse cámara, Tab/M vista aérea, I panel de mente de la isla, Esc suelta mouse, F8 silencio, F9 +1 h, F10 mirar la luna. (F11 no funcionó: el juego arranca en pantalla completa por configuración del proyecto.) Controles actuales: T usar objeto en mano, Q cortar, V sentarse, Z zoom, E baúl/recoger/dormir, I mente de la isla, F investigar, N apagar fogata, K clima (dev), O cámara del cielo (dev), G comer crudo, C armar.
- Sube escalones bajos (~40 cm) automáticamente.
- Salud con regeneración (más rápida en el refugio = cueva de día). `take_damage`, `heal`, `apply_slow`, `add_shake`.
- HUD (estética naufragio pirata): abajo a la izquierda, apilado: hambre y sed (íconos pintados) sobre la barra de vida con 7 gemas de vidas; marcos de madera con latón y muescas de cuerda; rótulo "Refugio" bajo la barra. Arriba a la izquierda, medallón de fases.

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

## Fase 2: supervivencia y acciones (en curso)
- Pilares pedidos por el usuario: inventario; guardar, investigar (info de lo que se ve), cortar (con piedra filosa u objeto cortante), dejar, probar (fruta, vegetal, animal crudo) y unir objetos (fuego, herramientas). Los objetos nuevos que interactúan con el jugador deben ser conocidos por la isla (`Isla.registrar_evento`).
- Controles: E recoger/beber/echar leña, G dejar, F investigar, R probar/comer, Q cortar, C combinar, 1-0/rueda elegir; vista aérea en M.
- Cadena de herramientas: piedra+piedra → cuchilla (lianas, hojas) → cuchilla+rama → hacha (talar) · lianas u hojas → cuerda → lanza. Fuego: 2 piedras + paja/leña. Comida con valores realistas (fracción de la barra de hambre/sed).
- La isla reacciona: ofrenda en lugar sagrado = confianza; investigar = curiosidad; talar/fuego/cazar = enojo/miedo (cuando existan).
- Usuario autorizó usar assets gratis (pack Stylized Nature MEGAKIT en `res://glTF`) para mejorar flora, objetos, misterios, cuevas y animales pequeños.

## Planeado (no hecho)
1. Sistema de interacción (E), inventario, comer/beber, medidores de hambre, sed y temperatura.
2. Qué restaura salud: frutos, cocos, raíces, hierbas medicinales, agua dulce, descansar en la cueva de día, fogata, refugio construido. (En discusión con el usuario; nada implementado.)
3. Clima controlado por el cerebro de la isla.
4. Sacar el reloj temporal.
5. Ajustar a oído: pasos fantasma, luz lejana, volumen general del audio.


## EcoMap: la isla como ecosistema por capas (biomas)

**Idea:** vegetación, rocas y suelo se reparten por reglas naturales (coherencia geológica), con ~5-10 % de zonas misteriosas. Todo determinista a partir de una semilla; parámetros en el Resource `EcoParams`.

**Capas (cada una se calcula una vez sobre una grilla de 2 m y se consulta rápido):**
1. Altura, pendiente y distancia a la costa: `get_altura`, `get_pendiente`, `get_dist_costa`, `is_tierra`.
2. Agua: distancia al agua más cercana (mar o laguna): `get_dist_agua`. Sin arroyos por ahora.
3. Humedad 0..1: cerca del agua, valles, poca altura y poca pendiente, más ruido: `get_humedad`.
4. Suelo: arena, roca, tierra fértil, tierra seca: `get_suelo`.
5. Bioma: costa, roquedal, selva, bosque, matorral, zona árida: `get_bioma` (dominante) y `get_bioma_pesos` (transición gradual, suman 1).
6. Vegetación: los pesos de bioma deciden densidad de árboles, mezcla abedul/arce, tamaño (selva más grande), arbustos, rocas sueltas (roquedal), y flores/pasto/helechos (matorral, claros del bosque, sotobosque de selva). Separación mínima de 2,6 m entre árboles. Palmeras, troncos secos de playa y derrumbe de acantilados mantienen sus reglas. El EcoMap REEMPLAZA las reglas viejas de plantado; lo crea `IslandTerrain.eco`.
7. Zonas misteriosas: 6 claros (~6 % de la tierra), semilla propia, mínimo 40 m entre centros: `get_misterio`. Dentro: casi sin árboles, más rocas y flores.

**Depuración:** F6 muestra/oculta el overlay, F7 cambia de capa (7 capas).

**Isla viva:** gancho `set_mood(humedad_delta, cierre, niebla)` preparado, todavía sin efecto.

**La isla aprende del bioma:** `Isla` guarda tiempo y eventos por bioma (`bioma_tiempo`, `bioma_eventos`, persisten), `bioma_favorito()` y `eventos_en_bioma()`. El cerebro suma tiempo cada frame y a veces comenta el bioma donde más vivís (frases `obs_bioma_*`).

**Próximo (sin implementar):** que esa memoria cambie lo que la isla hace y dice: avisos con el paisaje del bioma, acciones en lugares ecológicamente coherentes, regalos de convivencia. Los claros misteriosos podrían tener luz o niebla propia. Reglas: la isla sigue sin atacar salvo daño del jugador y el vínculo sigue oculto.

## Cueva = pozo con luces (rediseño)
La cueva de rocas se quitó. Ahora es un POZO excavado en el terreno (`IslandTerrain._pit_carve`: radio 5,5 m, 5 m de profundidad) con una rampa en trinchera hacia el centro de la isla. Adentro: cristales y 14 luces flotantes que se mueven, motas de luz y una luz ambiente; el color sigue siendo el del vínculo (turquesa, dorado si confía, rojo si es trampa). Refugio de día; de noche la isla sella la rampa con una roca (`seal_cave`). El resto de la lógica (cerebro, audio, trampa) no cambió.

## Vegetación: solo pack Quaternius
Árboles (NormalTree, PineTree, Birch, Maple, DeadTree, Palm), arbustos y rocas salen solo del pack nuevo. Quedan del MegaKit: pasto, helechos, tréboles y plantas del suelo.

## Cueva más profunda, lluvia y plantas nuevas
Pozo de 8 m con paredes y techo de rocas del pack Quaternius. `Weather` (weather.gd): lluvia ocasional (ciclo de 2-5 min sin lluvia, 1-2 min con lluvia) con gotas y sonido sintetizado; dentro de la cueva (`is_inside_cave`) no cae y el sonido baja. Pasto, pétalos y plantas del suelo ahora son `UQ:` del pack nuevo (ya no queda MegaKit en la vegetación).

**Pospuesto por memoria (decisión del usuario):** pasto del pack nuevo, luces extra de la cueva y clima/lluvia. `weather.gd` y `SoundBank.rain` quedan escritos pero `Weather` no se agrega en main.gd.

## Personaje nuevo (Quaternius CC0)
Modelo `res://assets/character/quaternius_cc0-male-character-1352.glb` (7.9k tris, 42 huesos, 6 materiales: piel, ojos, pelo, remera, pantalón, medias → fácil de cambiar la ropa). `castaway_model.gd` (CastawayModel) maneja las animaciones del archivo: Idle, Walk, Run, Jump, RunningJump, Death y SwordSlash (tajo al cortar, tecla Q). `castaway_pose.gd` (SkeletonModifier3D) suma poses por código: agacharse (Ctrl, 45% de velocidad, sin saltar), recoger, comer y beber (`Castaway.play_action`). Reemplaza al rig procedural viejo (castaway_rig.gd, borrado). No hay cara animada (`express()` queda vacío) ni nadar (no se puede entrar al mar profundo). Escena de prueba: `res://scenes/test_character.tscn`.

Árbol ancestral (island_features) y árbol corazón (island_life) ahora son MapleTree del pack nuevo (escala 2.4 y 1.5). Se eliminó la copa de esferas y el TwistedTree: ya no quedan árboles del MegaKit.

Luciérnaga de la isla (firefly.gd): regalo nocturno. Si el vínculo >= 15 (se va < 8) y es de noche, acompaña al jugador y lo alumbra; de día vuelve a su escondite (junto a un árbol). Sin avisos. Solo acompaña, no guía. Luna más fuerte (1.5, mínimo 0.3).


## Ideas guardadas para después (plan de mejoras de la isla)
Orden acordado: 1) pulir lo hecho, 2) isla viva, 3) isla que te estudia, 4) orden técnico.

**1. Pulir (en curso):** ajustar rocas oscuras, colores de bioma y troncos tras probar caminando; cueva con piso de piedra, recorrerla y probar el sello de noche; revisar de cerca plantas en grupos, pájaros y mariposas.

**2. Isla viva (después):**
- Viento visible: ramas y pasto se mueven más en lomas y menos en bosque cerrado.
- Flores y bayas comestibles según el bioma (`get_bioma_pesos`), hoy no lo usan (`island_life.gd`).
- Flores que brillan de noche (15-20% de las flores, emisión turquesa/violeta pulsante, sin luces reales), sobre todo en claros misteriosos; usar `res://Biolumina.flac`.
- **Mejorar la fogata (`campfire.gd`):** hoy emite una luz muy geométrica (círculo naranja duro sobre el suelo, halo plano, humo en bolas blancas facetadas). Debe ser ambiental: colores cálidos difuminados que se funden con el entorno, sin borde visible de la luz (atenuación suave, tinte cálido que cae gradualmente y tiñe pasto y árboles cercanos), parpadeo orgánico, humo suave y translúcido en vez de bolas blancas. El usuario traerá referencias de cómo se lo imagina; esperarlas antes de implementar.
- Referencia de ambiente nocturno (cálido/frío, teal + ámbar): A paleta de noche y B fogata hechos; pendientes C agua teal con reflejos cálidos, D flores nocturnas en ámbar, bajar la luz de luna sobre la arena.
- Luciérnagas (`firefly.gd`, desactivada) y clima/lluvia (`weather.gd`, desactivado): al final, vigilando la memoria.

**3. Isla que te estudia (después):**
- Pasto, flores y claros reaccionan sutilmente al vínculo (más apagado si hostil, más vivo si confía; el shader del terreno ya tiene `mood`), sin que el jugador vea la relación.
- Huellas y marcas de la isla en los claros misteriosos.

**5. Jugabilidad e interacción (nuevo, la lista de ideas se arma después con el usuario):**
- Mejorar la interacción con los objetos de la isla (más acciones sobre piedras, plantas, agua, árboles, cueva, ruinas).
- Mejorar el sistema de ofrendas y ofensas a la isla (más formas de ofrecer y de ofender, respuestas más variadas; el vínculo sigue oculto y los ataques nunca matan).
- Agua: si el náufrago se sumerge mucho tiempo, pierde vida de a poco (aguantar la respiración o nadar demasiado agota).
- Principio: libertad total; más mecánicas para interactuar con toda la isla, sin guiar al jugador. Mantener la regla de convivir y no herirse.
- **Ecología con sentido:** todo objeto de la isla existe por un porqué ligado a su bioma y su medioambiente. Para convivir hay que **mantener ese medioambiente**, no solo sobrevivir (ej.: talar sin replantar, arrancar la planta de un claro, ensuciar el agua o encender fuego en la selva húmeda dañan el equilibrio de esa zona; cuidar, replantar y devolver sí lo sostienen). Cada zona tendría su "salud" (EcoMap), que la isla percibe.
- **Huellas de otros náufragos:** más objetos aleatorios dejados por jugadores anteriores (mochilas, cartas, herramientas rotas, campamentos viejos, marcas en troncos), con historias sueltas, repartidos por biomas.
- **Fuego:** da calor (frío de noche, mojado, cueva) y a futuro se podrá cocinar. Hoy solo ilumina.
- **Frases de la isla:** sumar ~200 frases nuevas (texto, la isla no tiene voz hablada) que reaccionen a las acciones y movimientos del jugador (dónde camina, qué recoge, qué corta, fuego, agua, ofrendas, ofensas, quedarse quieto, correr, noche, cueva). Se escriben por categorías para `island_voice.gd`.
- Ideas sumadas por mí (a confirmar): clima del cuerpo (frío/calor, mojado, secarse junto al fuego); semillas y replantar árboles; cosechar sin arrancar (solo frutos); ofrendas con sentido por bioma (flor al claro, piedra al roquedal, agua a la selva); ofensas graduales (pisar flores raras, ensuciar el estanque); refugio y camas con hojas; pescar y cocinar; marcar caminos con piedras sin dañar; sentarse a observar y que la fauna se acerque; escuchar la isla (sonido cambia con la salud de la zona).
- Hecho de paso (menú C): selección con flechas/rueda/trackpad, espera con círculo al fabricar y aviso al juntar materiales.

**Plan de ejecución del bloque 5 (fases, una por vez, probada antes de seguir):**
- **5.1 Salud de zonas (base de todo):** `EcoMap` guarda una "salud" por celda/bioma (`Isla.registrar_evento` ya acumula `bioma_eventos`). Talar sin replantar, arrancar plantas, ensuciar agua y fuego en zona húmeda la bajan; replantar, ofrendas y cuidado la suben. Efecto sutil y oculto (pasto/flores más apagados en el shader con `mood` por zona, fauna menos, sonido). Sin indicadores.
- **5.2 Semillas y replantar + cosechar sin arrancar:** frutos se toman sin dañar la planta (rebrotan); al talar se obtienen semillas/brotes que se plantan (`_plant` en `interaccion.gd`) y crecen por etapas. Sube la salud de la zona.
- **5.3 Fuego, calor y cocina:** `Campfire` ya existe; agregar temperatura corporal (frío de noche, mojado, cueva) en `castaway.gd` y calor cerca del fuego; luego cocinar (receta nueva en `recipes.gd`: comida cruda -> cocida, y pescado). El fuego en selva/bosque húmedo ofende un poco, en costa/claro no.
- **5.4 Agua:** nado/inmersión larga baja vida de a poco (aliento); salir del agua moja (alimenta 5.3). Ensuciar el estanque es una ofensa leve.
- **5.5 Ofrendas y ofensas con sentido:** ofrenda por bioma (flor al claro, piedra al roquedal, agua a la selva) vale más que una genérica; ofensas graduales (pisar flores raras, cortar en sagrado, ensuciar agua). Todo pasa por `registrar_evento` con el bioma; nunca mata.
- **5.6 Huellas de otros náufragos:** nuevo `island_traces.gd` (o dentro de `island_features.gd`): campamentos viejos, mochilas, cartas, herramientas rotas, marcas en troncos, repartidos por bioma con semilla fija; inspeccionar (F) da texto corto. Cargas livianas (pocas mallas, MultiMesh/kit).
- **5.7 200 frases de la isla:** ampliar `POOLS` de `island_voice.gd` por categorías (caminar por bioma, quedarse quieto, correr, noche/día, recoger, talar, replantar, fuego, agua/nado, cueva, ofrenda, ofensa, objetos de otros náufragos, salud de la zona). Texto, sin voz; disparadas por eventos ya registrados y por movimiento (`sumar_paso`, tiempo quieto).
- **5.8 Extras:** refugio/cama de hojas, pescar, marcar caminos con piedras, sentarse a observar (fauna se acerca), sonido que cambia con la salud de la zona.
- Orden sugerido: 5.1 -> 5.2 -> 5.4 -> 5.3 -> 5.5 -> 5.6 -> 5.7 -> 5.8 (las frases van repartidas: se agregan las de cada fase al hacerla, y 5.7 completa hasta 200).

**4. Orden técnico (después):** (la hora fija 14:00 TEMPTEST ya se quitó); limpiar `main.tscn`/`world.tscn` y duplicados OBJ/FBX del MegaKit; actualizar PROGRESS.md; commit/push solo al cerrar la sesión.


## Planes nuevos guardados (pedido del usuario; SOLO DISEÑO, nada implementado)
Orden acordado: primero organizar el plan de OBJETOS (llamémoslo bloque 4.5 / "Objetos"), luego el BLOQUE 6 (mecánicas nuevas) y recién después el bloque 5. El usuario dirá con cuál seguir.

### Plan de objetos (a organizar con el usuario)
Categorías pedidas:
- Objetos nuevos (crafteo/uso).
- Objetos raros encontrados en la isla.
- Objetos ofrenda de la isla (la isla te da cosas; encaja con el vínculo oculto).
- Objetos de naufragios (restos de barcos en costa/fondo).
- Basura química (contaminante: la isla la odia; ver PERSONALITY.md, llevarla a la cueva).
- Residuos que llegan con la marea a la playa (cambian con la marea y el ciclo).
- Estatuas escondidas para dejar ofrendas (posible vínculo con altares/templos de PERSONALITY.md).
Por definir: lista concreta de objetos, rareza, dónde aparecen (bioma/marea/claros misteriosos), qué hace cada uno, si afectan al vínculo/salud por zona, modelos (kits disponibles o a descargar), UI de inventario.
Ideas extra a proponer mañana: diario/notas halladas, botellas con mensajes, restos de anteriores náufragos (las 7 vidas), objetos que "vuelven" tras un ciclo, ofrendas que cambian según el ciclo.

### Bloque 6: mecánicas nuevas (a organizar)
- Cuchillo en mano, hacha en mano, antorcha en mano (modelos en la mano, uso, luz de la antorcha).
- Animación de caminar con objeto en la mano.
- Sentarse a admirar algo con la isla (quieto, la isla reacciona; sube calma/vínculo oculto).
- Observar con zoom desde la visión de los ojos (zoom a lo que queramos; posible registro/diario de lo observado).
Ideas extra a proponer mañana: pescar, encender/apagar antorcha según clima, silbar/llamar, dejar ofrenda, inspeccionar objetos en mano, cámara fotográfica/diario.

Recordar: los pendientes sueltos (cueva a pie, fogata, clima, huellas, volver de pantalla completa) siguen abiertos.


### Decisión (sesión del agua): objetos decorativos con física
Dejado para más adelante: objetos decorativos de escenario (troncos, rocas, barriles, cajas, postes...) con colisión y física real. Se hará cuando todos los objetos estén ordenados en carpetas según uso (usables) o solo estéticos. Antes se hace: caminos de tierra y suciedad de piso (shader/marcas).
Hecho en esta sesión: agua del mar (fondo sucio, mini olas, motas, peces, ballena de día), estanque verdoso con camalotes y musgo, mantaraya luminosa nocturna con canto cada 10 min (scripts/sea_life.gd, scripts/night_manta.gd).


## PRÓXIMO PASO IMPORTANTE: Arte y luz artística de la isla
Prioridad alta del usuario. Objetivo: que la isla tenga una identidad visual propia y luz de autor, no solo realista.
Ideas a definir mañana con el usuario: paleta por hora del día (amanecer, mediodía, atardecer, noche teal con luces ámbar), luz cálida del sol bajo con sombras frías, rayos de luz entre árboles (falsos, sin volumétrica), luces puntuales ámbar en claros misteriosos y cueva, color grading/tonemap, contraste y saturación por bioma, niebla de color, reflejos cálidos en el agua, brillo de flores y bioluminiscencia.
Reglas: Mobile, sin SDFGI ni niebla volumétrica; referencias en res://docs/ref/. Proponer, esperar OK, un cambio a la vez.


### Recordatorio de desarrollo
Antes de finalizar el juego: borrar la cámara del cielo (sky_cam.gd) o inventar algo nuevo; quitar la hora fija FIXHOUR; revertir pantalla completa temporal.


### Bloque 4.5 OBJETOS: diseño acordado (sin implementar)
- Catálogo por datos (.tres/.json): id, categoría, modelo, escala, rareza, biomas/zonas (EcoMap), efecto, peso en el vínculo. Sumar objeto = sumar fila.
- Un solo `ObjectSpawner` por semilla de vida, por chunks (~64 m) y solo cerca del jugador.
- Tres niveles: A estético (MultiMesh, sin script ni colisión), B recogible (nodo liviano que se activa por cercanía), C especial (escena propia: ofrendas, altares, diario).
- Categorías: herramientas (se enganchan al bloque 6), útiles, estéticos inanimados, contaminantes (marea/otros náufragos; llevarlos a la cueva; suben contaminación de zona; el jugador no ve el vínculo).
- Cada vida cambia la distribución; algunos objetos solo en ciertas vidas (restos de náufragos previos).
- Decisiones del usuario: modelos de los packs que ya hay, coherentes con el estilo del juego; solo raros y ofrendas con más libertad. Cantidad inicial: estéticos ~30 en playa, paseo y cerca del estanque; ~20 recogibles; se suman ideas luego. Estéticos SIN colisión por ahora (colisión queda pendiente para después).
- Orden: 1) catálogo + colocador nivel A (~30 piezas, medir fps), 2) recogibles + contaminantes + entrega en la cueva, 3) herramientas con bloque 6, 4) ofrendas/especiales.

### Bloque 4.5 RECOGIBLES: diseño acordado (sin implementar)
- ~20 recogibles: 10 de uso + 10 de ofrenda; contaminantes aparte (5 tipos).
- USO: tela grande y chica (tienda para dormir / abrigo del frío; manta, vendaje, antorcha), linterna sin baterías, batería (8 repartidas; al gastarse queda 'batería gastada' = contaminante), botella vacía->con agua (beber y regar), semilla brillante azul (planta árbol o flor; árbol con frutos se riega con botella), resina (pega, antorcha), espina anzuelo (caña/red), pala de concha (cavar, arcilla), sal marina (cocina/conserva). Cuerda ya existe; red de pesca = varias cuerdas.
- OFRENDA (valor oculto para el jugador): concha (ya existe), caracola grande, perla, vidrio marino, pluma, cristal de la cueva, flor luminosa, moneda pirata (del cofre), figurilla de barro, fruto dorado (del árbol regado).
- CONTAMINANTES: batería gastada, lata oxidada, botella de plástico, bolsa de plástico, red enredada. Se llevan a la cueva.
- Respuestas del usuario: frío/sueño/calor NO existen aún, pero habrá (se verán después; la tienda depende de eso). Semillas brillantes azules repartidas random cada vida; la isla puede dar pistas. La linterna se esconde random cada vida, en lugares cercanos a la playa.
- Orden: 1) entradas ItemDB + colocador por zona de recogibles (usar world_item.gd), 2) linterna + baterías + ciclo batería gastada, 3) telas y tienda (tras frío/sueño), 4) botella con agua, semillas, árbol con frutos, 5) ofrendas y contaminantes.

- NOTA (usuario): la linterna servirá para ver de noche cuando la luciérnaga se va. Los objetos de mano (linterna, antorcha, cuchillo, hacha, pala, botella...) deben poder adherirse a las manos del personaje, con animaciones simples de uso (se une al bloque 6).


## Bloque 4.5: implementado (resumen de decisiones)
- **Objeto en mano:** el objeto elegido aparece en la mano derecha con el brazo levantado; **T** lo usa (gesto corto). Linterna: foco de mano independiente de la luciérnaga, batería 300 s, parpadea al final y deja batería gastada (contaminante).
- **Agua y plantas:** T llena la botella en el estanque; con agua, T bebe o riega. La semilla azul se planta con T; regada crece 120 s y da 3 frutos dorados (comida + ofrenda). Cuidar suma gesto a la isla.
- **Ofrendas (10)** y **contaminantes (5):** dejados en la cueva = evento `limpieza` (a favor); tirados fuera = `contaminacion` (leve, no ataque). El jugador no ve números.
- **Reparto por zona** (playa, orilla, playa alta, caminos, estanque, cueva, bosque), ~84 por vida, objetos x1.5, sin destello propio.
- **Luciérnaga guía:** de noche ofrece (solo a ~3 m) sutilmente útiles (luz cálida) y ofrendas (luz azul suave); no comida ni materiales de fabricación.
- **Pendiente / ideas:** baúl de madera en la playa para guardar más objetos (decidir tamaño, si la isla lo toma como propio, y si sobrevive a la muerte); tienda y telas (con frío/sueño); pistas de la isla sobre semillas; usos de herramientas (bloque 6).

## Baúl de la playa (diseño aplicado)
Baúl de madera fijo en la playa de llegada, vacío, con la inscripción 'Welcome!'. 30 celdas separadas, mismo estilo de GUI que el inventario. Lo que no entra en la mochila se guarda solo en el baúl. Pendiente a decidir: si el contenido sobrevive a la muerte, y si la isla lo toma como algo tuyo.

## Decisiones técnicas recientes (arte y rendimiento)
- Objetivo 60 fps, <1.5 GB; hoy ~50 fps en el bosque (editor). Presupuesto: sombras de la luna 2 cortes/70 m; árboles visibles hasta 110 m; recogibles hasta 60 m; agua 200x200.
- Rocas de la isla con el pack de piedras estilizadas (cueva y caminos con las viejas).
- Barco hundido y decorado del mar: estáticos, sin colisión, lejos de la costa.
- Fogata: solo la que construye el personaje; combustible máx 100 min con barra visible.
- Fauna chica (mariposas): propuesta pendiente de OK = ~20 en un MultiMesh con movimiento en shader, reemplazando las ~30 con script propio.
- Agua: el usuario la quiere como está; más suciedad/transparencia queda para cuando se diseñe el clima.
- Clima/lluvia: aplazado. Herramientas DEV (F12 fps, cámara del cielo) se quitan antes de terminar.

## Bloque 5 - estado de implementacion
- 5.1, 5.2, 5.3, 5.4, 5.5, 5.6 implementadas (sin probar en juego largo). 5.7 voces hecha antes. 5.8 parcial: refugio y dormir hechos; faltan pescar, marcar caminos, sentarse a observar con fauna, sonido por salud.
- Dormir: refugio simple (tela, madera, hojas), eleccion de minutos de la isla, pantalla de sueño con reloj acelerado, -2 % hambre y sed, mensajes de la isla segun su animo, pose fetal con Z grandes y marca brillante. El refugio dura 2 vidas.
- Regla de arte: nada nuevo puede cambiar el look; sin luces nuevas, solo piezas simples y sprites aditivos.

## Bloque 7 - Rediseño del GUI (HECHO; ver estado abajo)
- Rediseñar los inventarios, el baul y el menu de recetas (C): hoy se superponen con la vida, el hambre/sed, la hotbar y el texto de hora/sol (la lista de recetas queda debajo de esos elementos y se pisa).
- Ideas: paneles con anclas y margenes propios, la lista de recetas con scroll y que no cubra el HUD, ocultar o atenuar el HUD al abrir un menu, y revisar a distintas resoluciones y en pantalla completa.
- Captura de referencia: el menu de recetas con 'Refugio' tapado por la barra de vida.

### Bloque 7 - estado (HECHO, falta probar a mano)
- HUD apilado abajo a la izquierda: hambre/sed sobre la vida; reloj debajo. Recetas (C) centradas, 5 visibles con scroll y contador.
- Aviso 'Podes armar: X' (icono + C) arriba a la izquierda, 6 s, una vez por receta (inventory_ui.aviso_receta).
- Baul: casillas de 66 px y fondo mas oscuro. Colores del HUD mas apagados (vida, corazon, marco latón, barras).
- Pendiente: probar aviso y baul en juego; iconos flojos (cana de pescar, hacha).

### Bloque 7 parte 2 - estetica pirata (look-v9)
- Medallon redondo de fases sol/luna arriba a la izquierda (scripts/ui/medallon_fases.gd, marco ui_medallon_marco.png); reemplaza el texto de hora. No hay reloj en la isla.
- Sueno sin reloj: medallon grande, frases poeticas, 'despertarias al amanecer...' (sueno.gd).
- Paneles de naufragio: madera, cuerda, esquinas de laton (ui_theme.gd draw_panel/draw_slot, ui_madera_naufragio, ui_pergamino). 'COMBINAR' -> 'ARMAR'; baul 'BAUL DEL NAUFRAGO'.
- HUD: marcos de madera (scripts/pirate_ui.gd), iconos pintados de hambre (coco) y sed (cantimplora), corazon pirata, vidas como gemas en laton, rotulo Refugio bajo la barra.
- Nota tecnica: draw_texture_rect dejo un cuadrado blanco con los iconos de necesidades; se uso draw_set_transform + draw_texture.
- Pendiente: ver de noche la luna del medallon y el menu de dormir en juego; probar el baul.

## Estado actual del diseño y consejos de jugabilidad (revisión)
### Qué es el juego hoy
- Bucle: llegás, sobrevivís (hambre, sed, frío, agua), armás herramientas y refugio, y convivís con una isla que te estudia. Morís hasta 7 veces; la isla recuerda; al final se calcula convivir o no y te volvés la isla.
- Pilares ya implementados: cerebro de la isla y voz (frases, 5.7), vínculo oculto, salud de zonas (5.1), semillas y replantar (5.2), fuego/calor/cocina (5.3), agua (5.4), ofrendas y ofensas por bioma (5.5), huellas de náufragos (5.6), refugio y dormir, clima como filtro, noche con sonido, HUD pirata con medallón.
- Falta de 5.8: pescar, marcar caminos con piedras, sentarse a observar con fauna que se acerca, sonido según la salud de la zona.

### Consejos de jugabilidad con diseño (propuestas, nada implementado; a elegir con el usuario)
1. **Primeros 10 minutos (onboarding sin guía):** el jugador no sabe qué hacer. Sin tutorial, pero con el mundo enseñando: la barca trae cuerda y una cuchilla vieja en el cajón; el primer "Podés armar" aparece con 2 piedras; la isla susurra una pista poética sobre agua dulce. Evitar texto largo.
2. **Ritmo de necesidades:** hambre, sed y frío bajan juntos y abruman. Mejor escalonar: la sed manda primero (hay estanque cerca), el hambre después, el frío solo de noche o mojado. Un solo aviso a la vez, nunca tres.
3. **Dormir como decisión:** dormir cura pero cuesta hambre/sed y deja el cuerpo expuesto. Sugerencia: dormir fuera del refugio es posible pero pesadillas y menos curación; refugio junto a un fuego da mejor descanso. La isla comenta distinto si dormís en zona sana o dañada.
4. **Que construir tenga consecuencias:** cada cosa que armás es un evento que la isla ve. Un refugio en claro sagrado ofende; en la costa es neutro; junto a tu planta es cuidado. Así el diseño de convivencia es una decisión de lugar, no de menú.
5. **Convivir como juego, no como castigo:** además de evitar daño, dar verbos positivos con respuesta visible: plantar, ofrecer, sentarse a observar, marcar caminos sin dañar, devolver basura. Cada uno con una reacción pequeña y bella (luz, aves, flores) y nunca un número.
6. **Vidas con arco narrativo:** cada vida debería sentirse distinta. Ideas: vida 1-2 aprendés; 3-4 la isla cambia reglas (clima, fauna) según tu estilo; 5-6 aparecen señales del final; 7 es despedida. Las huellas de náufragos pueden ser vidas pasadas del jugador, no solo ajenas.
7. **La muerte no debe frustrar:** las muertes duelen poco (ataques nunca matan). Si morís es por hambre, sed, frío o agua: que el mensaje de muerte diga qué pasó, con tono poético, y que la isla recuerde dónde.
8. **Riesgo y recompensa:** zonas peligrosas (cueva de noche, roquedal, agua honda) con recompensas únicas (cristales, perlas, semillas azules) para que explorar valga la pena sin forzar combate.
9. **Mapa y orientación:** sin minimapa. Orientarse con el medallón (posición del sol), el faro, las estelas y marcas con piedras propias. La vista aérea (M) debería costar algo o limitarse.
10. **Legibilidad de la UI:** una sola ventana a la vez (recetas, baúl, dormir), HUD atenuado al abrir menús, y avisos agrupados (máximo uno en pantalla). Íconos pintados para todo lo que se pueda recoger; los que faltan hoy usan modelo 3D.
11. **Dificultad y confort:** opciones de accesibilidad: tamaño de texto del HUD, avisos de frío/hambre más o menos frecuentes, y modo "contemplativo" sin pérdida de vida por necesidades para quien solo quiere explorar.
12. **Rendimiento como diseño:** límite de objetos construibles (refugios 5 m entre sí, fogatas pocas) y dispersión de recogibles para mantener 60 fps; todo efecto nuevo sin luces ni sombras.

### Pendientes antes de publicar (sin cambios)
- Quitar herramientas de desarrollo: cámara del cielo (O), panel Clima (K), atajos F2–F10 (incluido F4), `START_HOUR`/`VINCULO_INICIO` de prueba, `fps_meter.gd`; modo de pantalla final; medir en calidad alta fuera del editor; limpiar assets sin uso.
- Probar a mano: dormir de noche con la luna del medallón, baúl con el estilo nuevo, semillas, cocina, frío, inmersión en agua, huellas, aviso de receta.
