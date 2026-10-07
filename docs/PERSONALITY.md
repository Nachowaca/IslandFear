# Personalidad de la isla (ideas guardadas, para realizar después)

> Documento de diseño. Nada de esto está implementado salvo lo marcado como **[HOY]**.
> Reglas fijas: el jugador NO ve el vínculo (sin barras ni números); la isla no habla en voz, solo texto corto;
> las ofensas duelen pero **nunca matan**; el juego trata de **convivir**, no de herirse.

## 1. Cómo funciona hoy [HOY] (`isla.gd`)

**Vínculo** (lento, oculto): -100 … +100. Etapas por umbral:

| Etapa | Rango | Qué significa |
|---|---|---|
| Hostil | < -40 | puede atacar (nunca mata) |
| Desconfiada | -40 … -10 | vigila, avisa |
| Extraña | -10 … 15 | neutral (arranque en 0) |
| Tolerante | 15 … 45 | te deja estar |
| Aceptante | 45 … 75 | ayuda de a poco |
| Aliada | > 75 | convive, luciérnaga, regalos |

- Paz: tras 90 s sin ofensas el vínculo sube solo (+0.02/s) hasta 40; si es negativo se sana (+0.03/s). Para pasar de 40 hacen falta gestos (ofrendas).
- Efectos al vínculo hoy: árbol cortado -8, animal cazado -12, fuego -3, animal molestado -0.6, zona sagrada -0.5, fruto -0.15, ofrenda +7, cuidado +1, explorar +0.2.

**Emociones** (rápidas, 0..1, vuelven a su base): confianza (base 0.45, decae 0.008/s), enojo (0.15, 0.012/s), miedo (0.1, 0.03/s), curiosidad (0.5, 0.02/s). Cada evento las mueve (tabla `EVENTOS`). El enojo cuesta soltarlo; el miedo pasa rápido.

**Dónde se nota hoy:** pasto del terreno (`mood`), flora y viento (`Wind.set_mood`: tensa = más movimiento y colores apagados; serena = lento y cálido), niebla, audio, tono del texto, ataques si hostil.

## 2. La pregunta: ¿qué la pone contenta o enojada?

Principio: la isla es un **ecosistema**. Se enoja con lo que daña su equilibrio sin necesidad; se alegra con lo que lo cuida o lo disfruta junto a vos. Importa la **intención y la medida**, no el acto aislado (comer un fruto no ofende; arrasar sí).

### 2.1 Enojo (tus ideas, ordenadas por cómo se juegan)

| Causa | Cómo se detecta | Gravedad | Notas de jugabilidad |
|---|---|---|---|
| Cortar árboles "porque sí" | Talar sin necesidad: sin replantar, o más de N por zona, o cerca de otros ya talados | Media -> alta | Talar 1-2 para fabricar es tolerado; "porque sí" = cortar y no usar la madera / no replantar. Replantar compensa |
| Mal uso de recursos | Recoger más de lo que se usa, tirar comida/materiales, dejar fuego sin fuel, desperdicio | Baja, acumulativa | Contador por zona; se perdona si luego devolvés o replantás |
| Atacar animales (solo peces se puede) | Golpear/cazar cualquier animal salvo peces | Alta (cazar) / baja (molestar) | Peces: pescar es la única caza permitida, sin enojo |
| Contaminantes sin dejarlos en la cueva | Objetos "contaminantes" (basura de otros náufragos: botellas, latas, baterías, plástico) recogidos y no depositados en la cueva tras un tiempo | Media, crece con el tiempo | Misión silenciosa: limpiar la isla. Depositar en la cueva = confianza. Ver 3.2 |
| Pisar cangrejos sin querer | Colisión con cangrejo al correr cerca de la playa | Muy baja | Castiga correr; caminar los esquiva. Enseña a ir despacio |

### 2.2 Confianza (tus ideas, ordenadas)

| Causa | Cómo se detecta | Valor | Notas de jugabilidad |
|---|---|---|---|
| Ofrendas en los templos | Dejar objeto en un templo/altar | Alta | Mejor si encaja con el bioma (flor al claro, piedra al roquedal, agua a la selva) |
| Plantar flores o árboles | Semilla plantada que crece | Alta (suma salud de zona) | Requiere semillas (al talar o recoger) y cuidar que prendan |
| Amanecer/atardecer junto a la fogata | Fogata encendida + jugador cerca, quieto/sentado, hora del alba o del ocaso | Alta, rara | La isla dice una frase amistosa. Una vez por día |
| Pasear disfrutando (no correr en peligro) | Caminar sin correr, tiempo en biomas distintos sin dañar | Baja pero constante | Ya existe `explorar` (+0.2); afinar para premiar variedad y calma |
| Observar aves y flores raras | Mirar un grupo de aves volando o una flor rara/brillante por unos segundos (F investigar) | Baja-media | Cada flor rara se "descubre" una vez |

