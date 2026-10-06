# Plan visual y de misterios de la isla

## Hecho
- Palmeras poligonales eliminadas: los "árboles de la costa" (mecánica de cocos/hojas/cuerda intacta) usan CommonTree del MegaKit, inclinados por el viento.
- Bosque, arbustos, rocas, suelo y árbol corazón con el MegaKit (ver PROGRESS.md).

## Assets a descargar (todos gratuitos; verificar la licencia al bajarlos)
Prioridad alta:
1. **Quaternius – Ultimate Stylized Nature** (CC0): trae **palmeras**, cocoteros, rocas, plantas tropicales y troncos. Mismo estilo que el MegaKit.
2. **Kenney – Graveyard Kit** (CC0): lápidas, cruces, velas, vallas rotas. Base de las piedras de los náufragos.
3. **Kenney – Pirate Kit** (CC0): cofres, restos de barco, barriles, calaveras, bote roto, cañones. Para naufragios y misterios.
4. **ambientCG** (CC0, texturas PBR): "Sand", "Ground", "Rock", "Moss", "Mud". Mejoran el terreno por altura y pendiente.
Prioridad media:
5. **Poly Haven** (CC0): un HDRI de cielo crepuscular para reflejos y 2–3 modelos de rocas/troncos realistas.
6. **Quaternius – Ultimate Fantasy/Ruins** (CC0): arcos, columnas rotas, ruinas para un templo antiguo.
7. **Kenney – Nature Kit** (CC0): más rocas, troncos, setas, puentes, nubes.
Opcional: Quaternius animales (cangrejos, aves, lagartijas) y sonidos CC0 de freesound/Kenney Audio.

Cómo bajarlos: descomprimir en `res://assets/<nombre_del_pack>/` (formato glTF/GLB si hay opción). Después me avisás la carpeta y los integro.

## Misterios y detalles (orden de trabajo)
1. **Piedras de los que vinieron antes**: estelas/lápidas rústicas con mensajes.
   - Mensajes de **tus propias vidas pasadas**: tras cada muerte aparece una piedra donde caíste, con un epitafio generado de lo que hiciste (días vividos, causa, si talaste o cuidaste). Se lee con F.
   - Mensajes de **otros náufragos** (escritos por mí, un texto por piedra, repartidos por la isla): consejos, advertencias y confesiones ("No cortes el árbol del centro", "Ofrecele algo en la cueva y te deja en paz", "Yo la odié. Ella me escuchó igual").
   - La isla reacciona: si las tocás con mala intención se enoja, si dejás una ofrenda se calma. Con confianza alta aparecen flores sobre ellas.
   - Mensajes del vínculo: algunas piedras solo se vuelven legibles cuando la relación sube (musgo que se retira).
2. **Camino de piedras** (RockPath del MegaKit) desde la playa hasta el árbol corazón o la cueva.
3. **Naufragios** en la costa (Pirate Kit): restos de un bote con cosas útiles y una nota.
4. **Flores nocturnas** que brillan (Flower_3/4 con emisión) y **luciérnagas** (partículas) cerca del árbol corazón.
5. **Fauna chica**: mariposas de día, luciérnagas de noche, lagartijas en las rocas, cangrejos ya existentes. Reaccionan al vínculo (se acercan si la isla confía, huyen si no).
6. **Agua**: espuma en la orilla, ondas alrededor de piedras, reflejos; sin efectos que cuelguen Godot.
7. **Realismo del terreno**: texturas PBR por altura/pendiente, huellas en la arena, hojas caídas, charcos tras la lluvia.
8. **Viento** en toda la vegetación nueva (shader de balanceo suave).

## Decisiones abiertas para el usuario
- ¿Epitafios en primera persona del náufrago muerto, o escritos por la isla?
- ¿Las piedras de otros náufragos son fijas o cambian en cada ciclo (nuevo ciclo = otros mensajes)?
