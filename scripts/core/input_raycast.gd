class_name InputRaycast
extends RefCounted
## Converts screen-space clicks to grid coordinates by performing
## a mathematical ray-cylinder intersection.

var camera: Camera3D
var cylinder_map: CylinderMap

func _init(cam: Camera3D, cyl: CylinderMap) -> void:
	camera = cam
	cylinder_map = cyl

## Convert a screen position to a grid coordinate on the cylinder.
## Returns Vector2i(-1, -1) if the ray misses the cylinder.
func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var uv = screen_to_uv(screen_pos)
	if uv.x < 0.0:
		return Vector2i(-1, -1)
	var pixel_x: float = uv.x * cylinder_map.map_width * cylinder_map.tile_size
	var pixel_y: float = uv.y * cylinder_map.map_height * cylinder_map.tile_size
	return GridUtils.pixel_to_grid(Vector2(pixel_x, pixel_y))

## Convert a screen position to UV coordinates on the cylinder surface.
## Returns Vector2(-1, -1) if the ray misses.
func screen_to_uv(screen_pos: Vector2) -> Vector2:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	return _ray_cylinder_intersection(ray_origin, ray_dir)

## Analytical ray-cylinder intersection.
## Cylinder: axis Y, centered at origin, radius R, height H.
## Solves x^2 + z^2 = R^2 for the ray, then checks Y bounds.
func _ray_cylinder_intersection(origin: Vector3, dir: Vector3) -> Vector2:
	var R: float = cylinder_map.cylinder_radius
	var H: float = cylinder_map.cylinder_height

	# Quadratic coefficients for the infinite cylinder x^2 + z^2 = R^2
	var a: float = dir.x * dir.x + dir.z * dir.z
	var b: float = 2.0 * (origin.x * dir.x + origin.z * dir.z)
	var c: float = origin.x * origin.x + origin.z * origin.z - R * R

	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return Vector2(-1.0, -1.0)

	var sqrt_disc: float = sqrt(discriminant)
	var t1: float = (-b - sqrt_disc) / (2.0 * a)
	var t2: float = (-b + sqrt_disc) / (2.0 * a)

	# Pick the nearest positive intersection (front face of cylinder)
	var t: float = t1 if t1 > 0.001 else t2
	if t < 0.001:
		return Vector2(-1.0, -1.0)

	var hit: Vector3 = origin + dir * t

	# Check if hit is within the cylinder's finite height
	if hit.y < -H / 2.0 or hit.y > H / 2.0:
		return Vector2(-1.0, -1.0)

	# Convert hit point to UV
	var theta: float = atan2(hit.z, hit.x)
	if theta < 0.0:
		theta += TAU

	var u: float = fposmod(1.0 - theta / TAU, 1.0)
	var v: float = (H / 2.0 - hit.y) / H  # top=0, bottom=1

	return Vector2(u, v)
