class_name LensDef
extends Resource
## Pattern, spread and focus of the beam (GDD §4.2).
##
## Per-cell power = laser power × focus ÷ (beam area in cells).
## A wide lens spreads power thin; a pin lens concentrates it.

enum Pattern { CIRCLE, LINE, RING, SCATTER }

@export var name: String = "Lens"
@export var pattern: Pattern = Pattern.CIRCLE
## Radius of the pattern in world units.
@export var spread: float = 1.6
## Concentration factor.
@export var focus: float = 1.0
## Sample count for LINE / RING / SCATTER (CIRCLE is one disc of radius `spread`).
@export var sample_points: int = 8
## Radius of each sample disc for LINE / RING / SCATTER.
@export var sample_radius: float = 0.9


## Sample offsets on the tangent plane (x,y) with the disc radius in z.
func samples() -> PackedVector3Array:
	var out := PackedVector3Array()
	match pattern:
		Pattern.CIRCLE:
			out.append(Vector3(0, 0, spread))
		Pattern.LINE:
			var n := maxi(sample_points, 2)
			for i in n:
				out.append(Vector3(lerpf(-spread, spread, float(i) / (n - 1)), 0, sample_radius))
		Pattern.RING:
			var n := maxi(sample_points, 3)
			for i in n:
				var a := TAU * i / n
				out.append(Vector3(cos(a) * spread, sin(a) * spread, sample_radius))
		Pattern.SCATTER:
			var n := maxi(sample_points, 1)
			for i in n:
				var a := randf() * TAU
				var r := sqrt(randf()) * spread
				out.append(Vector3(cos(a) * r, sin(a) * r, sample_radius))
	return out


## Beam footprint in world units².
func area() -> float:
	match pattern:
		Pattern.CIRCLE:
			return PI * spread * spread
		Pattern.LINE:
			return 2.0 * spread * 2.0 * sample_radius + PI * sample_radius * sample_radius
		_:
			return maxi(sample_points, 1) * PI * sample_radius * sample_radius
