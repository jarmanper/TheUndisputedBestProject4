extends RefCounted
## Extruded 3D lettering built from real glyph outlines.
##
## Godot's TextMesh triangulates the flat faces of a glyph with a convex
## decomposition that cannot handle contours which overlap each other. Cormorant
## Garamond draws "M" as two overlapping strokes and "B" with contours that
## touch, so TextMesh logs "Convex decomposing failed" for both and emits the
## side walls with no faces at all -- the letters come out hollow.
##
## This builds the same thing the honest way: pull the outline from the text
## server, flatten the quadratic curves, run the contours through Clipper
## (Geometry2D) so overlaps merge into clean simple polygons, cut a hairline
## channel out to each counter so the faces can be ear-clipped without hole
## support, then extrude. Visual only -- no gameplay.

## Line segments per quadratic curve. Glyph curves are short; 10 is plenty.
const CURVE_SEGMENTS := 16
## Clipper snaps to a fixed-point grid, so do the boolean work on a magnified
## copy of the outline. Without this, serif brackets collapse into straight lines.
const CLIP_SCALE := 64.0
## Width of the channel cut out to each counter, in magnified units. 4 / 64 is
## 1/16 of a pixel at the glyph's own size: far below anything that can be seen.
const SLIT_WIDTH := 4.0


## One ArrayMesh per character of `text`, each centred on its own ink box
## horizontally and on the whole string's ink box vertically, matching what
## TextMesh does with CENTER/CENTER alignment.
static func build_letters(font: Font, size: int, text: String, depth: float,
		pixel_size: float) -> Array[ArrayMesh]:
	var ts := TextServerManager.get_primary_interface()
	var rids := font.get_rids()
	var meshes: Array[ArrayMesh] = []
	if rids.is_empty():
		push_error("title_glyph_mesh: font has no RID")
		return meshes

	var shapes := []
	var min_y := INF
	var max_y := -INF
	for ch in text:
		var polys := _clean_glyph(ts, rids[0], size, ch)
		shapes.append(polys)
		for poly in polys:
			for p in poly:
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)
	if shapes.is_empty() or min_y > max_y:
		return meshes

	var cy := (min_y + max_y) * 0.5
	for polys in shapes:
		meshes.append(_extrude(polys, cy, depth, pixel_size))
	return meshes


# --- outline -> clean polygons -----------------------------------------------

## Outer rings wound counter-clockwise, counters wound clockwise, all overlaps
## resolved. Coordinates are in CLIP_SCALE units.
static func _clean_glyph(ts: TextServer, rid: RID, size: int, ch: String) -> Array[PackedVector2Array]:
	var empty: Array[PackedVector2Array] = []
	var gi := ts.font_get_glyph_index(rid, size, ch.unicode_at(0), 0)
	var data := ts.font_get_glyph_contours(rid, size, gi)
	if data.is_empty():
		return empty
	var loops := _flatten(data["points"], data["contours"])
	if loops.is_empty():
		return empty

	# The biggest ring decides which winding means "solid"; anything wound the
	# other way is a counter. (TrueType fills by non-zero winding.)
	var best := 0
	var best_area := 0.0
	for i in loops.size():
		var a: float = absf(_signed_area(loops[i]))
		if a > best_area:
			best_area = a
			best = i
	var fill_cw := Geometry2D.is_polygon_clockwise(loops[best])

	var fills: Array[PackedVector2Array] = []
	var counters: Array[PackedVector2Array] = []
	for loop in loops:
		if Geometry2D.is_polygon_clockwise(loop) == fill_cw:
			fills.append(_as_ccw(loop))
		else:
			counters.append(_as_ccw(loop))

	# Union the solid rings: this is what removes M's and K's overlaps.
	var solid: Array[PackedVector2Array] = []
	for f in fills:
		solid = _union(solid, f)
	# Then punch the counters back out.
	for c in counters:
		solid = _subtract(solid, c)

	var result: Array[PackedVector2Array] = []
	for poly in solid:
		# Clipper hands holes back wound the opposite way; keep that convention.
		result.append(poly)
	return result


