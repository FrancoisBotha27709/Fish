class_name WaterManager
extends MeshInstance3D

const MAX_RIPPLES := 16
const MAX_HULLS := 16
const GK := 9.8 / TAU
const ANG: Array[float] = [0.0, 24.0, 61.0, -37.0, 104.0, -73.0]
const LEN: Array[float] = [85.0, 52.0, 22.0, 13.0, 6.0, 3.2]
const STEEP: Array[float] = [0.8, 0.7, 0.45, 0.35, 0.22, 0.14]
const AMP: Array[float] = [1.0, 0.6, 0.32, 0.2, 0.1, 0.05]
const SPD: Array[float] = [0.9, 1.05, 1.3, 1.5, 1.9, 2.2]

@export var follow_target: Node3D
@export var meters_per_unit := 1.0
@export var mesh_vertex_spacing := 1.25

@export_group("Ripples")
@export var ripple_lifetime := 5.0
@export var ripple_speed := 4.0
@export var ripple_wavelength := 1.5
@export var ripple_width := 3.0
@export var ripple_amplitude := 0.4

@export_group("Waves")
@export var swell_amplitude := 1.2
@export var swell_wavelength_scale := 0.5
@export var chop_amplitude := 0.6
@export var wave_speed := 1.0
@export var wave_choppiness := 0.6
@export var wind_direction_deg := 30.0
@export var wave_direction_jitter := 12.0
@export var chop_patchiness := 0.5

@export_group("Large Scale Variation")
@export var domain_warp_amount := 15.0
@export var domain_warp_scale := 0.004
@export var domain_warp_speed := 0.02

@export_group("Sea State")
@export var enable_sea_state_variation := true
@export var sea_state_min := 0.6
@export var sea_state_max := 1.0
@export var sea_state_period := 120.0
@export var sea_state_jitter := 0.15
@export var sea_state_speed_influence := 0.15

@export_group("Foam")
@export var foam_res := 512
@export var foam_window := 256.0
@export var foam_fold_decay := 3.5
@export var foam_contact_decay := 1.2
@export var foam_fold_threshold := 0.75
@export var foam_fold_softness := 0.55

var _mat: ShaderMaterial
var _mats: Array[ShaderMaterial] = []
var _fm: Array[ShaderMaterial] = []
var _fvp: Array[SubViewport] = []
var _fi := 0
var _forg := Vector2.ZERO
var _t := 0.0
var _wt := 0.0
var _ph := 0.0
var _cur_swell := 0.0
var _cur_chop := 0.0
var _cur_spd := 1.0
var _dir := PackedVector2Array()
var _par := PackedVector4Array()
var _ck := PackedFloat32Array()
var _ca := PackedFloat32Array()
var _cw := PackedFloat32Array()
var _cm := Vector4(1, 1, 1, 0)
var _rm := Vector4(1, 1, 1, 0)
var _warp := Vector2.ZERO
var _rx := 0.0
var _rz := 0.0
var _rs := 0.0
var _rk := 1.0
var _rw := 1.0
var _rip: Array[Vector4] = []
var _rd := PackedVector4Array()
var _rip_dirty := false
var _ha := PackedVector4Array()
var _hb := PackedVector4Array()
var _hn := 0
var _hf := 0
var _bn := 0
var _bd := PackedVector4Array()
var _bc := PackedVector4Array()
var _br := PackedVector4Array()

func _ready() -> void:
	_mat = material_override as ShaderMaterial
	if _mat == null and mesh:
		_mat = mesh.surface_get_material(0) as ShaderMaterial
	if _mat == null:
		push_warning("WaterManager: no ShaderMaterial")
		return
	_mats.append(_mat)
	_dir.resize(6); _par.resize(6)
	_ck.resize(6); _ca.resize(6); _cw.resize(6)
	_rd.resize(MAX_RIPPLES); _ha.resize(MAX_HULLS); _hb.resize(MAX_HULLS)
	_cur_swell = swell_amplitude; _cur_chop = chop_amplitude; _cur_spd = wave_speed
	_pack()
	_foam_init()
	for k in ["ripple_lifetime", "ripple_speed", "ripple_wavelength", "ripple_width", "ripple_amplitude", "meters_per_unit", "mesh_vertex_spacing", "domain_warp_amount", "domain_warp_scale", "domain_warp_speed", "chop_patchiness", "wind_direction_deg"]:
		_all(k, get(k))
	_all("foam_size", foam_window)
	for m in _fm:
		m.set_shader_parameter("win_size", foam_window)
		m.set_shader_parameter("fold_thr", foam_fold_threshold)
		m.set_shader_parameter("fold_soft", foam_fold_softness)

