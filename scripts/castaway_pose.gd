class_name CastawayPose
extends SkeletonModifier3D

## Retoques de pose que se suman a la animación del modelo (agacharse, recoger, comer, beber).
## Se aplica DESPUÉS del AnimationPlayer. Todas las rotaciones son alrededor del eje X del esqueleto
## (el modelo mira hacia +Z en su propio espacio): ángulo positivo = inclinar hacia adelante.

var crouch: float = 0.0     ## 0..1
var act: String = ""        ## "pickup", "eat", "drink" o ""
var act_w: float = 0.0      ## intensidad 0..1 de la acción
var hand_local: Transform3D = Transform3D.IDENTITY   ## mano derecha en espacio del esqueleto, con la pose final
var hold: float = 0.0          ## 0..1: brazo derecho levantado sosteniendo un objeto
var use_w: float = 0.0        ## 0..1: pulso de uso del objeto en mano (un gesto corto)

var lie: float = 0.0           ## 0..1: acostado de costado en posicion fetal (dormir)
var sit: float = 0.0           ## 0..1: sentado (contemplando)
var hold_kind: String = ""     ## "luz", "herramienta", "caña" o "" (cómo se sostiene el objeto)
var hold_kind_w: float = 0.0   ## 0..1: cuánto pesa el matiz del tipo de objeto
var kind_up: float = 0.0       ## desplazamiento suavizado del hombro según el tipo (lo calcula CastawayModel)
var kind_fore: float = 0.0     ## ídem para el antebrazo
var run_w: float = 0.0         ## 0..1: cuánto corre (para el brazo con objeto)

var _idx: Dictionary = {}
var record_idle: bool = false     ## true mientras suena Idle: guarda la pose de los brazos en reposo
var arm_damp: float = 0.0         ## 0..1: cuánto se aquietan los brazos hacia esa pose (caminar tranquilo)
var _arm_rest: Dictionary = {}
const ARM_BONES: Array[String] = ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]

func _bone(sk: Skeleton3D, bone_name: String) -> int:
	if not _idx.has(bone_name):
		_idx[bone_name] = sk.find_bone(bone_name)
	return int(_idx[bone_name])

## Gira un hueso alrededor del eje X del esqueleto (sin importar cómo esté orientado el hueso).
func _rot(sk: Skeleton3D, bone_name: String, angle: float) -> void:
	if absf(angle) < 0.0005:
		return
	var i: int = _bone(sk, bone_name)
	if i < 0:
		return
	var g: Basis = sk.get_bone_global_pose(i).basis
	var par: int = sk.get_bone_parent(i)
	var pb: Basis = sk.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	var nb: Basis = Basis(Vector3.RIGHT, angle) * g
	sk.set_bone_pose_rotation(i, (pb.inverse() * nb).orthonormalized().get_rotation_quaternion())

## Baja o sube un hueso en el eje Y del esqueleto.
func _drop(sk: Skeleton3D, bone_name: String, dy: float) -> void:
	if absf(dy) < 0.0005:
		return
	var i: int = _bone(sk, bone_name)
	if i < 0:
		return
	var g: Transform3D = sk.get_bone_global_pose(i)
	g.origin.y += dy
	var par: int = sk.get_bone_parent(i)
	var pg: Transform3D = sk.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
	sk.set_bone_pose_position(i, (pg.affine_inverse() * g).origin)

func _process_modification() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	for ab: String in ARM_BONES:
		var bi: int = _bone(sk, ab)
		if bi < 0:
			continue
		if record_idle:
			_arm_rest[ab] = sk.get_bone_pose_rotation(bi)
		elif (arm_damp > 0.001 or (hold > 0.001 and ab.ends_with(".R"))) and _arm_rest.has(ab) and act == "":
			var dm: float = arm_damp
			if hold > 0.001 and ab.ends_with(".R"):
				dm = maxf(dm, 0.84 * hold)   # conserva ~16 % de la oscilación al caminar
			var k: float = dm * (1.0 if ab.begins_with("Upper") else 0.95)
			sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi).slerp(_arm_rest[ab], k))
	if hold > 0.001 and act == "":
		var kw: float = hold_kind_w * hold
		_rot(sk, "UpperArm.R", -0.55 * hold - 0.15 * use_w + kind_up * kw + 0.1 * run_w * hold)
		_rot(sk, "LowerArm.R", -1.0 * hold - 0.4 * use_w + kind_fore * kw - 0.25 * run_w * hold)
	var pw: float = act_w if act == "pickup" else 0.0
	var c: float = maxf(crouch, pw * 0.8)
	if c > 0.001:
		_drop(sk, "Body", -1.0 * c)
		for s: String in ["L", "R"]:
			_rot(sk, "UpperLeg." + s, -1.1 * c)
			_rot(sk, "LowerLeg." + s, 1.5 * c)
		_rot(sk, "Abdomen", 0.22 * c)
		_rot(sk, "Torso", 0.22 * c)
		_rot(sk, "Head", -0.2 * c)
	if sit > 0.001:
		_drop(sk, "Body", -1.3 * sit)
		for s2: String in ["L", "R"]:
			_rot(sk, "UpperLeg." + s2, -1.5 * sit)
			_rot(sk, "LowerLeg." + s2, 1.5 * sit)
		_rot(sk, "Abdomen", -0.06 * sit)
		_rot(sk, "Torso", 0.04 * sit)
		_rot(sk, "Head", 0.05 * sit)
	if lie > 0.001:
		for s3: String in ["L", "R"]:
			_rot(sk, "UpperLeg." + s3, -1.75 * lie)
			_rot(sk, "LowerLeg." + s3, 1.9 * lie)
			_rot(sk, "UpperArm." + s3, -0.8 * lie)
			_rot(sk, "LowerArm." + s3, -1.5 * lie)
		_rot(sk, "Abdomen", -0.35 * lie)
		_rot(sk, "Torso", -0.25 * lie)
		_rot(sk, "Head", -0.2 * lie)
	if pw > 0.001:
		_rot(sk, "Abdomen", 0.35 * pw)
		_rot(sk, "Torso", 0.3 * pw)
		for s: String in ["L", "R"]:
			_rot(sk, "UpperArm." + s, -0.9 * pw)
			_rot(sk, "LowerArm." + s, -0.35 * pw)
		_rot(sk, "Head", -0.3 * pw)
	if (act == "eat" or act == "drink") and act_w > 0.001:
		_rot(sk, "UpperArm.R", -0.5 * act_w)
		_rot(sk, "LowerArm.R", -2.0 * act_w)
		_rot(sk, "Head", (-0.3 if act == "drink" else 0.12) * act_w)
	# Mano derecha ya con la pose final (fuera de este modificador, Skeleton3D devuelve la pose sin modificar).
	var hb: int = sk.find_bone("MiddleHand.R")
	if hb >= 0:
		hand_local = sk.get_bone_global_pose(hb)
