# CEREBRO DE LA ISLA: documento de diseño técnico

Proyecto: juego 3D en **Godot 4.x, GDScript**. Sin LLM: todo con variables, curvas y reglas.
Uso: documento de contexto para el copiloto. Leelo completo antes de proponer cambios.

---

## 0. Reglas de trabajo (importante)

- Antes de escribir código, **proponé el enfoque y esperá confirmación**.
- **Cambiá solo lo necesario.** No reescribas scripts enteros ni regeneres lo que ya funciona.
- Una pieza por vez, en el orden de la sección 10. No avances a la siguiente sin que la anterior esté probada.
- No crees archivos, escenas ni assets que no se pidieron.
- Todo valor numérico va en `const` o `@export`, nunca "hardcodeado" en medio de la lógica (hay que poder tunear sin tocar código).
- Todo sistema debe poder mostrarse en un **overlay de debug** (tecla F3): emociones, tensión, fase, puntajes de acciones.

---

## 1. Concepto

La protagonista **es la isla**, no el jugador. Es un NPC vivo, único y omnipresente que:

- **Observa** al náufrago y recuerda lo que hace.
- **Siente** (confianza, enojo, miedo, curiosidad).
- **Decide** qué hacer: asustar, dañar, generar clima, ayudar, acompañar o no hacer nada.
- **Aprende entre vidas**: son 7 vidas; cada una hereda y profundiza la personalidad de la anterior.
- Final: el jugador aprende a convivir. Al morir en la vida 7 se convierte en la isla y el ciclo reinicia.

Objetivo de sensación: que parezca que la isla **piensa, recuerda y tiene intención**, no que tira dados.

---

## 2. Arquitectura: dos cerebros + memoria

```
        ┌──────────────── MEMORIA (persistente) ────────────────┐
        │ contadores, mapa de calor, patrones, personalidad     │
        └───────────────▲───────────────────────────┬───────────┘
                        │ registra                  │ lee
   JUGADOR ──eventos──► OBSERVA ──► EMOCIONES ──► DIRECTOR DE TENSIÓN (macro)
                                         │                │ fase + tensión
                                         ▼                ▼
                                   DECISIÓN (micro: utilidad con curvas)
                                         │
                                         ▼
                                   ACCIONES (mundo)
```

- **Macro (Director):** decide el *ritmo*. Cuándo apretar, cuándo soltar, cuándo callar.
- **Micro (Decisión):** dentro de lo que el director permite, elige *qué* hacer según emociones y contexto.
- **La isla no hace trampa:** no usa la posición exacta del jugador a cada frame. Trabaja con zonas, rastros recientes y patrones aprendidos. Eso la hace justa y creíble.

Estructura sugerida (autoloads): `Isla` (hub), `IslaMemoria`, `IslaEmociones`, `IslaDirector`, `IslaDecision`. Pueden ser un solo autoload con módulos si es más simple, pero separar las responsabilidades.

---

## 3. Memoria y emociones (base)

**Memoria** (guardada entre partidas en Resource/JSON):
- Contadores: árboles cortados, fuegos, animales cazados, ofrendas, plantaciones, cuidados, tiempo corriendo, tiempo quieto/contemplando, tiempo explorando.
- **Mapa de calor por zonas:** `zona -> {daño, cuidado, visitas}`.
- **Cola de eventos recientes:** `{tipo, zona, timestamp, intensidad}` (últimos ~60 s), usada para reacciones con retraso.
- **Patrones:** conteo de transiciones (ej. "de zona A va a zona B de noche 7 de 10 veces") para anticiparse.

**Emociones** (0.0 a 1.0): `confianza`, `enojo`, `miedo`, `curiosidad`.
- Cada una tiene `base` (personalidad, persiste entre vidas) y decae hacia su base con el tiempo.
- Los eventos las mueven con deltas **con rendimiento decreciente**: cuanto más alta está, menos sube (evita saturación en 1.0, que es una causa típica de comportamiento repetitivo).
- Señal `emocion_cambiada(nombre, valor)`.

---

## 4. DIRECTOR DE TENSIÓN (el sistema más importante)

Una variable global `tension` (0.0 a 1.0) que mide **cuánta presión ejerce la isla sobre el jugador ahora mismo**. Genera picos y valles: lo que más rompe la repetición.

### 4.1 Fases (ciclo)

| Fase | Qué pasa | Tensión | Duración (azar en rango) |
|---|---|---|---|
| `CALMA` | Acciones neutras o amables. El jugador respira. | 0.0 – 0.3 | 30 – 90 s |
| `ACUMULACION` | La isla sube la presión de a poco. Señales y avisos. | sube hasta el umbral | hasta llegar al pico |
| `PICO` | Se permiten las acciones más intensas. | ≥ umbral_pico | 5 – 15 s |
| `RETIRADA` | La isla **se retira a propósito**. Silencio casi total. | baja rápido | 20 – 40 s |

