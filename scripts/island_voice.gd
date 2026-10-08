class_name IslandVoice
extends RefCounted

## La "boca" de la isla: genera frases variadas según el tema, el tono y lo que observó del jugador.
## Evita repetir frases recientes y mezcla aperturas / remates según el humor.

var rng := RandomNumberGenerator.new()
var _recent: Array[String] = []

const OPEN: Array = [
	["Mmm.", "Veo.", "Interesante.", "Hm.", "Curioso.", "Así que...", "Ah.", "Vaya."],
	["Escucho.", "Lo noté.", "Otra vez.", "Sí.", "Presto atención.", "Claro."],
	["Basta.", "Ya.", "Suficiente.", "Mirá nomás.", "Qué lástima."],
]
const TAIL: Array = [
	["Lo anoto.", "Sigo mirando.", "Aún no sé qué sos.", "Me interesa.", "Aprendo.", "Todo cuenta."],
	["No me gusta.", "Cuidado.", "Lo recuerdo.", "Todo queda anotado.", "Me estoy cansando."],
	["Tu tiempo se acaba.", "Ya falta poco.", "Lo vas a pagar.", "Disfrutalo mientras puedas.", "No hay salida."],
]

const POOLS: Dictionary = {
	"greet": ["Un extraño pisa mi arena.", "Alguien llegó con el mar. Qué raro.", "Te vi llegar. Te miraba desde antes.", "Mi arena siente tus pies.", "Otro cuerpo sobre mi piel. Despacio, que te estudio."],
	"return": ["Volviste. Recuerdo cómo caíste.", "Otra vez vos. Ya sé cómo caminás.", "Es tu vuelta número {n}. No me sorprendés.", "Pensé que el mar te había devuelto para siempre."],
	"day_pass": ["Ya pasó un día entero desde que llegaste.", "Un día más. Seguís acá.", "Día número {n} de tu estadía. Tomo notas.", "Amaneció y seguís respirando mi aire."],
	"sacred_warn": ["No te acerques a {place}.", "{place} es sagrado para mí.", "Alejate de {place}, {who}.", "Un paso más en {place} y lo lamentás.", "Estás pisando {place}. Salí."],
	"obs_walk": ["Caminás sin parar, {who}. ¿Qué buscás?", "Ya recorriste {n} metros de mi piel. Los conté.", "No te quedás en ningún lado. Inquieto.", "Tus pies no descansan. Me hacen cosquillas.", "Das vueltas como quien huele una salida."],
	"obs_still": ["Te quedás quieto. ¿Esperás algo?", "Respirás despacio. Te escucho.", "Quieto como una piedra. Las piedras me gustan más.", "¿Descansás? Nadie descansa en mi isla.", "Cuando no te movés, te pienso mejor."],
	"obs_cave": ["Te escondés en mis rocas.", "Buscás refugio en {place}. Qué previsible.", "Siempre vuelven a la cueva. Siempre.", "Dentro de la piedra te creés a salvo.", "Tu sombra desaparece en {place}. La sigo igual."],
	"obs_beach": ["Mirás el mar más que a mí.", "Tus pasos dejan marcas en mi orilla; la marea las borra.", "Te quedás cerca del agua. ¿Esperás un barco?", "El mar no vendrá a buscarte.", "La arena guarda tu forma un instante."],
	"obs_forest": ["Te metés entre mis árboles. Ellos también te miran.", "Pisás mi bosque con cuidado. Aprendés.", "Los árboles se inclinan para oírte.", "Entre los troncos te perdés de vista... pero no de mí.", "Mi bosque tiene memoria, {who}."],
	"obs_animals": ["Dejá en paz a mis criaturas.", "Esos bichos son míos. No los toques.", "Asustás a los que viven acá.", "Cada vez que molestás a una criatura, algo en mí se encoge.", "Los animales huyen de vos. Hacen bien.", "¿Te divierte perseguirlos, {who}?"],
	"obs_taken": ["Levantás mis frutos como si fueran tuyos.", "Cada cosa que tomás me falta después.", "Recogés lo que no plantaste, {who}.", "Tomás sin pedir. Lo noto.", "Mi tierra da, pero no regala."],
	"obs_sacred": ["{place} no es para vos.", "¿Sentís el peso de {place}? Es mi memoria.", "Te acercás a {place}. Cuidado con lo que tocás.", "Ahí no. Nadie se queda en {place}.", "Insistís con {place}."],
	"obs_run": ["Corrés. ¿De qué huís?", "Tanta prisa... ¿ya te querés ir?", "Cuando corrés, el suelo lo siente.", "Huir cansa, {who}. Yo no me canso.", "Tus pasos apurados delatan el miedo."],
	"obs_night": ["De noche caminás. Pocos se animan.", "La oscuridad no te frena. Curioso.", "¿No dormís? Yo tampoco.", "Salís cuando estoy más despierta.", "Andás en mi oscuridad sin miedo. Todavía."],
	"obs_turns": ["Dudás. Das un paso y te arrepentís.", "Cambiás de rumbo tantas veces... ¿qué te pesa?", "Giraste otra vez. Aprendo de tus dudas.", "Vas y venís como la marea."],
	"obs_revisit": ["Volviste por donde ya habías pasado.", "Este lugar te llama de vuelta. A mí también.", "Das la vuelta sobre tus propias huellas.", "Los que se pierden siempre vuelven al mismo punto."],
	"obs_bioma_costa": ["Siempre volvés a la orilla. ¿Esperás que alguien venga a buscarte?", "Vivís donde termino. Me mirás desde afuera.", "La arena te sostiene menos que yo, y aun así no entrás."],
	"obs_bioma_roquedal": ["Subís a mis huesos. Te gusta lo que no se mueve.", "En la roca nada te esconde. Y aun así vas.", "Me pisás donde soy más vieja."],
	"obs_bioma_selva": ["Te metés en lo más espeso de mí. Ahí se oye mi respiración.", "En la selva casi no te veo. Eso me inquieta y me gusta.", "Te gusta lo húmedo. Se nota por dónde dejás las huellas."],
	"obs_bioma_bosque": ["Pasás horas bajo mis árboles. Te acostumbrás.", "El bosque te conoce el paso.", "Caminás entre mis troncos como si te dejaran."],
	"obs_bioma_matorral": ["Andás por el matorral, donde crece lo que nadie planta.", "Prefirís lo ralo, donde se ve lejos.", "Vivís en mis zonas de paso. Casi no te quedás."],
	"obs_bioma_arido": ["Elegís lo seco. Ahí casi nada crece.", "¿Por qué buscás donde falta agua?", "En mis zonas secas todo se nota más."],
	"first_cave": ["Encontraste la cueva. Todos la encuentran.", "Ahí dentro hay algo antiguo. No lo despiertes.", "La piedra te dejó pasar. Curioso."],
	"first_run": ["Así que sabés correr.", "Primera vez que corrés. ¿Fue por miedo?", "Qué rápido movés esas patitas."],
	"first_night": ["Caminás de noche. Eso no lo hacía nadie.", "La primera noche te encuentra despierto.", "Salís en la oscuridad. Valiente o ciego."],
	"echo": ["Mirá. Esos pasos son tuyos.", "Alguien repite tu camino.", "Te sigo con luz prestada."],
	"wisp": ["Una luz que no es del faro.", "No la sigas. O sí.", "Allá. ¿La ves?"],
	"footsteps": ["Escuchaste algo, ¿no?", "No te des vuelta.", "No soy yo. O sí."],
	"warn_animals": ["Última advertencia: dejá a mis criaturas.", "Soltá a los que viven acá, {who}. Es la única vez que lo pido.", "Lo que hacés con ellos lo siento yo."],
	"warn_sacred": ["Salí de {place}. Última vez que lo digo.", "{place} no se pisa. Retrocedé.", "Me estás obligando, {who}. Retrocedé de {place}."],
	"warn_taken": ["Basta de tomar. Estoy contando.", "Lo que levantás me falta. Cuidado.", "Una cosa más y se termina mi paciencia."],
	"warn_generic": ["Estás cruzando una línea que no ves.", "Mi paciencia tiene fondo.", "Esta es mi advertencia, {who}."],
	"react_trees": ["Un árbol menos. Lo sentí caer hasta las raíces.", "Cada tronco que derribás me arranca algo.", "Ese árbol tenía más años que tu nombre.", "¿Cuántos más, {who}?", "Hacha en mi carne. Lo recuerdo."],
	"react_fire": ["Fuego. En mi piel seca. Qué valiente.", "Tu fuego huele a hogar. No es tu hogar.", "Una chispa mía te mira arder.", "La llama te da luz. A mí, miedo.", "Cuidá ese fuego, {who}. Yo también tengo sed de él."],
	"react_chest": ["Esa caja guarda tus cosas. Lo sé.", "Dejás tus cosas ahí. Las veo.", "Una caja de madera, y todo lo que no querés perder.", "Guardás. Como si fueras a quedarte."],
	"react_offering": ["¿Es para mí? Qué raro.", "Una ofrenda. Nadie dejaba nada hacía mucho.", "Lo acepto. No creas que cambia todo.", "Eso estuvo bien, {who}.", "Lo guardo. Me gusta cuando devolvés."],
	"warn_trees": ["Basta de talar, {who}. Esos árboles son míos.", "Un árbol más y dejo de ser paciente.", "Tu hacha ya me dolió. Última vez que lo digo."],
	"warn_fire": ["Ese fuego puede salirse de control, {who}.", "Apagalo, o lo apago yo.", "Mi paciencia con tu fuego se está acabando."],
	"etapa_up_2": ["Ya no te miro como una amenaza.", "Dejaste de sobresaltarme."],
	"etapa_up_3": ["Ya no me molestás tanto.", "Te dejo pasar.", "Empezás a ser parte del paisaje."],
	"etapa_up_4": ["Empiezo a acostumbrarme a vos.", "Tus pasos ya no me asustan.", "No es tan malo tenerte acá."],
	"etapa_up_5": ["Podés quedarte. Quizás ahora sí.", "Somos casi lo mismo, vos y yo.", "Ya no me da miedo que me conozcas."],
	"etapa_down_0": ["No te quiero acá.", "Me hiciste demasiado daño."],
	"etapa_down_1": ["Algo se rompió entre nosotros.", "Ya no confío en vos."],
	"etapa_down_2": ["Volvés a ser un extraño.", "Se enfrió lo que habíamos hecho."],
	"etapa_down_3": ["Me estás decepcionando.", "Pensé que ibas a cuidarme."],
	"etapa_down_4": ["Algo se enfrió.", "Duele cuando hacés eso."],
	"niebla": ["Una bruma sube desde el mar.", "Dejá de ver tan lejos.", "La niebla es mi manera de cerrar los ojos.", "Todo se vuelve más cerca.", "Respirá despacio. Ahora el aire es mío."],
	"vegetacion": ["Las hojas se agitan sin viento.", "Algo recorre el follaje.", "El bosque se estira.", "Cada rama sabe dónde estás."],
	"sonidos": ["¿Oíste eso?", "No era un animal.", "Algo se movió entre las ramas."],
	"final_titulo_convivir": ["Raíces", "Respirar juntos", "El último desembarco", "Marea mansa", "Un solo cuerpo"],
	"final_titulo_no_convivir": ["Sal", "La isla se queda sola", "Lo que el mar devuelve", "Cenizas de arena", "Eco sin nadie"],
	"final_ap_destructor": ["Hiciste daño en cada vida. Cada tronco caído, cada criatura herida, me quedó clavado.", "Rompiste mucho de mí. Aprendí tu forma de pisar demasiado bien.", "Dejaste cicatrices en mi piel. Las cuento una por una."],
	"final_ap_cuidador": ["Cuidaste lo que otros habrían roto. Eso también lo anoté.", "Dejaste ofrendas donde nadie las pedía. Aprendí a esperar tus pasos.", "Pisaste con cuidado en cada vida. Me acostumbré a vos."],
	"final_ap_explorador": ["Recorriste cada rincón. Ya no queda lugar de mí que no hayas visto.", "Caminaste sin parar, siempre curioso. Me conocés más que yo.", "Tantos pasos tuyos quedaron en mi arena que ya son parte del mapa."],
	"final_ap_neutral": ["No fuiste ni amigo ni enemigo. Fuiste alguien que pasó siete veces.", "Pasaste por mí sin tomar partido. Siete veces. Siempre volviste.", "Ni daño ni ofrendas: solo presencia. Y la presencia también pesa."],
	"final_cuerpo_convivir": ["Esta vez no hay barco que te lleve. Dejo que mi tierra te abrace: tus huesos se vuelven raíces, tu respiración, brisa. Somos una sola isla.", "Te acepto. Sos mi nuevo corazón, y por primera vez no estoy sola.", "Ya no te necesitás a vos mismo: sos mis rocas, mis olas, mi sombra. Convivimos adentro del mismo cuerpo."],
	"final_cuerpo_no_convivir": ["No hay lugar para dos en mí. Te disuelvo despacio: tu nombre se vuelve sal, tu miedo, niebla. Me convierto en lo único que queda de vos.", "Te absorbo sin perdón. Tu voz se queda en mi viento, repitiendo lo que ya no podés decir.", "No convivimos: te consumo. Sos la isla ahora, y yo soy lo que te recuerda."],
	"final_cierre": ["Y cuando otro barco llegue, nadie recordará cómo empezó.", "El mar trae otra corriente. Todo comienza de nuevo, pero distinto.", "Desde acá se escucha el ruido de un casco nuevo. Empieza otro ciclo.", "La marea sube, baja, y alguien nuevo desembarca. Yo ya no soy la misma."],
	"generic": ["Sigo estudiándote.", "Todavía no sé qué sos.", "{who}, ¿qué querés de mí?", "Aprendo tu manera de pisar.", "Cada rato te conozco un poco más.", "Silencio. Estoy pensando en vos.", "Tu respiración tiene un ritmo. Lo memorizo."],
	"verdict_animals": ["Terminé de estudiarte. Molestás a mis criaturas. Eso no se perdona.", "Ya te conozco: perseguís, asustás, tocás lo que no es tuyo. Se acabó la paciencia."],
	"verdict_sacred": ["Terminé de estudiarte. Insistís en pisar {place}. Voy a corregirte.", "Ya sé qué sos: alguien que no respeta {place}."],
	"verdict_still": ["Terminé de estudiarte. Te quedás quieto, un blanco paciente.", "Ya te conozco. Esperás. Yo también."],
	"verdict_cave": ["Terminé de estudiarte. Vivís en la cueva. Eso se puede aprovechar.", "Te escondés mucho. Ya sé dónde buscarte."],
	"verdict_restless": ["Terminé de estudiarte. No parás. Yo sí sé esperar.", "Ya te conozco: siempre en movimiento. Te voy a frenar."],
	"verdict_taken": ["Terminé de estudiarte. Me vaciás de a poco. Voy a cobrarlo.", "Ya sé qué sos: alguien que toma sin devolver."],
	"verdict_calm": ["Terminé de estudiarte. No hiciste daño... pero igual no te quiero acá.", "Ya te conozco. No sos malo, solo sobrás."],
	"tremor": ["El suelo tiembla bajo tus pies.", "La isla respira. Sentís su pulso.", "Algo enorme se mueve debajo.", "Me estiro. Disculpá si te sacudo.", "Eso que sentiste es mi corazón."],
	"birds": ["Las aves huyen de golpe.", "Se hizo un silencio extraño.", "Hasta los pájaros saben cuándo callar.", "Les pedí que se fueran. No querían oírte."],
	"eyes": ["Algo te mira desde los árboles.", "Hay ojos entre las sombras.", "No estás solo, aunque lo desees.", "Los troncos parpadean cuando te das vuelta."],
	"atk_rock": ["Mirá arriba.", "La roca no avisa.", "Las piedras caen donde yo quiero.", "Gravedad: mi aliada.", "Esa piedra te estaba esperando."],
	"atk_thorn": ["El suelo se agrieta.", "Las raíces te buscan.", "No hay dónde pisar.", "Mi tierra te agarra los tobillos.", "Quedate. Las raíces quieren conocerte."],
	"atk_crab": ["Las criaturas de la orilla te rodean.", "Los cangrejos vienen por vos.", "Mis hijos de la costa tienen hambre.", "Pisaste su casa. Ahora ellos pisan la tuya."],
	"atk_crab_revenge": ["Tocaste a mis criaturas. Ahora ellas te tocan a vos.", "Perseguiste a los míos. Que te persigan.", "Cada cangrejo recuerda tus pasos."],
	"atk_trap": ["Ahora no hay sol que te proteja.", "La cueva se cierra. Ya no es refugio.", "Entraste a mi boca, ¿recordás?"],
	"trap_end": ["Sal de ahí... si puedes.", "Te dejo salir. Por ahora.", "Respirá. Todavía no terminé."],
	"hit": ["Eso dolió, ¿verdad?", "Aprendés rápido.", "Uno menos de tus huesos intactos.", "Te sentí caer. Lo disfruté.", "Así se siente mi isla."],
	"miss": ["Casi.", "Te moviste bien. Me acordaré.", "Esquivás... por ahora.", "Hm. Corrijo la puntería."],
	"mood_0": ["La isla se calma.", "Respiro. Por ahora.", "Todo vuelve a su lugar."],
	"mood_1": ["La isla te observa.", "Siento que me mirás. Yo también.", "Algo en el aire se tensa."],
	"mood_2": ["La isla se agita. Algo cambió en el aire.", "Me incomodás cada vez más.", "Ya no te miro con curiosidad."],
	"mood_3": ["La isla ya no te quiere aquí.", "Basta de cortesía.", "Mi paciencia tiene fondo, y lo estás tocando."],
	"mood_4": ["La isla está furiosa.", "Ya no queda paciencia.", "Todo lo que soy te rechaza."],
	"cave_day": ["Ahí dentro no puedo tocarte. Esperaré a la noche.", "Te escondés bajo mi piel. Volverás a salir.", "El sol te protege hoy. Solo hoy.", "Dormí tranquilo. La noche es larga."],
	"cave_night": ["Qué oscuro está ahí dentro.", "Ya no hay sol.", "La piedra respira de noche.", "Se terminó el refugio."],
	"night": ["La noche es mía.", "Te escucho respirar.", "Cada paso tuyo me despierta.", "Es mi hora, no la tuya."],
	"hostile": ["Andate.", "Este no es tu lugar.", "Cada vez me duele más tenerte.", "El mar te trajo. Que te lleve."],
}