func _process(dt: float) -> void:
	if _mat == null:
		return
	_t += dt
	_sea(dt)
	_wt += dt * _cur_spd
	if follow_target:
		global_position.x = snappedf(follow_target.global_position.x, mesh_vertex_spacing)
		global_position.z = snappedf(follow_target.global_position.z, mesh_vertex_spacing)
	_pack()
	_all("wave_time", _wt)
	_all("sim_time", _t)
	_all("swell_amplitude", _cur_swell)
	_all("chop_amplitude", _cur_chop)
	_all("wave_dir", _dir)
	_all("wave_par", _par)
	var d := false
	while not _rip.is_empty() and _t - _rip[0].z > ripple_lifetime:
		_rip.remove_at(0)
		d = true
	if d or _rip_dirty:
		_rip_dirty = false
		for i in MAX_RIPPLES:
			_rd[i] = _rip[i] if i < _rip.size() else Vector4.ZERO
		_mat.set_shader_parameter("ripple_data", _rd)
		_mat.set_shader_parameter("ripple_count", _rip.size())
	if Engine.get_physics_frames() - _hf > 4:
		_hn = 0
	_foam_step(dt)

func _all(k: StringName, v: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(k, v)

func _sea(dt: float) -> void:
	if not enable_sea_state_variation:
		_cur_swell = swell_amplitude; _cur_chop = chop_amplitude; _cur_spd = wave_speed
		return
	_ph += dt * TAU / maxf(sea_state_period, 1.0)
	var s := clampf(lerpf(0.5 + 0.5 * sin(_ph), clampf(_fbm(Vector2(_ph * 0.15, 91.7)) / 0.9375, 0.0, 1.0), sea_state_jitter), 0.0, 1.0)
	var m := lerpf(sea_state_min, sea_state_max, s)
	_cur_swell = swell_amplitude * m
	_cur_chop = chop_amplitude * m
	_cur_spd = wave_speed * lerpf(1.0, m, sea_state_speed_influence)

func _pack() -> void:
	var wind := deg_to_rad(wind_direction_deg)
	var ms := mesh_vertex_spacing
	for i in 6:
		var a := deg_to_rad(ANG[i] + (_fbm(Vector2(i * 17.17, _wt * 0.015)) - 0.5) * 2.0 * wave_direction_jitter) + wind
		_dir[i] = Vector2(cos(a), sin(a))
		var wl := LEN[i]
		var amp := AMP[i] * _cur_chop
		if i < 2:
			wl = maxf(wl * swell_wavelength_scale, 0.5)
			amp = AMP[i] * _cur_swell * smoothstep(ms * 2.0, ms * 3.5, wl)
		_par[i] = Vector4(wl, SPD[i], amp, STEEP[i] * wave_choppiness)

func _foam_init() -> void:
	var sh: Shader = load(get_script().resource_path.get_base_dir() + "/water_foam.gdshader")
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(foam_res, foam_res)
		vp.use_hdr_2d = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var m := ShaderMaterial.new()
		m.shader = sh
		var r := ColorRect.new()
		r.size = Vector2(foam_res, foam_res)
		r.material = m
		vp.add_child(r)
		add_child(vp)
		_fvp.append(vp)
		_fm.append(m)
		_mats.append(m)
	_fm[0].set_shader_parameter("prev", _fvp[1].get_texture())
	_fm[1].set_shader_parameter("prev", _fvp[0].get_texture())

func _foam_step(dt: float) -> void:
	var c := global_position
	if follow_target:
		c = follow_target.global_position
	elif get_viewport().get_camera_3d():
		c = get_viewport().get_camera_3d().global_position
	var tx := foam_window / foam_res
	var org := Vector2(snappedf(c.x - foam_window * 0.5, tx), snappedf(c.z - foam_window * 0.5, tx))
	var m := _fm[_fi]
	m.set_shader_parameter("origin", org)
	m.set_shader_parameter("shift", (org - _forg) / foam_window)
	m.set_shader_parameter("decay", Vector2(exp(-foam_fold_decay * dt), exp(-foam_contact_decay * dt)))
	m.set_shader_parameter("hull_a", _ha)
	m.set_shader_parameter("hull_b", _hb)
	m.set_shader_parameter("hull_n", _hn)
	_fvp[_fi].render_target_update_mode = SubViewport.UPDATE_ONCE
	_mat.set_shader_parameter("foam_map", _fvp[_fi].get_texture())
	_mat.set_shader_parameter("foam_origin", org)
	_forg = org
	_fi = 1 - _fi

func set_biomes(n: int, data: PackedVector4Array, chop: PackedVector4Array, ripple: PackedVector4Array, look: PackedVector4Array, tint: PackedVector4Array) -> void:
	_bn = mini(n, data.size())
	_bd = data; _bc = chop; _br = ripple
	_all("biome_count", n)
	_all("biome_data", data)
	_all("biome_chop", chop)
	_all("biome_ripple", ripple)
	_all("biome_look", look)
	_all("biome_tint", tint)

func spawn_ripple(pos: Vector3, strength := 1.0) -> void:
	if _rip.size() >= MAX_RIPPLES:
		_rip.remove_at(0)
	_rip.append(Vector4(pos.x, pos.z, _t, strength))
	_rip_dirty = true

func stamp_hull(pos: Vector3, half: Vector2, axis_x: Vector2, strength: float) -> void:
	var f := Engine.get_physics_frames()
	if f != _hf:
		_hf = f
		_hn = 0
	if _hn < MAX_HULLS:
		_ha[_hn] = Vector4(pos.x, pos.z, maxf(half.x, 0.1), maxf(half.y, 0.1))
		_hb[_hn] = Vector4(axis_x.x, axis_x.y, strength, 0.0)
		_hn += 1

func get_water_height_at(p: Vector2) -> float:
	prep(p)
	return surface(p.x, p.y) + ripples()

func get_wave_height_at(p: Vector2) -> float:
	prep(p)
	return surface(p.x, p.y)

func get_ripple_height_at(p: Vector2) -> float:
	prep(p)
	_rx = p.x; _rz = p.y
	return ripples()

func get_water_world_y(w: Vector3) -> float:
	return global_position.y + get_water_height_at(Vector2(w.x, w.z))

func get_water_normal_at(p: Vector2, e := 1.0) -> Vector3:
	prep(p)
	var a := surface(p.x + e, p.y) + ripples()
	var b := surface(p.x - e, p.y) + ripples()
	var c := surface(p.x, p.y + e) + ripples()
	var d := surface(p.x, p.y - e) + ripples()
	return Vector3(b - a, 2.0 * e, d - c).normalized()

func prep(p: Vector2) -> void:
	_cm = Vector4(1, 1, 1, 0)
	_rm = Vector4(1, 1, 1, 0)
	for i in _bn:
		var d := _bd[i]
		var w := 1.0 - smoothstep(d.z, d.z + maxf(d.w, 0.001), p.distance_to(Vector2(d.x, d.y)))
		if w > 0.001:
			_cm = _cm.lerp(_bc[i], w)
			_rm = _rm.lerp(_br[i], w)
	var s := p * domain_warp_scale
	var t := _wt * domain_warp_speed
	_warp = (Vector2(_fbm(s + Vector2(0.0, t)), _fbm(s + Vector2(5.2, -t))) - Vector2(0.5, 0.5)) * domain_warp_amount
	var pm := lerpf(1.0 - chop_patchiness * 0.7, 1.0 + chop_patchiness * 0.7, _fbm((p + _warp) * 0.015 + Vector2(4.0, 9.0)))
	var ms := mesh_vertex_spacing
	for i in 6:
		var q := _par[i]
		var wl: float
		var a: float
		var sp: float
		if i < 2:
			wl = q.x
			a = q.z * lerpf(1.0, _cm.x, 0.35)
			sp = lerpf(1.0, _cm.z, 0.35)
		else:
			wl = maxf(q.x / maxf(_cm.y, 0.01), 0.5)
			a = q.z * pm * _cm.x * smoothstep(ms * 2.0, ms * 3.5, wl)
			sp = _cm.z
		var k := TAU / wl
		_ck[i] = k
		_ca[i] = a
		_cw[i] = k * sqrt(GK * wl) * q.y * sp
	_rs = ripple_speed * _rm.x
	_rk = TAU / maxf(ripple_wavelength * _rm.y, ms * 3.5)
	_rw = maxf(ripple_width, ms * 2.0)

func surface(x: float, z: float) -> float:
	var rx := x
	var rz := z
	var o := Vector3.ZERO
	for i in 3:
		o = _gerst(rx, rz)
		if i < 2:
			rx = x - o.x
			rz = z - o.z
	_rx = rx
	_rz = rz
	if _cm.w > 0.01:
		var sc := 1.0 / maxf(meters_per_unit, 0.001)
		var tf := 0.03 * maxf(_cm.y, 0.01)
		var fade := smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, 1.0 / maxf(tf, 0.0001) / sc)
		o.y += (_fbm(Vector2(rx + _warp.x, rz + _warp.y) * sc * tf + Vector2(_wt * 0.6, _wt * 0.45)) - 0.5) * _cur_chop * 1.5 * _cm.w * fade
	return o.y

