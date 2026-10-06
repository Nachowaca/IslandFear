# Plan de diseño visual (v2, enfoque memoria baja)

## Dirección de arte
Low-poly estilizado, paleta cálida de día y turquesa/violeta de noche. Pocas texturas grandes, formas claras, mucho color por vértice. Lo misterioso se cuenta con luz (cueva, árbol corazón, piedras), no con detalle pesado.

## Presupuesto de memoria (objetivo)
- Texturas: máx. ~150 MB en VRAM. Nada de 4K; 1K para terreno, 512 para props, 256 para detalles.
- Modelos: reutilizar con MultiMesh. Un árbol ~6k tris es el techo; props pequeños <1k.
- Sin HDRI grande (usar el cielo procedural actual). Sin audio pesado (todo sintetizado).
- Importar texturas con compresión VRAM (BPTC/ASTC), mipmaps ON.
- Nunca cargar packs enteros: copiar solo los modelos usados a `res://assets/<pack>/`.

## Assets a bajar (en orden de prioridad, todos CC0)
1. **Quaternius – Ultimate Stylized Nature** (palmeras, rocas, plantas). Reemplaza los "árboles de costa". Formato glTF. Liviano (~20 MB).
2. **Kenney – Pirate Kit** (restos de barco, cofres, barriles, muelle). Muy liviano (~5 MB).
3. **Kenney – Graveyard Kit** (cruces, lápidas, velas) para tumbas y misterio. ~5 MB.
4. **ambientCG – 3 texturas 1K**: Ground (tierra/pasto), Rock (roca), Sand. Solo Color + NormalGL, JPG.
5. **Quaternius – Ruins/Fantasy props** (arcos, columnas rotas) para el misterio. Solo 5–8 piezas.
6. Opcional: **Kenney Nature Kit** (troncos, hongos, piedras de camino).
Descargá, descomprimí y dejá en `res://assets/<nombre_pack>/`. No hace falta limpiar; yo copio lo que sirva.

## Qué ya tenemos y se puede borrar para ahorrar memoria
`res://OBJ` y `res://FBX` del Stylized Nature MegaKit (duplican los glTF). Confirmame y los borro.

## Fases de trabajo
1. **Terreno**: texturas PBR por pendiente/altura (arena, pasto, roca), 1K triplanar. Playa más suave, colinas más claras.
2. **Costa**: palmeras reales, espuma en la orilla, restos de naufragio, troncos varados.
3. **Misterio**: camino de piedras al árbol corazón, ruinas pequeñas, tumbas con velas, círculo de hongos que brilla de noche.
4. **Vida**: mariposas de día, luciérnagas y flores luminosas de noche, lagartijas y pájaros.
5. **Atmósfera**: niebla baja por zonas, rayos de luz entre árboles (sin volumétrico), colores según el vínculo.
6. **Optimización**: LOD/visibility ranges, MultiMesh en todo lo repetido, medir FPS y memoria.
7. **Personaje y UI**: rediseño del castaway, barras y pantallas de muerte/final con el estilo isla.

## Cómo medimos
Monitor de memoria de Godot (VRAM, objetos, draw calls) en una partida de 5 min. Meta: 60 fps estables en tu M1, <1.5 GB de RAM.