Ciclo: `CALMA → ACUMULACION → PICO → RETIRADA → CALMA`.

El silencio de `RETIRADA` es una herramienta de miedo, no un hueco: el jugador espera lo que viene.

### 4.2 Qué mueve la tensión

- **Sube** (en ACUMULACION): `velocidad = base + enojo*k1 + miedo*k2 - confianza*k3`.
- **Sube por eventos**: el jugador daña la isla, se acerca a una zona de alto daño, es de noche, está lejos del refugio.
- **Baja** por: tiempo, cuidado/ofrendas, contemplación, refugio, fase RETIRADA.
- **Modulado por personalidad:** si `confianza` es alta, `umbral_pico` baja (picos suaves), CALMA dura más y el ciclo puede derivar a la fase `CONVIVENCIA` (ver 4.3). Si `enojo` es alto, picos más altos y más frecuentes.

### 4.3 Fase extra: CONVIVENCIA

Cuando `confianza` supera un valor alto sostenido, el director **deja de generar picos hostiles** y entra en `CONVIVENCIA`: tensión baja y estable, la isla ofrece recompensas y acompaña. Sin este camino de vuelta, solo existiría el miedo. Si el jugador traiciona la confianza (daño grave), se sale de CONVIVENCIA con un pico fuerte: la traición pesa.

### 4.4 Cómo filtra a la decisión

Cada acción del catálogo declara una `intensidad` (0–1). El director solo habilita acciones con `intensidad <= tension + margen`. En PICO se habilita todo; en RETIRADA solo las de intensidad mínima.

### 4.5 Esqueleto (adaptar, no copiar a ciegas)

```gdscript
extends Node
class_name IslaDirector

enum Fase { CALMA, ACUMULACION, PICO, RETIRADA, CONVIVENCIA }

signal fase_cambiada(fase: Fase)
signal tension_cambiada(valor: float)

@export var umbral_pico_base: float = 0.85
@export var velocidad_subida_base: float = 0.02   # por segundo
@export var velocidad_bajada_retirada: float = 0.08

var fase: Fase = Fase.CALMA
var tension: float = 0.1
var _tiempo_en_fase: float = 0.0
var _duracion_fase: float = 45.0

func _process(delta: float) -> void:
    _tiempo_en_fase += delta
    match fase:
        Fase.CALMA:
            tension = move_toward(tension, 0.15, delta * 0.05)
            if _tiempo_en_fase >= _duracion_fase:
                _ir_a(Fase.ACUMULACION)
        Fase.ACUMULACION:
            tension += _velocidad_subida() * delta
            if tension >= _umbral_pico():
                _ir_a(Fase.PICO)
        Fase.PICO:
            if _tiempo_en_fase >= _duracion_fase:
                _ir_a(Fase.RETIRADA)
        Fase.RETIRADA:
            tension = move_toward(tension, 0.05, delta * velocidad_bajada_retirada)
            if _tiempo_en_fase >= _duracion_fase:
                _ir_a(Fase.CALMA)
        Fase.CONVIVENCIA:
            tension = move_toward(tension, 0.1, delta * 0.05)
    tension = clampf(tension, 0.0, 1.0)
    tension_cambiada.emit(tension)

func _velocidad_subida() -> float:
    var e = Isla.emociones   # ajustar a tu estructura
    return maxf(0.0, velocidad_subida_base + e.enojo * 0.03 + e.miedo * 0.02 - e.confianza * 0.03)

func _umbral_pico() -> float:
    return umbral_pico_base - Isla.emociones.confianza * 0.25

func _ir_a(nueva: Fase) -> void:
    fase = nueva
    _tiempo_en_fase = 0.0
    _duracion_fase = _duracion_para(nueva)   # azar en rango según tabla 4.1
    fase_cambiada.emit(nueva)

func intensidad_maxima_permitida() -> float:
    match fase:
        Fase.PICO: return 1.0
        Fase.RETIRADA: return 0.15
        Fase.CONVIVENCIA: return 0.3
        _: return clampf(tension + 0.15, 0.0, 1.0)
```

---

## 5. CURVAS DE RESPUESTA (decisión por utilidad)

Cada acción recibe un puntaje. Cada **consideración** toma una variable (0–1), la pasa por una **curva** (`Curve` de Godot, editable en el inspector, guardada como Resource) y devuelve un valor 0–1. Los resultados se multiplican o promedian.

**Por qué curvas y no sumas lineales:** una suma lineal da puntajes parecidos siempre. Una curva permite que el miedo *casi no pese* hasta 0.6 y luego pese fuerte, o que algo importe solo en cierto rango. Ahí nace la personalidad.

