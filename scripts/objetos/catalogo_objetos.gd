class_name CatalogoObjetos
extends RefCounted

## Catálogo de objetos decorativos (bloque 4.5). Para sumar uno: agregar su fila en ITEMS, la forma en
## ObjetoBuilder.mesh_for y cuántos van por zona en ZONAS. Categorías: estetico, recogible, herramienta, contaminante.
## escala: tamaño sobre el modelo base (algunos son chicos y se exageran un poco, estilo cuento).
## tilt: inclinación máxima (rad) al apoyarlo. hundir: cuánto queda enterrado.

const ITEMS: Dictionary = {
	"calavera": {"cat": "estetico", "escala": 1.4, "tilt": 0.2, "hundir": 0.03},
	"cruz": {"cat": "estetico", "escala": 1.0, "tilt": 0.1, "hundir": 0.3},
	"ojos": {"cat": "estetico", "escala": 1.3, "tilt": 0.05, "hundir": 0.08},
	"cofre": {"cat": "estetico", "escala": 1.0, "tilt": 0.12, "hundir": 0.12},
	"lata": {"cat": "estetico", "escala": 1.7, "tilt": 0.1, "hundir": 0.0},
	"botella_verde": {"cat": "estetico", "escala": 1.6, "tilt": 0.1, "hundir": 0.01},
	"botella_ambar": {"cat": "estetico", "escala": 1.6, "tilt": 0.1, "hundir": 0.01},
	"caracola": {"cat": "estetico", "escala": 1.6, "tilt": 0.05, "hundir": 0.0},
	"estrella": {"cat": "estetico", "escala": 1.8, "tilt": 0.0, "hundir": 0.0},
	"ancla": {"cat": "estetico", "escala": 1.1, "tilt": 1.3, "hundir": 0.1},
	"tablones": {"cat": "estetico", "escala": 1.0, "tilt": 0.08, "hundir": 0.02},
	"barril": {"cat": "estetico", "escala": 1.0, "tilt": 0.05, "hundir": 0.08},
	"remo": {"cat": "estetico", "escala": 1.0, "tilt": 0.25, "hundir": 0.35},
	"cairn": {"cat": "estetico", "escala": 1.0, "tilt": 0.03, "hundir": 0.03},
	"fogata_apagada": {"cat": "estetico", "escala": 1.0, "tilt": 0.0, "hundir": 0.0},
	"huesos": {"cat": "estetico", "escala": 1.5, "tilt": 0.0, "hundir": 0.0},
	"cuerda": {"cat": "estetico", "escala": 1.2, "tilt": 0.0, "hundir": 0.0},
}

## Cuántos de cada uno por zona y por vida.
const ZONAS: Dictionary = {
	"playa": {"botella_verde": 2, "botella_ambar": 1, "lata": 2, "caracola": 3, "estrella": 2, "tablones": 2, "barril": 1, "ancla": 1, "cofre": 1},
	"paseo": {"cruz": 1, "calavera": 2, "huesos": 2, "fogata_apagada": 1, "cairn": 2, "remo": 1, "lata": 1},
	"estanque": {"ojos": 1, "botella_verde": 1, "cuerda": 1, "cairn": 1, "tablones": 1, "calavera": 1, "lata": 1, "huesos": 1},
}
