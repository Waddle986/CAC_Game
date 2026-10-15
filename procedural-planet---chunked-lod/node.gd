## Grows the planet through size tiers as the player upgrades their world.
##
## Setup: add a Node with this script as a sibling of Planet and PlanetCamera
## (it finds them automatically), or assign them in the inspector.
## Call upgrade() from your game logic or a UI button.
## Press U while running for a quick test.
class_name WorldProgression
extends Node

signal tier_changed(index: int, tier: Dictionary)

## One entry per world size. "radius" uses the same units as Planet.radius.
## "cost" is a placeholder for your economy; this script never spends anything.
const TIERS: Array[Dictionary] = [
	{"name": "Seedling",  "radius": 4.0,  "cost": 0},
	{"name": "Islet",     "radius": 8.0,  "cost": 100},
	{"name": "Haven",     "radius": 16.0, "cost": 300},
	{"name": "Realm",     "radius": 32.0, "cost": 800},
	{"name": "Homeworld", "radius": 64.0, "cost": 2000},
]

@export var planet: Planet
@export var camera: PlanetCamera
## Mountain height as a fraction of radius. Real Earth is about 0.003;
## small worlds read better with exaggerated relief.
@export var terrain_height_ratio: float = 0.08
## Atmosphere thickness as a fraction of radius.
@export var atmosphere_ratio: float = 0.12
## Camera distance from the planet center, in radii (atmosphere included).
@export var view_distance_factor: float = 1.8
## Press U to upgrade (for testing).
@export var test_key_enabled: bool = true

var tier_index: int = 0
var is_upgrading: bool = false


func _ready() -> void:
	for sibling in get_parent().get_children():
		if planet == null and sibling is Planet:
			planet = sibling
		elif camera == null and sibling is PlanetCamera:
			camera = sibling
	if planet == null or camera == null:
		push_error("WorldProgression: needs a Planet and a PlanetCamera.")
		return
	_apply_tier(0)
	_set_camera_distance(_view_distance(TIERS[0]["radius"]))
	_aim_at_planet()


func _unhandled_input(event: InputEvent) -> void:
	if test_key_enabled and event is InputEventKey and event.pressed \
			and not event.echo and event.keycode == KEY_U:
		upgrade()


# ===========================================================================
#  Public API
# ===========================================================================

func get_tier() -> Dictionary:
	return TIERS[tier_index]


## Returns the next tier, or an empty Dictionary if already at the maximum.
func get_next_tier() -> Dictionary:
	if tier_index >= TIERS.size() - 1:
		return {}
	return TIERS[tier_index + 1]


func can_upgrade() -> bool:
	return not is_upgrading and tier_index < TIERS.size() - 1


## Starts the grow animation. Returns false if already maxed or mid-upgrade.
## Check get_next_tier()["cost"] against the player's money before calling.
func upgrade() -> bool:
	if planet == null or camera == null or not can_upgrade():
		return false
	_run_upgrade()
	return true


# ===========================================================================
#  Internals
# ===========================================================================

func _run_upgrade() -> void:
	is_upgrading = true
	var target := tier_index + 1
	var new_view := _view_distance(TIERS[target]["radius"])
	_aim_at_planet()
	# 1. Pull back so the old world shrinks away.
	await _move_camera_to(new_view * 1.4, 0.8)
	# 2. Swap to the bigger world while it's far away.
	tier_index = target
	_apply_tier(target)
	# 3. Settle in on the new world.
	await _move_camera_to(new_view, 0.9)
	is_upgrading = false
	tier_changed.emit(tier_index, TIERS[tier_index])


## Set the planet's size values and rebuild its mesh.
## (Chunk meshes bake in the radius, so a rebuild is required.)
func _apply_tier(index: int) -> void:
	var r: float = TIERS[index]["radius"]
	planet.radius = r
	planet.terrain_height = r * terrain_height_ratio
	planet.atmosphere_height = r * atmosphere_ratio
	planet.rebuild_planet()


func _view_distance(radius: float) -> float:
	return radius * (1.0 + atmosphere_ratio) * view_distance_factor


func _move_camera_to(distance: float, seconds: float) -> void:
	var start := camera.global_position.distance_to(planet.global_position)
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_camera_distance, start, distance, seconds)
	await tween.finished


## Move the camera along its current direction from the planet center.
func _set_camera_distance(distance: float) -> void:
	var dir := camera.global_position - planet.global_position
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector3(0.4, 0.3, 1.0).normalized()
	camera.global_position = planet.global_position + dir * distance


func _aim_at_planet() -> void:
	var to_planet := planet.global_position - camera.global_position
	if to_planet.length_squared() < 0.0001:
		return
	var up := Vector3.UP
	if absf(to_planet.normalized().dot(up)) > 0.99:
		up = Vector3.RIGHT
	camera.look_at(planet.global_position, up)
