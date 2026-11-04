extends RefCounted
## Procedural clockwork geometry for the title screen backdrop.
##
## Everything here is pure mesh building: crossed-out clock wheels (rim with
## teeth + hub + spokes, with real holes between the spokes), pointed escape
## wheels, and simple rods/discs for the pendulum. Visual only, no gameplay.
##
## Gears are built in the XY plane, facing +Z, centred on the origin, so a gear
## can be spun with `rotation.z`.

## A gear's pitch radius for a given tooth count, so two wheels built with the
## same `module` mesh when their centres are `r1 + r2` apart.
static func pitch_radius(teeth: int, module: float) -> float:
	return teeth * module * 0.5


## Build one crossed-out clock wheel.
##   teeth     number of teeth
##   module    tooth size (pitch_radius = teeth * module / 2)
##   thickness plate depth along Z
##   spokes    number of crossings (0 = solid plate with a bore)
##   pointed   true for an escape wheel (thin, raked, pointed teeth)
static func wheel(teeth: int, module: float, thickness: float, spokes: int = 5,
		pointed: bool = false) -> ArrayMesh:
	var r_pitch := pitch_radius(teeth, module)
	var r_tip := r_pitch + module * (1.5 if pointed else 0.6)
	var r_root := r_pitch - module * (0.3 if pointed else 0.75)
	var rim_inner := r_root * 0.87
	var hub_r := maxf(r_tip * 0.17, module * 1.4)
	var bore := hub_r * 0.42

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var outer := _tooth_profile(teeth, r_tip, r_root, pointed)
	if spokes > 0:
		# Rim band: toothed outside, plain circle inside.
		var inner := _resample_circle(outer, rim_inner)
		_band(st, inner, outer, thickness, r_tip)
		# Hub tube.
		var hub_out := _circle(28, hub_r)
		var hub_in := _circle(28, bore)
		_band(st, hub_in, hub_out, thickness * 1.5, r_tip)
		# Spokes between hub and rim. Built by hand rather than with
		# SurfaceTool.append_from(), which drops the vertices already added.
		var span := rim_inner - hub_r * 0.85 + 0.004
		var size := Vector3(span, maxf(r_tip * 0.07, module * 0.8), thickness * 0.8)
		for i in spokes:
			var a := TAU * float(i) / float(spokes)
			var mid := hub_r * 0.85 + span * 0.5
			var xf := Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a) * mid, sin(a) * mid, 0.0))
			_box(st, xf, size, r_tip)
	else:
		var inner2 := _resample_circle(outer, bore)
		_band(st, inner2, outer, thickness, r_tip)

	st.generate_tangents()
	return st.commit()