func _gerst(px: float, pz: float) -> Vector3:
	var wx := px + _warp.x
	var wz := pz + _warp.y
	var o := Vector3.ZERO
	for i in 6:
		var d := _dir[i]
		var f := _ck[i] * (d.x * wx + d.y * wz) - _cw[i] * _wt
		var a := _ca[i]
		var sa := _par[i].w * a * cos(f)
		o.x += sa * d.x
		o.z += sa * d.y
		o.y += a * sin(f)
	return o

func ripples() -> float:
	if _rip.is_empty():
		return 0.0
	var sc := 1.0 / maxf(meters_per_unit, 0.001)
	var tot := 0.0
	for r in _rip:
		var age := _t - r.z
		var d := Vector2(_rx - r.x, _rz - r.y).length() * sc
		var fr := age * _rs
		var bx := (d - fr) / (_rw * (1.0 + age * 0.25))
		var band := exp(-bx * bx)
		if band < 0.001:
			continue
		var u := clampf(age / maxf(ripple_lifetime, 0.001), 0.0, 1.0)
		tot += sin((d - fr) * _rk) * ripple_amplitude * _rm.z * r.w * smoothstep(0.0, 0.15, age) * (1.0 - u * u * (3.0 - 2.0 * u)) / sqrt(1.0 + fr * 0.5) * band
	return tot

static func _hash(x: float, y: float) -> float:
	x = fposmod(x, 289.0) * 123.34
	y = fposmod(y, 289.0) * 456.21
	x -= floorf(x)
	y -= floorf(y)
	var d := x * (x + 45.32) + y * (y + 45.32)
	x += d
	y += d
	var m := x * y
	return m - floorf(m)

static func _vn(p: Vector2) -> float:
	var ix := floorf(p.x)
	var iy := floorf(p.y)
	var fx := p.x - ix
	var fy := p.y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_hash(ix, iy), _hash(ix + 1.0, iy), ux), lerpf(_hash(ix, iy + 1.0), _hash(ix + 1.0, iy + 1.0), ux), uy)

static func _fbm(p: Vector2) -> float:
	var v := 0.0
	var a := 0.5
	for i in 4:
		v += a * _vn(p)
		p *= 2.03
		a *= 0.5
	return v