## Flatten a glyph outline into polylines, magnified by CLIP_SCALE.
## Both bundled fonts have TrueType (glyf) outlines, which are quadratic only,
## so every off-curve point is treated as a quadratic control point.
static func _flatten(pts: PackedVector3Array, ends: PackedInt32Array) -> Array[PackedVector2Array]:
	var loops: Array[PackedVector2Array] = []
	var start := 0
	for e in ends:
		var n := e - start + 1
		if n < 3:
			start = e + 1
			continue
		var pos := PackedVector2Array()
		var on := PackedByteArray()
		for i in n:
			var p := pts[start + i]
			# The text server hands back y pointing down; flip to y-up so the
			# letters are not mirrored and CCW really means CCW.
			pos.append(Vector2(p.x, -p.y) * CLIP_SCALE)
			on.append(1 if int(p.z) == 0 else 0)

		# A TrueType contour may begin on a control point, so start from a real
		# on-curve point; if there is none, every on-curve point is implied.
		var first := -1
		for i in n:
			if on[i] == 1:
				first = i
				break
		var loop := PackedVector2Array()
		if first < 0:
			for i in n:
				loop.append((pos[i] + pos[(i + 1) % n]) * 0.5)
		else:
			var cur := pos[first]
			loop.append(cur)
			var i := 1
			while i <= n:
				var idx := (first + i) % n
				if on[idx] == 1:
					cur = pos[idx]
					loop.append(cur)
					i += 1
					continue
				var c := pos[idx]
				var nidx := (first + i + 1) % n
				var tip: Vector2
				if on[nidx] == 1:
					tip = pos[nidx]
					i += 2
				else:
					# Two controls in a row: the on-curve point between them is
					# implied at their midpoint.
					tip = (c + pos[nidx]) * 0.5
					i += 1
				for s in range(1, CURVE_SEGMENTS + 1):
					var t := float(s) / float(CURVE_SEGMENTS)
					loop.append(cur.lerp(c, t).lerp(c.lerp(tip, t), t))
				cur = tip
		if loop.size() >= 3:
			loops.append(loop)
		start = e + 1
	return loops


static func _union(acc: Array[PackedVector2Array], poly: PackedVector2Array) -> Array[PackedVector2Array]:
	if acc.is_empty():
		# Self-union: cleans a single ring that crosses itself.
		var self_clean: Array[PackedVector2Array] = []
		for r in Geometry2D.merge_polygons(poly, poly):
			self_clean.append(r)
		return self_clean
	var out: Array[PackedVector2Array] = []
	var merged_any := false
	for a in acc:
		var res := Geometry2D.merge_polygons(a, poly)
		# One polygon back means the two actually joined.
		if res.size() == 1 and not merged_any:
			merged_any = true
			out.append(res[0])
		elif not merged_any:
			for r in res:
				out.append(r)
			merged_any = true
		else:
			out.append(a)
	if not merged_any:
		out.append(poly)
	return out