## A flat disc (clock dial, pendulum bob) facing +Z.
static func disc(radius: float, thickness: float, segments: int = 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := _circle(segments, radius)
	var inner := _circle(segments, radius * 0.0001)
	_band(st, inner, outer, thickness, radius)
	st.generate_tangents()
	return st.commit()


# --- internals ---------------------------------------------------------------

## Outline of a toothed wheel, 5 points per tooth, counter-clockwise.
static func _tooth_profile(teeth: int, r_tip: float, r_root: float, pointed: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var step := TAU / float(teeth)
	# Fractions of one tooth pitch: root, flank up, tip, flank down.
	# A clock escape wheel has long, raked, needle-pointed teeth, not trapezoids.
	var f := [0.0, 0.14, 0.32, 0.68, 0.86] if not pointed else [0.0, 0.50, 0.58, 0.61, 0.64]
	var rr := [r_root, r_root, r_tip, r_tip, r_root]
	for i in teeth:
		var base := step * float(i)
		for k in 5:
			var a: float = base + step * float(f[k])
			var rad: float = rr[k]
			pts.append(Vector2(cos(a) * rad, sin(a) * rad))
	return pts


static func _circle(count: int, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in count:
		var a := TAU * float(i) / float(count)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts


## A circle with one point per point of `like`, at the same angles.
static func _resample_circle(like: PackedVector2Array, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in like:
		pts.append(p.normalized() * radius)
	return pts


## Extrude the area between two closed loops (same point count, same winding)
## into a solid band: front cap, back cap, outer wall, inner wall.
static func _band(st: SurfaceTool, inner: PackedVector2Array, outer: PackedVector2Array,
		thickness: float, uv_scale: float) -> void:
	var n := outer.size()
	var hz := thickness * 0.5
	var solid := inner[0].length() < 0.0001

	for i in n:
		var j := (i + 1) % n
		var o0 := outer[i]
		var o1 := outer[j]
		var i0 := inner[i]
		var i1 := inner[j]

		# Front cap (+Z) and back cap (-Z).
		if solid:
			_tri(st, Vector3(o0.x, o0.y, hz), Vector3(o1.x, o1.y, hz), Vector3(0, 0, hz),
					Vector3.BACK, uv_scale)
			_tri(st, Vector3(o1.x, o1.y, -hz), Vector3(o0.x, o0.y, -hz), Vector3(0, 0, -hz),
					Vector3.FORWARD, uv_scale)
		else:
			_quad(st, Vector3(i0.x, i0.y, hz), Vector3(o0.x, o0.y, hz),
					Vector3(o1.x, o1.y, hz), Vector3(i1.x, i1.y, hz), Vector3.BACK, uv_scale)
			_quad(st, Vector3(i1.x, i1.y, -hz), Vector3(o1.x, o1.y, -hz),
					Vector3(o0.x, o0.y, -hz), Vector3(i0.x, i0.y, -hz), Vector3.FORWARD, uv_scale)

		# Outer wall.
		var e := (o1 - o0)
		var nw := Vector3(e.y, -e.x, 0.0).normalized()
		if nw.dot(Vector3(o0.x, o0.y, 0.0)) < 0.0:
			nw = -nw
		_quad(st, Vector3(o0.x, o0.y, -hz), Vector3(o1.x, o1.y, -hz),
				Vector3(o1.x, o1.y, hz), Vector3(o0.x, o0.y, hz), nw, uv_scale)

		# Inner wall (bore), normal facing in.
		if not solid:
			var ei := (i1 - i0)
			var ni := Vector3(-ei.y, ei.x, 0.0).normalized()
			if ni.dot(Vector3(i0.x, i0.y, 0.0)) > 0.0:
				ni = -ni
			_quad(st, Vector3(i1.x, i1.y, -hz), Vector3(i0.x, i0.y, -hz),
					Vector3(i0.x, i0.y, hz), Vector3(i1.x, i1.y, hz), ni, uv_scale)


## An oriented box, six quads, flat-shaded.
static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, uv_scale: float) -> void:
	var h := size * 0.5
	var corner := func(sx: float, sy: float, sz: float) -> Vector3:
		return xf * Vector3(h.x * sx, h.y * sy, h.z * sz)
	var faces := [
		[Vector3.RIGHT, [[1, -1, -1], [1, 1, -1], [1, 1, 1], [1, -1, 1]]],
		[Vector3.LEFT, [[-1, -1, 1], [-1, 1, 1], [-1, 1, -1], [-1, -1, -1]]],
		[Vector3.UP, [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]]],
		[Vector3.DOWN, [[-1, -1, 1], [1, -1, 1], [1, -1, -1], [-1, -1, -1]]],
		[Vector3.BACK, [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]],
		[Vector3.FORWARD, [[-1, 1, -1], [1, 1, -1], [1, -1, -1], [-1, -1, -1]]],
	]
	for f in faces:
		var nrm: Vector3 = (xf.basis * (f[0] as Vector3)).normalized()
		var p: Array = f[1]
		_quad(st,
				corner.call(p[0][0], p[0][1], p[0][2]),
				corner.call(p[1][0], p[1][1], p[1][2]),
				corner.call(p[2][0], p[2][1], p[2][2]),
				corner.call(p[3][0], p[3][1], p[3][2]),
				nrm, uv_scale)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, s: float) -> void:
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.set_uv(Vector2(v.x, v.y) / (s * 2.0) + Vector2(0.5, 0.5))
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		nrm: Vector3, s: float) -> void:
	_tri(st, a, b, c, nrm, s)
	_tri(st, a, c, d, nrm, s)
