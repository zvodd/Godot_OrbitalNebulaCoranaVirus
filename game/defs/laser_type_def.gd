class_name LaserTypeDef
extends Resource
## What the beam can get through and how deep it focuses (GDD §4.2).

@export var name: String = "Laser"
## Total beam power. The lens spreads it over the cells it covers.
@export var power: float = 10.0
## Focal distance from the satellite. Cells closer to the core than
## (orbit_radius - reach) cannot be cut.
@export var reach: float = 30.0
@export var fuel_per_sec: float = 1.0
@export var beam_color: Color = Color(1.0, 0.5, 0.2)
