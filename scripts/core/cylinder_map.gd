class_name CylinderMap
extends MeshInstance3D
## Generates a 3D cylinder mesh textured with the 2D map SubViewport.
## The cylinder axis is Y. The circumference maps to map_width tiles,
## and the height maps to map_height tiles.

var map_width: int = 80
var map_height: int = 50
var tile_size: int = 64
var cylinder_radius: float = 0.0
var cylinder_height: float = 0.0

func setup(w: int, h: int, viewport: SubViewport) -> void:
	map_width = w
	map_height = h
	tile_size = GridUtils.TILE_SIZE
	# Circumference = map_width so that 1 unit of arc = 1 tile column
	cylinder_radius = float(map_width) / TAU
	# Height = map_height so that 1 unit = 1 tile row
	cylinder_height = float(map_height)
	_build_cylinder_mesh()
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = viewport.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0, mat)

func _build_cylinder_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cols: int = map_width
	var rows: int = map_height

	# Generate vertices: (rows+1) x (cols+1) grid
	# col 0 and col cols share the same position but have u=0 and u=1 (seam)
	for row in range(rows + 1):
		for col in range(cols + 1):
			var u: float = float(col) / float(cols)
			var v: float = float(row) / float(rows)
			var theta: float = (1.0 - u) * TAU
			var x: float = cylinder_radius * cos(theta)
			var z: float = cylinder_radius * sin(theta)
			var y: float = cylinder_height * (0.5 - v)  # top = +H/2, bottom = -H/2
			st.set_normal(Vector3(cos(theta), 0.0, sin(theta)))
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(x, y, z))

	# Generate indices for each quad (two triangles)
	for row in range(rows):
		for col in range(cols):
			var tl: int = row * (cols + 1) + col
			var tr: int = tl + 1
			var bl: int = (row + 1) * (cols + 1) + col
			var br: int = bl + 1
			# Triangle 1: top-left, top-right, bottom-left (CW from outside)
			st.add_index(tl)
			st.add_index(tr)
			st.add_index(bl)
			# Triangle 2: top-right, bottom-right, bottom-left (CW from outside)
			st.add_index(tr)
			st.add_index(br)
			st.add_index(bl)

	mesh = st.commit()