### Consideraciones típicas
1. **Emoción relevante** (ej. `enojo` para tormenta, `confianza` para regalo).
2. **Encaje con la tensión:** qué tan cerca está la `intensidad` de la acción de la `tension` actual (curva campana).
3. **Zona:** calor de daño/cuidado de la zona del jugador.
4. **Momento:** hora del día, clima actual, distancia al refugio.
5. **Novedad** (sección 6).
6. **Eventos recientes** (sección 7).

### Recurso de acción

```gdscript
extends Resource
class_name AccionIsla

enum Tipo { HOSTIL, NEUTRA, AMABLE }

@export var id: StringName
@export var tipo: Tipo
@export_range(0.0, 1.0) var intensidad: float = 0.5
@export var cooldown: float = 30.0
@export var telegrafia: float = 3.0          # segundos de aviso antes de ejecutar
@export var curva_emocion: Curve              # emoción -> utilidad
@export var emocion_clave: StringName         # "enojo", "confianza", ...
@export var curva_tension: Curve              # diferencia(intensidad, tension) -> utilidad
@export var peso_base: float = 1.0
```

### Selección

```gdscript
func puntuar(a: AccionIsla, ctx: Dictionary) -> float:
    var u := a.peso_base
    u *= a.curva_emocion.sample(ctx.emociones[a.emocion_clave])
    u *= a.curva_tension.sample(1.0 - absf(a.intensidad - ctx.tension))
    u *= _factor_novedad(a)
    u *= _factor_evento_reciente(a, ctx)
    u *= _factor_zona(a, ctx)
    return u

func elegir(candidatas: Array[AccionIsla], ctx: Dictionary) -> AccionIsla:
    # 1) filtrar por director y cooldown
    # 2) puntuar todas
    # 3) quedarse con las 3 mejores
    # 4) azar ponderado entre esas 3 (no siempre la ganadora)
    pass
```

La acción `nada` (no hacer nada, silencio) también puntúa y debe poder ganar seguido, sobre todo en RETIRADA.

---

## 6. Novedad: que la isla "se aburra" de repetir

- Cada acción guarda `ultima_vez` y un contador de usos recientes.
- `factor_novedad = curva(tiempo_desde_ultimo_uso)`: justo después de usarla vale ~0.1 y se recupera gradualmente a 1.0.
- Penalización extra si la **misma categoría** (ej. todo clima) se repite dos veces seguidas.
- Resultado: la isla prueba cosas distintas y parece creativa.

---

## 7. Reacciones con intención y retraso

El mundo vivo **responde a lo que hiciste, en el lugar y momento preciso, con un retraso**. Ese retraso es lo que se siente como pensamiento.

- Cada evento relevante entra a la cola reciente con zona y timestamp.
- La isla crea una **reacción pendiente** con un delay de 10–40 s (más corto si el enojo es alto).
- Ejemplos:
  - Cortaste un árbol → 20 s después el viento sopla fuerte **desde esa zona**.
  - Dejaste una ofrenda → rato después aparece un fruto o un claro cerca.
  - Siempre vas a la costa de noche → una noche la niebla ya está ahí esperándote (anticipación por patrones).
- La reacción puede ser proporcional, desproporcionada (rencor) o inexistente: el azar controlado mantiene la intriga.

---

## 8. Acciones, consecuencias y recompensas

**Regla de oro: toda acción hostil telegrafía.** Hay un aviso previo (sonido, viento, sombra, cambio de luz) de `telegrafia` segundos. El jugador debe sentir miedo, no injusticia. El daño real es acotado y recuperable salvo en momentos de final de vida.

### 8.1 Catálogo

**HOSTILES (consecuencias malas)**
| Acción | Intensidad | Efecto |
|---|---|---|
| Sonidos inquietantes | 0.2 | Susto, sube miedo del jugador |
| Niebla densa | 0.4 | Pierde visibilidad |
| Vegetación que se cierra | 0.45 | Bloquea o desvía un camino |
| Criatura merodeadora | 0.6 | Acecho sin ataque directo |
| Tormenta | 0.7 | Visibilidad, ruido, frío |
| Fuente de agua / frutos "se agotan" | 0.7 | Presión de supervivencia |
| Derrumbe o trampa natural leve | 0.8 | Daño menor |
| Ataque directo de criatura | 0.9 | Daño real (solo en PICO y enojo alto) |

**NEUTRAS (solo disfrutar la isla)**
| Acción | Intensidad | Efecto |
|---|---|---|
| Nada / silencio | 0.0 | Pausa pura |
| Viento suave, oleaje | 0.05 | Ambiente |
| Aves, luciérnagas, fauna a lo lejos | 0.05 | Vida |
| Cambio de luz (atardecer especial) | 0.1 | Belleza |
| Sombras y movimientos que "te siguen" | 0.15 | Sensación de ser observado |

