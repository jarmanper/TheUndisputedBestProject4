class_name TimbukFx
## Small helpers shared by the gameplay mechanics: tick timers, spawn effect
## scenes and talk to the GameState autoload without a hard dependency on it.


## Floating-point slack for timer boundaries. Subtracting deltas that sum to
## exactly a timer's length leaves a residue of up to ~1e-15 on the positive
## side (0.6 - 0.599 - 0.001 is 8.7e-19, not 0), which would hold an ability on
## cooldown for one extra frame and make an 8 s mark last 8 s plus a frame.
const TIMER_EPSILON := 1e-9


## Ticks `timer` down by `delta`, snapping to exactly 0.0 once what is left is
## only that residue. Every cooldown and duration in the game goes through this
## so the assignment's exact timings land on the frame they should.
static func tick(timer: float, delta: float) -> float:
	var left := timer - delta
	return 0.0 if left <= TIMER_EPSILON else left



## Instances an effect scene from scenes/effects/ at `where`.
## one_shot = true frees it when its vfx_player duration is done.
static func spawn(tree: SceneTree, path: String, where: Vector3, one_shot := true, basis := Basis.IDENTITY) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var fx: Node3D = load(path).instantiate()
	if one_shot:
		fx.set("autoplay", false)
		fx.set("free_when_done", true)
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	parent.add_child(fx)
	fx.global_transform = Transform3D(basis, where)
	if one_shot and fx.has_method("play"):
		fx.play()
	return fx


## Returns the GameState autoload, or null if it isn't registered yet.
static func game_state(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("GameState")


static func state_call(tree: SceneTree, method: String, args := []) -> Variant:
	var gs := game_state(tree)
	if gs and gs.has_method(method):
		return gs.callv(method, args)
	return null


## Basis whose +Y axis points along `normal` (impact_sparks / decals face +Y).
static func basis_from_normal(normal: Vector3) -> Basis:
	var n := normal.normalized()
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(n).normalized()
	var z := x.cross(n).normalized()
	return Basis(x, n, z)
