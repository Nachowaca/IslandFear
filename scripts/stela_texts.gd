class_name StelaTexts
extends RefCounted
## Mensajes tallados por los náufragos que vinieron antes. Cortos, en mayúsculas, a modo de pista.
## Cada bloque se usa durante 5 vidas del jugador; luego las piedras cambian de lugar y de mensaje.

const BLOCKS: Array = [
	# 0 · supervivencia
	[
		"LOS HONGOS\nDE COLORES\nMIENTEN",
		"EL ESTANQUE\nNO ENGAÑA",
		"FUEGO\nCON CUIDADO\nELLA MIRA",
		"UN HACHA\nCUESTA MÁS\nQUE UN ÁRBOL",
		"LA CUEVA\nABRIGA DE DÍA\nDE NOCHE NO",
		"BEBÉ ANTES\nDE TENER SED",
		"QUIEN CORRE\nCOME MÁS",
		"LAS RAÍCES\nSE COMEN\nCRUDAS",
		"LA CUERDA\nSALE DE\nLAS LIANAS",
	],
	# 1 · convivencia
	[
		"PEDÍ\nANTES DE\nTOMAR",
		"UNA OFRENDA\nEN LA CUEVA\nCALMA",
		"NO TOQUES\nSUS CRIATURAS",
		"ELLA OBSERVA\nLOS PRIMEROS\nDÍAS",
		"QUIEN LA\nESCUCHA\nVIVE",
		"LOS PÁJAROS\nCALLAN ANTES\nDEL MAL",
		"CUANDO LA\nCUEVA ENTIBIA\nTE ACEPTÓ",
		"NO CORTES\nEL ÁRBOL\nDEL CENTRO",
		"ELLA PERDONA\nSI ESPERÁS",
	],
	# 2 · misterio
	[
		"LLEGUÉ\nUNA VEZ\nNO RECUERDO",
		"LA LUZ\nDEL MAR\nNO ES FARO",
		"SIETE\nVECES\nVOLVÍ",
		"BAJO EL ÁRBOL\nALGO LATE",
		"LOS DÍAS\nSE REPITEN",
		"LOS HONGOS\nBRILLAN\nPARA ALGUIEN",
		"LA ISLA\nTUVO MIEDO\nTAMBIÉN",
		"SOY LO QUE\nQUEDÓ\nDE ÉL",
		"NO HAY\nSALIDA\nSOLO FINAL",
	],
	# 3 · remordimiento
	[
		"LA TALÉ\nY LLORÓ",
		"LE DEBO\nUN ÁRBOL",
		"MATÉ UN\nCANGREJO\nSIN HAMBRE",
		"DEBÍ\nESCUCHAR\nSUS AVISOS",
		"ELLA AVISÓ\nYO NO\nENTENDÍ",
		"ME QUEDÓ\nSU ENOJO\nEN EL PECHO",
		"NO ERA\nMI ENEMIGA",
		"AQUÍ DURMIÓ\nUN AMIGO",
		"VOLVÉ CON\nLAS MANOS\nVACÍAS",
	],
]

## Bloque en uso según las muertes acumuladas (cambia cada 5 vidas).
static func bloque() -> int:
	var muertes: int = (Isla.ciclo - 1) * Isla.VIDAS_MAX + (Isla.vida - 1)
	return int(floor(float(muertes) / 5.0)) % BLOCKS.size()

static func mensajes(block: int) -> Array:
	return BLOCKS[block % BLOCKS.size()]

## Epitafio de una vida pasada del jugador (se talla donde murió).
static func epitafio(vida_n: int, causa: String, stats: Dictionary) -> String:
	var l2: String = "CAYÓ SIN\nSABER POR QUÉ"
	match causa:
		"hambre":
			l2 = "LO VENCIÓ\nEL HAMBRE"
		"sed":
			l2 = "LO VENCIÓ\nLA SED"
		"una roca":
			l2 = "UNA ROCA\nLO ALCANZÓ"
		"raíces espinosas":
			l2 = "LAS RAÍCES\nLO APRESARON"
		"cangrejos":
			l2 = "LOS CANGREJOS\nPUDIERON MÁS"
		"hongo venenoso":
			l2 = "CONFIÓ EN\nUN HONGO"
	var l3: String = "PASÓ SIN\nDEJAR HUELLA"
	if float(stats.get("arboles_cortados", 0.0)) >= 3.0:
		l3 = "TALÓ SIN\nPEDIR"
	elif float(stats.get("animales_molestados", 0.0)) >= 4.0 or float(stats.get("animales_cazados", 0.0)) >= 1.0:
		l3 = "MOLESTÓ A\nSUS CRIATURAS"
	elif float(stats.get("ofrendas", 0.0)) >= 1.0:
		l3 = "DEJÓ OFRENDAS"
	elif float(stats.get("fuegos", 0.0)) >= 2.0:
		l3 = "ENCENDIÓ\nDEMASIADO"
	elif float(stats.get("tiempo_corriendo", 0.0)) >= 120.0:
		l3 = "SIEMPRE\nCORRÍA"
	elif float(stats.get("tiempo_explorando", 0.0)) >= 120.0:
		l3 = "QUISO\nENTENDERLA"
	return "VIDA %d\n%s\n%s" % [vida_n, l2, l3]
