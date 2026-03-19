class_name WaterSystemClass
extends Node
## Singleton providing the authoritative wave-height function.
##
## The exact same math runs in the water shader (water.gdshader) and here,
## so any script can query the precise water surface Y at any world (x, z).
##
## Usage:
##   var y := WaterSystem.get_surface_y(global_position.x, global_position.z)
##   var submerged := global_position.y < y

# These MUST match the shader uniform defaults in water.gdshader
const WAVE_SPEED := 0.4
const WAVE_HEIGHT := 0.25
const WAVE_FREQUENCY := 2.0

const BASE_WATER_Y := 0.08  # water plane offset above WATER_LEVEL (0.0)


func _wave(wx: float, wz: float, time: float) -> float:
	var w1 := sin(wx * WAVE_FREQUENCY + time * WAVE_SPEED * 4.0) * 0.6
	var w2 := sin(wz * WAVE_FREQUENCY * 0.7 + time * WAVE_SPEED * 3.2 + 1.5) * 0.4
	var w3 := sin((wx + wz) * WAVE_FREQUENCY * 0.5 + time * WAVE_SPEED * 2.8) * 0.3
	return (w1 + w2 + w3) * WAVE_HEIGHT


## Returns the world-space Y of the water surface at (wx, wz).
func get_surface_y(wx: float, wz: float) -> float:
	var t := _engine_time()
	return BASE_WATER_Y + _wave(wx, wz, t)


## Returns how deep (positive) or how far above water (negative) a point is.
func get_submersion(world_pos: Vector3) -> float:
	return get_surface_y(world_pos.x, world_pos.z) - world_pos.y


## Convenience: true when the point is at or below the water surface.
func is_submerged(world_pos: Vector3) -> bool:
	return get_submersion(world_pos) > 0.0


## Sample the surface at multiple offsets around a center (for tilt/roll).
## Returns an array of Vector3 surface positions.
func sample_surface_points(center: Vector3, offsets: Array[Vector3]) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for off in offsets:
		var wx := center.x + off.x
		var wz := center.z + off.z
		points.append(Vector3(wx, get_surface_y(wx, wz), wz))
	return points


var _accumulated_time := 0.0


func _process(delta: float) -> void:
	_accumulated_time += delta


## Mirrors the shader's TIME built-in. Both accumulate render-frame
## deltas from _process, so they pause together and never drift.
func _engine_time() -> float:
	return _accumulated_time