**AMABLES (recompensas)**
| Acción | Intensidad | Efecto |
|---|---|---|
| Brisa fresca / lluvia suave | 0.1 | Alivio, baja tensión |
| Fruto o agua cerca | 0.2 | Recurso |
| Animal amigable que acompaña | 0.25 | Compañía |
| Camino despejado hacia algo útil | 0.3 | Pista de exploración |
| Claro con refugio | 0.35 | Descanso seguro |
| Curación lenta (zona segura) | 0.4 | Recuperación |
| Regalo especial / revelación de secreto de la isla | 0.5 | Hito de vínculo |

### 8.2 Comportamiento del jugador → emociones → consecuencia

| Acción del jugador | Efecto en la isla | Consecuencia típica |
|---|---|---|
| Cortar árboles en exceso, incendios | +enojo, -confianza, +calor de daño en la zona | Reacción hostil localizada, picos más altos |
| Cazar sin necesidad | +enojo | Fauna esquiva, criaturas merodeando |
| Dejar ofrendas, plantar, cuidar | +confianza, -enojo, +calor de cuidado | Recompensas amables, tensión más baja |
| Cosechar con medida / respetar fauna | +confianza leve | Recursos más abundantes |
| Explorar sin dañar | +curiosidad | La isla revela rutas y secretos |
| **Quedarse quieto a contemplar** | +confianza, baja tensión | Neutras hermosas, animales se acercan |
| Huir siempre / mostrar miedo | +miedo percibido | La isla puede "jugar" más con ese miedo |
| Traicionar la confianza (daño tras vínculo alto) | Enojo se dispara, sale de CONVIVENCIA | Pico fuerte, rencor que dura vidas |

### 8.3 Vínculo (medidor de convivencia)

Variable `vinculo` 0–100, que sube con cuidado y contemplación y baja con daño. Hitos (25 / 50 / 75 / 100) desbloquean recompensas permanentes dentro de la vida: refugio, compañero animal, revelaciones. Es el hilo que lleva al final de convivencia.

### 8.4 Perdón y rencor

- La confianza se recupera **más lento** de lo que se pierde (el rencor pesa).
- El rencor tiene decaimiento entre vidas, pero deja marca en la personalidad base.
- Siempre debe existir un camino de reconciliación, aunque largo.

---

## 9. Las 7 vidas como arco de aprendizaje

Cada vida **desbloquea una capacidad nueva** de la isla y hereda la personalidad (emociones base desplazadas según cómo jugó el náufrago).

| Vida | La isla aprende a… |
|---|---|
| 1 | Observar (solo registra, reacciones simples) |
| 2 | Imitar: repite en el entorno lo que hiciste (ruidos, patrones) |
| 3 | Anticipar: usa patrones de recorrido para adelantarse |
| 4 | Reaccionar con intención y retraso (sección 7 completa) |
| 5 | Tener humor y juego: acciones ambiguas, ni buenas ni malas |
| 6 | Comunicar: el entorno "habla" (señales, rutas, advertencias) |
| 7 | Decidir el final según el acumulado de convivencia |

**Personalidad persistente:** al morir, las emociones base se desplazan según el balance de esa vida (destructivo → más enojo/menos confianza base; cuidadoso → lo contrario). Guardar `vida_actual` y personalidad en Resource/JSON.

**Final de vida 7:** calcular `convivencia_total` (suma ponderada de vínculo por vida y traiciones). Si supera el umbral → final de convivencia (el jugador se vuelve isla en paz). Si no → final de conflicto. En ambos casos, reinicio del ciclo con la personalidad resultante.

---

## 10. Orden de implementación (un paso por vez)

1. **Overlay de debug (F3):** emociones, tensión, fase, top de puntajes.
2. **Director de tensión** (sección 4) con acciones de prueba que solo imprimen en consola.
3. **Curvas de respuesta + recurso `AccionIsla`** (sección 5), reemplazando el puntaje lineal actual.
4. **Novedad** (sección 6).
5. **Cola de eventos y reacciones con retraso** (sección 7).
6. **Telegrafía + 3 acciones reales** (niebla, sonido 3D, mover vegetación), una de cada tipo (hostil, neutra, amable).
7. **Vínculo y recompensas** (sección 8).
8. **Vidas y personalidad persistente** (sección 9).
9. **Final** y balance de números.

Después de cada paso: probar con el overlay, ajustar valores en el inspector, recién entonces seguir.

---

## 11. Criterios de "esto se siente vivo"

- En 10 minutos de juego hay **al menos un pico y un silencio** claramente distintos.
- La isla **no repite** la misma acción dos veces seguidas salvo que sea muy coherente.
- El jugador puede **identificar causa y efecto** ("corté eso y ahora pasa esto") sin que sea mecánico.
- Hay momentos donde **no pasa nada** y se siente intencional.
- Comportarse bien cambia de verdad el tono del mundo, no solo un número.