## 3. Más ideas (a confirmar con el usuario)

### 3.1 Confianza extra
- **Sentarse a observar**: quedarse quieto y tranquilo un rato en un claro; la fauna se acerca (venado, aves) y la isla lo nota.
- **Devolver lo sobrante**: dejar frutos en el suelo de un claro / compartir comida con animales.
- **Curar y sembrar**: regar plántulas, dar agua a una planta seca, sacar una liana que ahoga un árbol joven.
- **Limpiar la costa**: recoger basura de la playa (botellas, redes) y llevarla a la cueva.
- **Seguir un camino hecho de piedras** o marcar uno propio sin dañar.
- **Silencio**: no hacer ruido (no correr, no golpear) de noche en el bosque.
- **Visitar las tumbas** de vidas pasadas sin dañar nada alrededor.
- **Dormir cerca de la fogata** con refugio: la isla "te cuida" la noche.
- **Pesca moderada**: pescar solo lo que se come.
- **Respetar los claros sagrados**: rodearlos en vez de atravesarlos.

### 3.2 Enojo extra
- **Ensuciar el agua** (arrojar basura, lavar cosas en el estanque).
- **Fuego en zona húmeda/selva** o cerca de árboles jóvenes (en costa/claro, no).
- **Pisar flores raras/brillantes** o plantas plantadas.
- **Cavar o arrancar plantas enteras** en vez de cosechar solo frutos.
- **Romper cosas de la isla** (ruinas, tumbas, piedras apiladas).
- **Gritar/correr de noche** cerca de nidos o claros sagrados.
- **Acumular**: llevar demasiado de un solo recurso.
- **Dejar rastros contaminantes** (restos de fuego, basura) en un bioma limpio.

### 3.3 Matices (para que se sienta viva y justa)
- **Perdón y memoria**: la isla perdona más rápido ofensas viejas; las repetidas pesan más (rachas).
- **Contexto**: talar es más grave en selva densa que en bosque ralo; cazar peces nunca.
- **Zona por zona**: cada bioma tiene su ánimo; ofender en uno no arruina los demás (usa `EcoMap` y `calor_dano`).
- **Segundas oportunidades**: antes del ataque hay avisos sutiles (viento, aves se van, flores se cierran).
- **Reconciliación**: tras una ofensa, una ofrenda o replantar baja el enojo más rápido de lo normal.
- **Personalidad por ciclo**: en cada ciclo cambia qué le importa más (`_personalidad_inicial`) -> a veces es más sensible al fuego, otras a los animales.

## 4. Señales sutiles (sin mostrar el vínculo)

| Ánimo | Flora/viento | Fauna | Sonido | Texto |
|---|---|---|---|---|
| Serena/contenta | Movimiento lento, colores cálidos, flores brillantes más intensas | Aves y mariposas se acercan, el venado no huye | Cantos más suaves | Frases amistosas, curiosas |
| Neutral | Normal | Normal | Normal | Observadora |
| Tensa | Más viento y temblor, colores apagados | Aves se van, silencio | Graves, viento | Frases secas |
| Enojada | Vegetación se cierra, niebla, viento fuerte | Fauna escondida | Tensión | Advertencias; a hostil, ataques que hieren sin matar |

## 5. Jugabilidad real: orden sugerido para implementar

1. **Aclarar eventos** en `Isla.EVENTOS`: agregar los que faltan (`arbol_sin_uso`, `cangrejo_pisado`, `contaminante_pendiente`, `agua_sucia`, `planta_pisada`, `planta_sembrada`, `atardecer_fogata`, `contemplar`, `ofrenda_templo`, `limpiar_isla`) con su efecto en emociones y vínculo.
2. **Cangrejos y peces**: colisión de cangrejos (enojo muy bajo) y pesca permitida (sin enojo).
3. **Plantar**: semillas y brotes; premio de confianza cuando prenden (comparte con 5.2 del plan del bloque 5).
4. **Contaminantes y cueva**: objetos de otros náufragos marcados como contaminantes + depósito en la cueva (ver 5.6).
5. **Contemplar**: detector de quietud + fogata + hora del día -> frase amistosa (`island_voice.gd`).
6. **Observar aves/flores raras**: mirar con F durante unos segundos.
7. **Ofrendas por bioma**: valor extra si encaja con la zona.
8. **Tala con intención**: distinguir talar con uso y replantar de talar sin sentido.
9. **Señales sutiles** según la tabla del punto 4 (la flora ya está hecha).

## 6. Preguntas abiertas
- ¿Cuántos contaminantes puede cargar el jugador antes de que la isla se queje, y cuánto tiempo se le da para llevarlos a la cueva?
- ¿Los templos ya existen o hay que crearlos (altares por bioma)?
- ¿La isla perdona si el jugador murió por su culpa (ataque), o la muerte cuenta como algo neutral?
- ¿Un nivel de enojo máximo por zona, para no volver imposible el juego?