const R_SUBJ: Array = ["El viento", "La arena", "Las piedras", "El mar", "Los árboles", "La niebla", "La luna", "Mis raíces", "La marea", "El musgo", "Las gaviotas", "Lo que hay bajo la tierra"]
const R_VERB: Array = ["recuerda", "guarda", "susurra", "esconde", "espera", "conoce", "olvida", "cuenta", "reclama", "persigue"]
const R_OBJ: Array = ["tu nombre", "tus pasos", "lo que buscás", "el camino de vuelta", "un secreto", "tu miedo", "lo que dejaste atrás", "a los que llegaron antes", "la hora exacta en que llegaste", "lo que todavía no hiciste"]
const R_FORM: Array = ["{s} {v} {o}.", "{s} {v} {o}. Yo también.", "¿Sabías que {s_l} {v} {o}?", "{s} {v} {o}... pero no a vos.", "Dicen que {s_l} {v} {o}."]

## Frase críptica armada con piezas sueltas: casi nunca sale dos veces igual.
func riddle(_ctx: Dictionary = {}) -> String:
	var t: String = ""
	for attempt in 8:
		var f: String = R_FORM[rng.randi() % R_FORM.size()]
		var s: String = R_SUBJ[rng.randi() % R_SUBJ.size()]
		var plural: bool = s.begins_with("Las ") or s.begins_with("Los ") or s.begins_with("Mis ")
		var sl: String = s.substr(0, 1).to_lower() + s.substr(1)
		var v: String = R_VERB[rng.randi() % R_VERB.size()]
		if plural:
			v += "n"
		t = f.format({"s": s, "s_l": sl, "v": v, "o": R_OBJ[rng.randi() % R_OBJ.size()]})
		if not _recent.has(t):
			break
	_recent.append(t)
	if _recent.size() > 16:
		_recent.pop_front()
	return t

func line(topic: String, ctx: Dictionary = {}, tone: int = 0) -> String:
	var pool: Array = POOLS.get(topic, POOLS["generic"])
	var d: Dictionary = {"who": "extraño", "place": "ese lugar", "n": "0"}
	for k: Variant in ctx.keys():
		d[k] = str(ctx[k])
	var best: String = ""
	for attempt in 8:
		var t: String = str(pool[rng.randi() % pool.size()]).format(d)
		if topic.begins_with("obs_") or topic == "generic" or topic.begins_with("verdict_"):
			var tn: int = clampi(tone, 0, 2)
			if rng.randf() < 0.4:
				t = "%s %s" % [OPEN[tn][rng.randi() % OPEN[tn].size()], t]
			if rng.randf() < 0.3:
				t = "%s %s" % [t, TAIL[tn][rng.randi() % TAIL[tn].size()]]
		t = t.replace(" de el ", " del ").replace(" a el ", " al ")
		best = t
		if not _recent.has(t):
			break
	_recent.append(best)
	if _recent.size() > 16:
		_recent.pop_front()
	return best