static func _subtract(acc: Array[PackedVector2Array], poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for a in acc:
		for r in Geometry2D.clip_polygons(a, poly):
			out.append(r)
	return out


# --- polygons -> mesh ---------------------------------------------------------

static func _extrude(polys: Array[PackedVector2Array], cy: float, depth: float,
		pixel_size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if polys.is_empty():
		return st.commit()

	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for p in polys:
		if Geometry2D.is_polygon_clockwise(p):
			holes.append(p)
		else:
			outers.append(p)

	# Ink box, so the glyph can be centred and UVs normalised.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in polys:
		for v in p:
			lo = lo.min(v)
			hi = hi.max(v)
	var span: Vector2 = (hi - lo).max(Vector2(0.001, 0.001))
	var origin := Vector2((lo.x + hi.x) * 0.5, cy)
	var k := pixel_size / CLIP_SCALE
	var hz := depth * 0.5

	var to_world := func(v: Vector2, z: float) -> Vector3:
		return Vector3((v.x - origin.x) * k, (v.y - origin.y) * k, z)
	var uv_of := func(v: Vector2) -> Vector2:
		return (v - lo) / span

	# Faces: cut a hairline channel out to each counter so the result is a
	# simple polygon, then ear-clip it. The channel is only in the flat face;
	# the side walls below are built from the real outlines.
	var face: Array[PackedVector2Array] = []
	for o in outers:
		face.append(o)
	for h in holes:
		var seed: Array[PackedVector2Array] = [_as_ccw(h)]
		for kp in _union(seed, _slit(h, hi.y)):
			face = _subtract(face, kp)
	for poly in face:
		if Geometry2D.is_polygon_clockwise(poly):
			continue
		var idx := Geometry2D.triangulate_polygon(poly)
		var i := 0
		while i + 2 < idx.size():
			var tri: Array[Vector2] = [poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]]]
			# Front (+Z) then back (-Z), wound opposite ways.
			for v in tri:
				st.set_normal(Vector3.BACK)
				st.set_uv(uv_of.call(v))
				st.add_vertex(to_world.call(v, hz))
			for j in [2, 1, 0]:
				st.set_normal(Vector3.FORWARD)
				st.set_uv(uv_of.call(tri[j]))
				st.add_vertex(to_world.call(tri[j], -hz))
			i += 3

	# Side walls, from the uncut outlines. Normals are averaged across shallow
	# joins so the curved strokes read as curves, and kept flat at corners.
	for poly in polys:
		var n := poly.size()
		var edge: Array[Vector3] = []
		for i in n:
			var d: Vector2 = poly[(i + 1) % n] - poly[i]
			# Outward for a CCW ring; for a CW counter this points into the
			# counter, which is also away from the solid. Same formula.
			edge.append(Vector3(d.y, -d.x, 0.0).normalized() if d.length_squared() > 1e-9 else Vector3.ZERO)
		var smooth: Array[Vector3] = []
		for i in n:
			var prev: Vector3 = edge[(i - 1 + n) % n]
			var here: Vector3 = edge[i]
			# ~50 degrees: below that it is a curve, above it is a corner.
			smooth.append((prev + here).normalized() if prev.dot(here) > 0.64 else Vector3.ZERO)

		for i in n:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % n]
			if edge[i] == Vector3.ZERO:
				continue
			var na: Vector3 = smooth[i] if smooth[i] != Vector3.ZERO else edge[i]
			var nb: Vector3 = smooth[(i + 1) % n] if smooth[(i + 1) % n] != Vector3.ZERO else edge[i]
			var quad: Array[Vector3] = [
				to_world.call(a, -hz), to_world.call(b, -hz),
				to_world.call(b, hz), to_world.call(a, hz),
			]
			var qn: Array[Vector3] = [na, nb, nb, na]
			var uvs: Array[Vector2] = [uv_of.call(a), uv_of.call(b), uv_of.call(b), uv_of.call(a)]
			for j in [0, 1, 2, 0, 2, 3]:
				st.set_normal(qn[j])
				st.set_uv(uvs[j])
				st.add_vertex(quad[j])

	st.generate_tangents()
	return st.commit()


## A hairline rectangle from the top of a counter up past the top of the glyph.
static func _slit(hole: PackedVector2Array, top: float) -> PackedVector2Array:
	var p := hole[0]
	for v in hole:
		if v.y > p.y:
			p = v
	var w := SLIT_WIDTH * 0.5
	return PackedVector2Array([
		Vector2(p.x - w, p.y - SLIT_WIDTH),
		Vector2(p.x + w, p.y - SLIT_WIDTH),
		Vector2(p.x + w, top + SLIT_WIDTH * 4.0),
		Vector2(p.x - w, top + SLIT_WIDTH * 4.0),
	])


static func _as_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if not Geometry2D.is_polygon_clockwise(poly):
		return poly
	var out := poly.duplicate()
	out.reverse()
	return out


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
