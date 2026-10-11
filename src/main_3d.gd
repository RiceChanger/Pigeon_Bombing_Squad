extends Node3D

const WORLD_HALF := Vector2(72.0, 108.0)
const PLAYER_ALTITUDE := 13.0
const NEST_POSITIONS := [
	Vector3(-50.0,0.0,82.0),
	Vector3(50.0,0.0,82.0),
	Vector3(0.0,0.0,-88.0)
]
const TARGET_CLUSTER_CENTERS := [
	Vector3(-23.0,0.0,-62.0), Vector3(22.0,0.0,-45.0),
	Vector3(-26.0,0.0,-18.0), Vector3(25.0,0.0,10.0),
	Vector3(-22.0,0.0,38.0), Vector3(21.0,0.0,63.0)
]
const INITIAL_TARGETS_PER_CLUSTER := 4
const MAX_TARGETS := 36
const TARGET_CLUSTER_RADIUS := 7.5
const TARGET_MOVE_MIN := 1.2
const TARGET_MOVE_MAX := 2.2
const COMBO_GRACE_SECONDS := 3.8
const ANGER_PER_HIT := 1.2
const ANGER_PER_DEFEAT := 2.8
const NEST_TRIGGER_RADIUS := 7.0
const NORMAL_HIT_SCORE := 50
const DIRECT_HIT_SCORE := 110
const DIRECT_HIT_RADIUS := 1.45
const SAVE_PATH := "user://pigeon_bombing_3d_save.json"
const EVOLUTION_TYPES := ["rapid", "split", "flock"]

enum ScreenState { TITLE, PLAYING, RESULT }

var state := ScreenState.TITLE
var player_pos := Vector3(0.0, PLAYER_ALTITUDE, 0.0)
var player_velocity := Vector2.ZERO
var drag_active := false
var drag_origin := Vector2.ZERO
var drag_vector := Vector2.ZERO
var score := 0
var hit_count := 0
var combo := 0
var max_combo := 0
var combo_clock := 0.0
var anger := 0.0
var drop_clock := 0.0
var spawn_clock := 0.0
var attack_serial := 0
var target_spawn_serial := 0
var has_flown_out := false
var anger_flash_clock := 0.0
var anger_notice_clock := 0.0
var camera_shake_clock := 0.0
var evolution := {"rapid":0.0, "split":0.0, "flock":0.0}
var evolved := {"rapid":false, "split":false, "flock":false}
var showcase_kind := ""
var showcase_clock := 0.0
var evolution_slow_clock := 0.0
var evolution_banner_clock := 0.0
var last_result := {}
var save_data := {"best":0, "breadcrumbs":0, "lineage":""}
var targets: Array[Dictionary] = []
var poops: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var world_root: Node3D
var actor_root: Node3D
var effect_root: Node3D
var pigeon: Node3D
var pigeon_visual: Node3D
var pigeon_shadow: MeshInstance3D
var left_wing: Node3D
var right_wing: Node3D
var rapid_badge: MeshInstance3D
var split_badge: MeshInstance3D
var flock_left: Node3D
var flock_right: Node3D
var nest_rings: Array[MeshInstance3D] = []
var camera: Camera3D
var ui_root: Control
var score_label: Label
var anger_bar: ColorRect
var anger_notice_label: Label
var combo_label: Label
var nest_label: Label
var evo_bars := {}
var evo_labels := {}
var banner_label: Label
var audio_player: AudioStreamPlayer
var font: Font
var material_cache := {}
var flight_time := 0.0

func _ready() -> void:
	font = preload("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	rng.seed = 4282
	load_save()
	setup_scene()
	build_city()
	show_title()

func setup_scene() -> void:
	world_root = Node3D.new()
	world_root.name = "GroundCity"
	add_child(world_root)
	actor_root = Node3D.new()
	actor_root.name = "GroundTargets"
	add_child(actor_root)
	effect_root = Node3D.new()
	effect_root.name = "AirEffects"
	add_child(effect_root)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#a8d4df")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b9d5d7")
	environment.ambient_light_energy = 0.22
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_color = Color("#fff0c2")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.near = 0.2
	camera.far = 330.0
	add_child(camera)
	pigeon = build_pigeon(false)
	pigeon.scale = Vector3.ONE * 0.48
	add_child(pigeon)
	pigeon_visual=pigeon.get_node("Visual")
	pigeon_shadow = make_cylinder(effect_root,1.7,0.035,Color(0.06,0.10,0.12,0.28),Vector3.ZERO,24)
	pigeon_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui_root)
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	update_player_transform(0.0)

func _process(delta: float) -> void:
	flight_time += delta
	animate_pigeon()
	var simulation_delta := delta
	if evolution_slow_clock > 0.0:
		evolution_slow_clock = maxf(0.0,evolution_slow_clock-delta)
		simulation_delta *= 0.22
	if evolution_banner_clock > 0.0:
		evolution_banner_clock = maxf(0.0,evolution_banner_clock-delta)
		if is_instance_valid(banner_label):
			banner_label.modulate.a = minf(1.0,evolution_banner_clock*3.0)
	if showcase_clock > 0.0:
		showcase_clock -= delta
		if showcase_clock <= 0.0 and showcase_kind != "":
			showcase_evolution(showcase_kind)
			showcase_kind = ""
	if state == ScreenState.PLAYING:
		update_game(simulation_delta)
	update_camera(delta)

func update_camera(delta: float) -> void:
	var desired := player_pos + Vector3(0.0,22.0,30.0)
	if camera_shake_clock>0.0:
		camera_shake_clock=maxf(0.0,camera_shake_clock-delta)
		var shake_strength:=camera_shake_clock*0.65
		desired+=Vector3(sin(flight_time*61.0)*shake_strength,cos(flight_time*47.0)*shake_strength*0.45,0.0)
	camera.position = camera.position.lerp(desired,1.0-exp(-5.0*delta))
	camera.look_at(player_pos+Vector3(0.0,-13.0,-7.0),Vector3.UP)

func animate_pigeon() -> void:
	var flap := sin(flight_time*9.2)*0.52
	left_wing.rotation.z = -0.18-flap
	right_wing.rotation.z = 0.18+flap
	left_wing.rotation.x=sin(flight_time*9.2+0.7)*0.10
	right_wing.rotation.x=sin(flight_time*9.2+0.7)*0.10
	var strain:=0.0
	if state==ScreenState.PLAYING and drop_clock<0.20:strain=(0.20-drop_clock)/0.20
	if is_instance_valid(pigeon_visual):
		pigeon_visual.scale=Vector3(1.0+strain*0.05,1.0-strain*0.08,1.0+strain*0.10)
	pigeon.position.y = PLAYER_ALTITUDE+sin(flight_time*3.2)*0.24
	var nest_pulse := 1.0+sin(flight_time*4.0)*0.08
	for ring in nest_rings:
		if is_instance_valid(ring):ring.scale = Vector3(nest_pulse,1.0,nest_pulse)

func update_player_transform(delta: float) -> void:
	pigeon.position.x = player_pos.x
	pigeon.position.z = player_pos.z
	if player_velocity.length()>0.15:
		pigeon.rotation.y = lerp_angle(pigeon.rotation.y,atan2(player_velocity.x,player_velocity.y),1.0-exp(-7.0*maxf(delta,0.001)))
	pigeon.rotation.z=lerpf(pigeon.rotation.z,clampf(-player_velocity.x*0.025,-0.34,0.34),1.0-exp(-5.0*maxf(delta,0.001)))
	pigeon_shadow.position = Vector3(player_pos.x,0.04,player_pos.z)
	var shadow_scale := 0.72+sin(flight_time*3.2)*0.03
	pigeon_shadow.scale = Vector3(shadow_scale,1.0,shadow_scale)

func update_game(delta: float) -> void:
	anger_flash_clock=maxf(0.0,anger_flash_clock-delta)
	anger_notice_clock=maxf(0.0,anger_notice_clock-delta)
	combo_clock = maxf(0.0,combo_clock-delta)
	if combo_clock<=0.0:
		combo=0
	var speed := 22.5
	var desired := drag_vector.limit_length(1.0)*speed
	player_velocity = player_velocity.lerp(desired,1.0-exp(-8.0*delta))
	if not drag_active:
		player_velocity = player_velocity.move_toward(Vector2.ZERO,speed*8.0*delta)
	player_pos.x = clampf(player_pos.x+player_velocity.x*delta,-WORLD_HALF.x,WORLD_HALF.x)
	player_pos.z = clampf(player_pos.z+player_velocity.y*delta,-WORLD_HALF.y,WORLD_HALF.y)
	player_pos.y = PLAYER_ALTITUDE
	update_player_transform(delta)
	drop_clock -= delta
	if drop_clock<=0.0:
		perform_auto_drop()
		drop_clock += current_drop_interval()
	spawn_clock -= delta
	if spawn_clock<=0.0:
		spawn_target()
		spawn_clock += rng.randf_range(1.2,1.8)
	update_poops(delta)
	update_targets(delta)
	update_effects(delta)
	update_hud()
	var nest_distance := distance_xz(player_pos,nearest_nest_position())
	if nest_distance>11.0:
		has_flown_out=true
	if has_flown_out and nest_distance<NEST_TRIGGER_RADIUS:
		finish_sortie(true)
	elif anger>=100.0:
		finish_sortie(false)

func current_drop_interval() -> float:
	var interval := 1.28
	if bool(evolved.rapid):
		interval = 0.66
	elif String(save_data.lineage)=="rapid":
		interval -= 0.15
	return interval

func current_radius() -> float:
	var radius := 5.3
	if bool(evolved.split):
		radius += 2.0
	elif String(save_data.lineage)=="split":
		radius += 0.65
	return radius

func perform_auto_drop() -> void:
	attack_serial += 1
	play_drop_whoosh()
	var offsets := [-2.7,0.0,2.7]
	if bool(evolved.split):
		offsets=[-5.2,-2.6,0.0,2.6,5.2]
	for offset in offsets:
		spawn_poop(player_pos+Vector3(float(offset),0.0,0.0),0.76)
	if bool(evolved.flock) or (String(save_data.lineage)=="flock" and attack_serial%3==0):
		spawn_poop(player_pos+Vector3(-6.4,0.0,1.8),0.72)
		spawn_poop(player_pos+Vector3(6.4,0.0,1.8),0.72)

func spawn_poop(origin: Vector3,duration: float) -> void:
	var target := Vector3(clampf(origin.x,-WORLD_HALF.x,WORLD_HALF.x),0.35,clampf(origin.z,-WORLD_HALF.y,WORLD_HALF.y))
	var visual := make_sphere(effect_root,0.46,Color("#f7f1d1"),origin,8,4)
	visual.scale=Vector3(0.8,1.25,0.8)
	var marker := make_cylinder(effect_root,1.35,0.025,Color(1.0,0.92,0.36,0.38),Vector3(target.x,0.055,target.z),24)
	var shadow := make_cylinder(effect_root,0.42,0.018,Color(0.08,0.10,0.11,0.34),Vector3(target.x,0.075,target.z),20)
	marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	poops.append({"origin":origin,"target":target,"time":0.0,"duration":duration,"node":visual,"marker":marker,"shadow":shadow})

func update_poops(delta: float) -> void:
	for index in range(poops.size()-1,-1,-1):
		var poop:=poops[index]
		poop.time+=delta
		var progress:=clampf(float(poop.time)/float(poop.duration),0.0,1.0)
		poop.node.position=Vector3(poop.target.x,lerpf(float(poop.origin.y),float(poop.target.y),progress*progress),poop.target.z)
		poop.node.rotation.y+=delta*6.0
		var pulse:=1.0+sin(progress*PI*5.0)*0.08
		poop.marker.scale=Vector3(pulse,1.0,pulse)
		poop.shadow.scale=Vector3(0.55+progress*1.10,1.0,0.55+progress*1.10)
		if progress>=1.0:
			impact_poop(poop.target)
			poop.node.queue_free()
			poop.marker.queue_free()
			poop.shadow.queue_free()
			poops.remove_at(index)

func impact_poop(position: Vector3) -> void:
	var radius:=current_radius()
	var hits:=0
	var direct_hits:=0
	var raw_points:=0
	var hit_center:=Vector3.ZERO
	for target in targets:
		var distance:=distance_xz(target.pos,position)
		if distance<=radius+float(target.radius):
			var is_direct:=distance<=DIRECT_HIT_RADIUS
			target.dirt+=70.0 if is_direct else 46.0
			target.reaction=1.20 if is_direct else 0.82
			target.reaction_kind="direct" if is_direct else "normal"
			target.dirt_node.visible=true
			target.reaction_icon.visible=true
			target.reaction_icon.text="!!" if is_direct else "!"
			target.reaction_icon.modulate=Color("#ff785e") if is_direct else Color("#ffca4a")
			spawn_hit_splash(target.pos,is_direct)
			hits+=1
			hit_center+=target.pos
			if is_direct:
				direct_hits+=1
				raw_points+=DIRECT_HIT_SCORE
			else:raw_points+=NORMAL_HIT_SCORE
	if hits>0:
		hit_count+=hits
		combo+=1
		max_combo=maxi(max_combo,combo)
		combo_clock=COMBO_GRACE_SECONDS
		var multiplier:=minf(3.0,1.0+floorf(float(combo-1)/3.0)*0.25)
		var awarded_points:=int(float(raw_points)*multiplier)
		score+=awarded_points
		spawn_score_popup(hit_center/float(hits),awarded_points,hits,direct_hits)
		camera_shake_clock=maxf(camera_shake_clock,0.24 if direct_hits>0 else 0.14)
		add_anger(float(hits)*ANGER_PER_HIT,"命中")
		if direct_hits>0:
			gain_evolution("rapid",24.0*direct_hits)
		if hits>=2:
			gain_evolution("split",34.0+8.0*(hits-2))
		if combo>=3:
			gain_evolution("flock",17.0+float(combo))
		play_impact_sound(direct_hits>0,hits)
		play_reaction_sound(direct_hits>0,hits)
	else:
		combo=0
	var splat:=make_cylinder(effect_root,radius,0.045,Color(0.93,0.90,0.62,0.88),Vector3(position.x,0.10,position.z),18)
	splat.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.append({"node":splat,"time":0.52,"max_time":0.52,"kind":"splat"})
	if hits==0:play_tone(215.0,0.055)

func spawn_hit_splash(position: Vector3,is_direct: bool) -> void:
	var splash:=Node3D.new()
	splash.position=position+Vector3(0,1.0,0)
	effect_root.add_child(splash)
	var droplet_count:=8 if is_direct else 5
	for index in droplet_count:
		var angle:=TAU*float(index)/float(droplet_count)
		var droplet:=make_sphere(splash,0.24 if is_direct else 0.18,Color("#fff8dc"),Vector3(cos(angle)*0.75,rng.randf_range(0.2,1.5),sin(angle)*0.75),7,4)
		droplet.scale=Vector3(0.75,1.35,0.75)
	effects.append({"node":splash,"time":0.50,"max_time":0.50,"kind":"splash"})

func spawn_score_popup(position: Vector3,points: int,hits: int,direct_hits: int) -> void:
	var popup:=Label3D.new()
	popup.font=font
	popup.font_size=52
	popup.outline_size=12
	popup.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	popup.pixel_size=0.016
	popup.no_depth_test=true
	popup.render_priority=120
	popup.modulate=Color("#ffdc58") if direct_hits>0 else Color.WHITE
	popup.text="直撃！ +%d"%points if direct_hits>0 else "+%d"%points
	if hits>1:popup.text+="  ×%d"%hits
	popup.position=position+Vector3(0,4.6,0)
	effect_root.add_child(popup)
	effects.append({"node":popup,"time":1.0,"max_time":1.0,"kind":"popup"})

func add_anger(amount: float,reason: String) -> void:
	if amount<=0.0:return
	anger=minf(100.0,anger+amount)
	anger_flash_clock=0.42
	anger_notice_clock=1.1
	if is_instance_valid(anger_notice_label):
		anger_notice_label.text="怒り +%.1f（%s）"%[amount,reason]
		anger_notice_label.modulate=Color.WHITE

func gain_evolution(kind: String,amount: float) -> void:
	if bool(evolved[kind]):
		return
	evolution[kind]=minf(100.0,float(evolution[kind])+amount)
	if float(evolution[kind])>=100.0:
		trigger_evolution(kind)

func trigger_evolution(kind: String) -> void:
	if bool(evolved[kind]):
		return
	evolved[kind]=true
	evolution[kind]=100.0
	evolution_slow_clock=0.62
	evolution_banner_clock=1.35
	showcase_kind=kind
	showcase_clock=0.64
	var names:={"rapid":"連射進化！","split":"分裂進化！","flock":"群れ進化！"}
	if is_instance_valid(banner_label):
		banner_label.text=names[kind]
		banner_label.modulate=Color.WHITE
	var colors:={"rapid":Color("#70e6ff"),"split":Color("#ffcf62"),"flock":Color("#d19cff")}
	var wave:=make_cylinder(effect_root,1.2,0.10,colors[kind],player_pos,32)
	effects.append({"node":wave,"time":0.75,"max_time":0.75,"kind":"evolution"})
	apply_evolution_visuals()
	play_tone(880.0,0.24)
	Input.vibrate_handheld(90)

func showcase_evolution(kind: String) -> void:
	if kind=="rapid":
		for row in 3:
			for x in [-2.7,0.0,2.7]:spawn_poop(player_pos+Vector3(float(x),0.0,-float(row)*1.5),0.50+row*0.06)
	elif kind=="split":
		for x in [-7.0,-3.5,0.0,3.5,7.0]:spawn_poop(player_pos+Vector3(float(x),0.0,0.0),0.62)
	else:
		for x in [-8.0,-5.0,-2.5,0.0,2.5,5.0,8.0]:spawn_poop(player_pos+Vector3(float(x),0.0,rng.randf_range(-2,2)),0.58)

func apply_evolution_visuals() -> void:
	rapid_badge.visible=bool(evolved.rapid)
	split_badge.visible=bool(evolved.split)
	flock_left.visible=bool(evolved.flock)
	flock_right.visible=bool(evolved.flock)
	var wing_scale:=1.2 if bool(evolved.split) else 1.0
	left_wing.scale=Vector3(wing_scale,1.0,wing_scale)
	right_wing.scale=Vector3(wing_scale,1.0,wing_scale)

func distance_xz(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func nearest_nest_position() -> Vector3:
	var nearest:Vector3=NEST_POSITIONS[0]
	var best_distance:=distance_xz(player_pos,nearest)
	for index in range(1,NEST_POSITIONS.size()):
		var candidate:Vector3=NEST_POSITIONS[index]
		var candidate_distance:=distance_xz(player_pos,candidate)
		if candidate_distance<best_distance:
			nearest=candidate
			best_distance=candidate_distance
	return nearest

func nest_direction_arrow(target: Vector3) -> String:
	var offset:=Vector2(target.x-player_pos.x,target.z-player_pos.z)
	if absf(offset.x)>absf(offset.y)*1.5:return "→" if offset.x>0.0 else "←"
	if absf(offset.y)>absf(offset.x)*1.5:return "↓" if offset.y>0.0 else "↑"
	if offset.y>0.0:return "↘" if offset.x>0.0 else "↙"
	return "↗" if offset.x>0.0 else "↖"

func spawn_target(cluster_index: int=-1) -> void:
	if targets.size()>=MAX_TARGETS:return
	if cluster_index<0 or cluster_index>=TARGET_CLUSTER_CENTERS.size():
		cluster_index=rng.randi_range(0,TARGET_CLUSTER_CENTERS.size()-1)
	var home:Vector3=TARGET_CLUSTER_CENTERS[cluster_index]
	var angle:=rng.randf_range(0.0,TAU)
	var distance:=rng.randf_range(1.2,TARGET_CLUSTER_RADIUS)
	var position:=home+Vector3(cos(angle)*distance,0.0,sin(angle)*distance)
	var serial:=target_spawn_serial
	target_spawn_serial+=1
	var type:="special" if serial%9==0 else ("bike" if serial%5==0 else "human")
	var max_dirt:=104.0 if type=="special" else (82.0 if type=="bike" else 58.0)
	var radius:=1.55 if type!="human" else 1.1
	var node:=build_ground_character(type,serial)
	actor_root.add_child(node)
	node.position=position
	var bar:MeshInstance3D=node.get_node("DirtMeter/Fill")
	var visual:Node3D=node.get_node("Visual")
	var velocity:=Vector2.from_angle(rng.randf_range(0,TAU))*rng.randf_range(TARGET_MOVE_MIN,TARGET_MOVE_MAX)
	targets.append({"pos":position,"home":home,"vel":velocity,"dirt":0.0,"max_dirt":max_dirt,"type":type,"radius":radius,"turn":rng.randf_range(0.8,2.4),"node":node,"bar":bar,"visual":visual,"dirt_node":visual.get_node("Dirt"),"reaction_icon":visual.get_node("ReactionIcon"),"left_arm":visual.get_node("LeftArm"),"right_arm":visual.get_node("RightArm"),"left_leg":visual.get_node("LeftLeg"),"right_leg":visual.get_node("RightLeg"),"reaction":0.0,"reaction_kind":"","walk_phase":rng.randf_range(0,TAU)})

func update_targets(delta: float) -> void:
	for index in range(targets.size()-1,-1,-1):
		var target:=targets[index]
		target.walk_phase+=delta*6.0
		var reacting:=float(target.reaction)>0.0
		if reacting:
			target.reaction=maxf(0.0,float(target.reaction)-delta)
			var reaction_length:=1.20 if target.reaction_kind=="direct" else 0.82
			var reaction_progress:=1.0-float(target.reaction)/reaction_length
			var reaction_wave:=sin(clampf(reaction_progress,0.0,1.0)*PI)
			target.visual.rotation.x=-reaction_wave*(0.72 if target.reaction_kind=="direct" else 0.42)
			target.visual.position.y=reaction_wave*(0.48 if target.reaction_kind=="direct" else 0.24)
			target.left_arm.rotation.z=-reaction_wave*1.35
			target.right_arm.rotation.z=reaction_wave*1.35
			target.left_leg.rotation.x=0.0
			target.right_leg.rotation.x=0.0
			if target.reaction<=0.0:
				target.reaction_icon.visible=false
		else:
			target.visual.rotation.x=lerpf(target.visual.rotation.x,0.0,minf(1.0,delta*10.0))
			target.visual.position.y=lerpf(target.visual.position.y,0.0,minf(1.0,delta*10.0))
			target.left_arm.rotation.z=lerpf(target.left_arm.rotation.z,0.0,minf(1.0,delta*9.0))
			target.right_arm.rotation.z=lerpf(target.right_arm.rotation.z,0.0,minf(1.0,delta*9.0))
			var walk:=sin(float(target.walk_phase))*0.42
			target.left_leg.rotation.x=walk
			target.right_leg.rotation.x=-walk
			target.left_arm.rotation.x=-walk*0.72
			target.right_arm.rotation.x=walk*0.72
			target.turn-=delta
			if target.turn<=0.0:
				target.turn=rng.randf_range(1.0,3.0)
				target.vel=target.vel.rotated(rng.randf_range(-0.85,0.85))
			var offset:=Vector2(float(target.pos.x-target.home.x),float(target.pos.z-target.home.z))
			if offset.length()>TARGET_CLUSTER_RADIUS:
				var homeward:=-offset.normalized()*rng.randf_range(TARGET_MOVE_MIN,TARGET_MOVE_MAX)
				target.vel=target.vel.lerp(homeward,0.72)
			target.pos.x=clampf(target.pos.x+target.vel.x*delta,-42.0,42.0)
			target.pos.z=clampf(target.pos.z+target.vel.y*delta,-98.0,92.0)
		target.node.position=target.pos
		if target.vel.length()>0.1:target.node.rotation.y=atan2(target.vel.x,target.vel.y)
		var ratio:=clampf(float(target.dirt)/float(target.max_dirt),0.0,1.0)
		target.bar.scale.x=maxf(0.001,ratio)
		target.bar.position.x=-0.72+0.72*ratio
		if float(target.dirt)>=float(target.max_dirt) and float(target.reaction)<=0.0:
			var bonus:=420 if target.type=="special" else (190 if target.type=="bike" else 120)
			score+=bonus
			add_anger(ANGER_PER_DEFEAT,"退場")
			var puff:=make_sphere(effect_root,1.4,Color(1,1,1,0.72),target.pos+Vector3(0,1.2,0),8,4)
			effects.append({"node":puff,"time":0.5,"max_time":0.5,"kind":"puff"})
			target.node.queue_free()
			targets.remove_at(index)

func update_effects(delta: float) -> void:
	for index in range(effects.size()-1,-1,-1):
		var effect:=effects[index]
		effect.time-=delta
		var progress:=1.0-clampf(float(effect.time)/float(effect.max_time),0.0,1.0)
		if effect.kind=="splat":effect.node.scale=Vector3.ONE*(0.65+progress*0.45)
		elif effect.kind=="evolution":effect.node.scale=Vector3.ONE*(1.0+progress*8.0)
		elif effect.kind=="popup":
			effect.node.position.y+=delta*1.7
			effect.node.modulate.a=clampf(float(effect.time)*2.2,0.0,1.0)
		elif effect.kind=="splash":
			effect.node.position.y+=delta*1.1
			effect.node.scale=Vector3.ONE*(1.0+progress*0.8)
		elif effect.kind!="audio":
			effect.node.position.y+=delta*2.4
			effect.node.scale=Vector3.ONE*(1.0+progress*0.6)
		if effect.time<=0.0:
			effect.node.queue_free()
			effects.remove_at(index)

func strongest_lineage() -> String:
	var best_kind:="rapid"
	var best_value:=-1.0
	for kind in EVOLUTION_TYPES:
		var value:=float(evolution[kind])+(100.0 if bool(evolved[kind]) else 0.0)
		if value>best_value:
			best_value=value
			best_kind=kind
	return best_kind

func finish_sortie(success: bool) -> void:
	if state==ScreenState.RESULT:return
	state=ScreenState.RESULT
	drag_active=false
	drag_vector=Vector2.ZERO
	var pending_reward:=int(score/120)
	var confirmed_reward:=pending_reward if success else 0
	var inherited:=String(save_data.lineage)
	if success:
		inherited=strongest_lineage()
		save_data.lineage=inherited
		save_data.breadcrumbs=int(save_data.breadcrumbs)+confirmed_reward
		save_data.best=maxi(int(save_data.best),score)
		save_game()
	last_result={"success":success,"score":score,"hits":hit_count,"combo":max_combo,"reward":confirmed_reward,"lost":pending_reward-confirmed_reward,"lineage":inherited}
	build_result_ui()
	play_tone(720.0 if success else 105.0,0.24)

func clear_dynamic_nodes() -> void:
	for target in targets:
		if is_instance_valid(target.node):target.node.queue_free()
	for poop in poops:
		for key in ["node","marker","shadow"]:
			if is_instance_valid(poop[key]):poop[key].queue_free()
	for effect in effects:
		if is_instance_valid(effect.node):effect.node.queue_free()
	targets.clear()
	poops.clear()
	effects.clear()

func build_city() -> void:
	make_box(world_root,Vector3(160,0.5,230),Color("#b8d57d"),Vector3(0,-0.25,0))
	var asphalt:=Color("#6d777d")
	make_box(world_root,Vector3(28,0.12,230),asphalt,Vector3(0,0.02,0))
	make_box(world_root,Vector3(16,0.12,196),asphalt,Vector3(-34,0.025,-3))
	make_box(world_root,Vector3(16,0.12,196),asphalt,Vector3(34,0.025,-3))
	for z in [-64.0,-22.0,24.0,68.0]:
		make_box(world_root,Vector3(144,0.13,18),asphalt,Vector3(0,0.03,z))
	for center in TARGET_CLUSTER_CENTERS:
		make_cylinder(world_root,10.5,0.16,Color("#d9d4bd"),center+Vector3(0,0.10,0),28)
	for z in range(-102,106,15):make_box(world_root,Vector3(0.45,0.05,6.0),Color(1,1,1,0.72),Vector3(0,0.10,float(z)))
	for x in [-34.0,34.0]:
		for z in range(-92,92,18):make_box(world_root,Vector3(0.40,0.05,6.0),Color(1,1,1,0.55),Vector3(x,0.10,float(z)))
	for z in [-86.0,-56.0,-26.0,6.0,38.0,70.0]:build_shop_row(z)
	for z in range(-84,85,28):
		var left_tree:=Vector3(-49,0,float(z)+6)
		var right_tree:=Vector3(49,0,float(z)-6)
		if not position_near_any_nest(left_tree,20.0):build_tree(left_tree)
		if not position_near_any_nest(right_tree,20.0):build_tree(right_tree)
	build_hero_block()
	for index in NEST_POSITIONS.size():build_nest(NEST_POSITIONS[index],index)

func build_hero_block() -> void:
	var pavement:=Color("#d8cbbb")
	make_box(world_root,Vector3(35,0.20,36),pavement,Vector3(49,0.14,10))
	for tile_x in range(34,66,4):make_box(world_root,Vector3(0.06,0.025,36),Color("#bbaea0"),Vector3(float(tile_x),0.26,10))
	for tile_z in range(-8,29,4):make_box(world_root,Vector3(35,0.025,0.06),Color("#bbaea0"),Vector3(49,0.26,float(tile_z)))
	make_box(world_root,Vector3(13,7.0,23),Color("#bf8a62"),Vector3(64,3.5,10))
	make_box(world_root,Vector3(0.45,5.3,21),Color("#59443a"),Vector3(57.3,3.0,10))
	for z in [-0.5,6.0,12.5,19.0]:
		make_box(world_root,Vector3(0.12,2.7,4.6),Color("#8fd0dc"),Vector3(57.0,3.1,z))
		make_box(world_root,Vector3(0.18,0.20,5.0),Color("#f3e3c1"),Vector3(56.8,4.85,z))
	for z in range(0,22,4):
		var awning_color:=Color("#d75f59") if (z/4)%2==0 else Color("#f3dfc6")
		var awning:=make_box(world_root,Vector3(3.8,0.20,3.5),awning_color,Vector3(55.5,5.2,float(z)))
		awning.rotation.z=-0.12
	make_box(world_root,Vector3(0.45,2.8,6.2),Color("#433833"),Vector3(56.8,7.4,9.0))
	var shop_sign:=Label3D.new()
	shop_sign.text="HATO CAFE"
	shop_sign.font=font
	shop_sign.font_size=54
	shop_sign.outline_size=10
	shop_sign.modulate=Color("#ffe9b7")
	shop_sign.position=Vector3(56.45,7.5,9.0)
	shop_sign.rotation.y=-PI/2.0
	world_root.add_child(shop_sign)
	build_bench(Vector3(43,0,0))
	build_bench(Vector3(45,0,22))
	build_bicycle(Vector3(43,0,15))
	build_street_lamp(Vector3(38,0,-5))
	build_street_lamp(Vector3(39,0,27))

func build_bench(position: Vector3) -> void:
	make_box(world_root,Vector3(5.0,0.35,1.2),Color("#7a4c2c"),position+Vector3(0,1.15,0))
	make_box(world_root,Vector3(5.0,1.2,0.28),Color("#875635"),position+Vector3(0,1.85,0.48))
	for x in [-1.8,1.8]:make_box(world_root,Vector3(0.22,1.15,0.80),Color("#34383c"),position+Vector3(x,0.58,0))

func build_bicycle(position: Vector3) -> void:
	for x in [-1.15,1.15]:
		var wheel:=make_torus(world_root,0.58,0.08,Color("#293239"),position+Vector3(x,0.72,0),12,6)
		wheel.rotation.x=PI/2.0
	make_box(world_root,Vector3(2.2,0.12,0.12),Color("#4b7880"),position+Vector3(0,0.82,0))
	var frame:=make_box(world_root,Vector3(0.12,1.25,0.12),Color("#4b7880"),position+Vector3(0,1.18,0))
	frame.rotation.z=0.55
	make_box(world_root,Vector3(0.85,0.16,0.42),Color("#684536"),position+Vector3(0.20,1.62,0))

func build_street_lamp(position: Vector3) -> void:
	make_cylinder(world_root,0.16,5.2,Color("#333d43"),position+Vector3(0,2.6,0),8)
	make_sphere(world_root,0.48,Color("#ffe7a0"),position+Vector3(0,5.2,0),10,6)

func build_shop_row(z: float) -> void:
	var colors:=[Color("#e7a39a"),Color("#9bc4d7"),Color("#e6c276"),Color("#b5a7ce")]
	for side in [-1,1]:
		var x:=float(side)*61.0
		var size:=Vector3(rng.randf_range(13,16),rng.randf_range(5.5,8.0),rng.randf_range(12,16))
		var color:Color=colors[(int(absf(z)/24.0)+(1 if side>0 else 0))%colors.size()]
		if position_near_any_nest(Vector3(x,0,z),25.0):continue
		make_box(world_root,size,color,Vector3(x,size.y*0.5,z))
		make_box(world_root,Vector3(size.x*0.82,0.45,size.z*0.82),color.lightened(0.18),Vector3(x,size.y+0.22,z))

func build_tree(position: Vector3) -> void:
	make_cylinder(world_root,0.45,3.5,Color("#7c563d"),position+Vector3(0,1.75,0),8)
	make_sphere(world_root,2.4,Color("#4f905d"),position+Vector3(0,4.6,0),8,4)
	make_sphere(world_root,1.8,Color("#71ad66"),position+Vector3(1.3,5.2,0.4),8,4)

func position_near_any_nest(position: Vector3,radius: float) -> bool:
	for nest_position in NEST_POSITIONS:
		if distance_xz(position,nest_position)<radius:return true
	return false

func build_nest(position: Vector3,index: int) -> void:
	var colors:=[Color("#5affc2"),Color("#ff7fc8"),Color("#74c9ff")]
	var color:Color=colors[index%colors.size()]
	make_cylinder(world_root,6.0,0.36,Color("#87623f"),position+Vector3(0,0.20,0),28)
	make_cylinder(world_root,4.8,0.42,Color("#c49b56"),position+Vector3(0,0.48,0),24)
	var ring:=make_cylinder(world_root,7.2,0.08,Color(color,color.a*0.78),position+Vector3(0,0.80,0),32)
	ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nest_rings.append(ring)
	var beacon:=make_cylinder(world_root,1.35,16.0,Color(color,0.20),position+Vector3(0,8.2,0),20)
	beacon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var icon:=make_sphere(world_root,1.25,color,position+Vector3(0,9.5,0),10,5)
	icon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for angle in range(0,360,30):
		var rad:=deg_to_rad(float(angle))
		var twig:=make_box(world_root,Vector3(0.35,0.22,8.0),Color("#6d492e"),position+Vector3(cos(rad)*2.8,0.85,sin(rad)*2.8))
		twig.rotation.y=-rad

func build_pigeon(companion: bool) -> Node3D:
	var root:=Node3D.new()
	root.name="Companion" if companion else "PigeonAtAltitude"
	var visual:=Node3D.new()
	visual.name="Visual"
	root.add_child(visual)
	var scale_value:=0.60 if companion else 1.0
	var body:=make_sphere(visual,2.0*scale_value,Color("#9299a5"),Vector3(0,-0.05,0.20)*scale_value,14,8)
	body.scale=Vector3(1.03,1.10,1.32)
	var breast:=make_sphere(visual,1.48*scale_value,Color("#c5c8ca"),Vector3(0,-0.42,-1.05)*scale_value,12,7)
	breast.scale=Vector3(0.88,1.0,0.78)
	make_sphere(visual,1.32*scale_value,Color("#747c89"),Vector3(0,1.50,-0.78)*scale_value,14,8)
	var neck_green:=make_sphere(visual,1.20*scale_value,Color("#2a9a79"),Vector3(-0.38,0.78,-0.88)*scale_value,12,7)
	neck_green.scale=Vector3(0.70,0.62,0.62)
	var neck_purple:=make_sphere(visual,1.12*scale_value,Color("#8552a0"),Vector3(0.42,0.68,-0.84)*scale_value,12,7)
	neck_purple.scale=Vector3(0.66,0.56,0.58)
	for neck in [neck_green,neck_purple]:
		var neck_material:=neck.material_override.duplicate() as StandardMaterial3D
		neck_material.roughness=0.24
		neck_material.metallic=0.28
		neck.material_override=neck_material
	for x in [-0.50,0.50]:
		make_sphere(visual,0.39*scale_value,Color("#fff8e7"),Vector3(x,1.78,-1.82)*scale_value,10,6)
		make_sphere(visual,0.17*scale_value,Color("#2b201d"),Vector3(x,1.80,-2.15)*scale_value,8,4)
		make_sphere(visual,0.07*scale_value,Color.WHITE,Vector3(x-0.04,1.87,-2.29)*scale_value,6,3)
	var beak:=make_cylinder(visual,0.38*scale_value,0.92*scale_value,Color("#e89a70"),Vector3(0,1.48,-2.20)*scale_value,8,0.03)
	beak.rotation.x=PI/2.0
	var local_left:=Node3D.new()
	local_left.name="LeftWing"
	local_left.position=Vector3(-1.25,0.25,-0.05)*scale_value
	visual.add_child(local_left)
	var local_right:=Node3D.new()
	local_right.name="RightWing"
	local_right.position=Vector3(1.25,0.25,-0.05)*scale_value
	visual.add_child(local_right)
	for feather_index in 4:
		var length:=(3.0-feather_index*0.30)*scale_value
		var shade:=Color("#68717f").lightened(feather_index*0.045)
		var lf:=make_box(local_left,Vector3(length,0.26*scale_value,(0.82+feather_index*0.14)*scale_value),shade,Vector3(-length*0.48,-feather_index*0.05,feather_index*0.32)*scale_value)
		lf.rotation.y=-0.08*feather_index
		var rf:=make_box(local_right,Vector3(length,0.26*scale_value,(0.82+feather_index*0.14)*scale_value),shade,Vector3(length*0.48,-feather_index*0.05,feather_index*0.32)*scale_value)
		rf.rotation.y=0.08*feather_index
	for tail_index in 5:
		var tail_x:=(tail_index-2)*0.42*scale_value
		var tail:=make_box(visual,Vector3(0.62,0.24,2.65)*scale_value,Color("#555e6b").lightened(abs(tail_index-2)*0.035),Vector3(tail_x,-0.45,2.18)*scale_value)
		tail.rotation.y=(tail_index-2)*0.12
	for x in [-0.58,0.58]:
		var leg:=make_cylinder(visual,0.11*scale_value,0.68*scale_value,Color("#da7880"),Vector3(x,-1.75,0.48)*scale_value,7)
		leg.rotation.x=0.18
		for toe in [-0.18,0.0,0.18]:
			var foot:=make_cylinder(visual,0.065*scale_value,0.50*scale_value,Color("#df7f86"),Vector3(x+toe,-2.05,-0.02)*scale_value,6)
			foot.rotation.x=PI/2.0
	if not companion:
		left_wing=local_left
		right_wing=local_right
		rapid_badge=make_sphere(visual,0.34,Color("#70e6ff"),Vector3(0,2.9,0),8,4)
		rapid_badge.visible=false
		split_badge=make_cylinder(visual,2.6,0.10,Color(1.0,0.78,0.30,0.65),Vector3(0,-1.0,0),24)
		split_badge.visible=false
		flock_left=build_pigeon(true)
		flock_left.position=Vector3(-6.0,-0.8,1.5)
		flock_left.visible=false
		visual.add_child(flock_left)
		flock_right=build_pigeon(true)
		flock_right.position=Vector3(6.0,-0.8,1.5)
		flock_right.visible=false
		visual.add_child(flock_right)
	return root

func build_ground_character(type: String,serial: int) -> Node3D:
	var root:=Node3D.new()
	root.name="%s_%d"%[type,serial]
	var visual:=Node3D.new()
	visual.name="Visual"
	root.add_child(visual)
	var style:=serial%3
	var skin_colors:=[Color("#eab38f"),Color("#bd7f5d"),Color("#f0c6a1")]
	var skin:Color=skin_colors[serial%skin_colors.size()]
	var top_colors:=[Color("#334a70"),Color("#6c9b50"),Color("#b56b6f")]
	var bottom_colors:=[Color("#283445"),Color("#445166"),Color("#604f52")]
	var shirt:Color=top_colors[style]
	if type=="special":shirt=Color("#e5aa2d")
	for side in [-1,1]:
		var leg_pivot:=Node3D.new()
		leg_pivot.name="LeftLeg" if side<0 else "RightLeg"
		leg_pivot.position=Vector3(float(side)*0.28,1.00,0)
		visual.add_child(leg_pivot)
		make_cylinder(leg_pivot,0.18,1.35,bottom_colors[style],Vector3(0,-0.58,0),7)
		make_box(leg_pivot,Vector3(0.42,0.20,0.68),Color("#24272d"),Vector3(0,-1.27,-0.16))
	var torso:=make_box(visual,Vector3(1.25,1.60,0.78),shirt,Vector3(0,1.86,0))
	if style==1:torso.scale=Vector3(1.08,1.0,1.10)
	make_box(visual,Vector3(0.24,1.20,0.10),Color("#f4eee0"),Vector3(0,1.98,-0.45))
	if style==0:make_box(visual,Vector3(0.13,0.86,0.12),Color("#b13f46"),Vector3(0,1.89,-0.52))
	for side in [-1,1]:
		var arm:=Node3D.new()
		arm.name="LeftArm" if side<0 else "RightArm"
		arm.position=Vector3(float(side)*0.78,2.32,0)
		visual.add_child(arm)
		make_cylinder(arm,0.17,1.22,shirt.darkened(0.06),Vector3(0,-0.53,0),7)
		make_sphere(arm,0.22,skin,Vector3(0,-1.15,0),8,4)
	var head:=make_sphere(visual,0.58,skin,Vector3(0,3.05,0),12,7)
	head.scale=Vector3(0.92,1.08,0.90)
	var hair_color:Color=[Color("#24252b"),Color("#5a3828"),Color("#352b2a")][style]
	var hair:=make_sphere(visual,0.61,hair_color,Vector3(0,3.38,0.05),10,6)
	hair.scale=Vector3(0.98,0.50,0.95)
	if style==2:make_box(visual,Vector3(0.95,0.22,0.62),hair_color,Vector3(0,3.39,-0.28))
	for x in [-0.19,0.19]:
		make_sphere(visual,0.07,Color("#29231f"),Vector3(x,3.12,-0.52),6,3)
	make_box(visual,Vector3(0.22,0.055,0.055),Color("#8d4e4c"),Vector3(0,2.88,-0.56))
	var dirt:=Node3D.new()
	dirt.name="Dirt"
	dirt.visible=false
	visual.add_child(dirt)
	var face_splat:=make_sphere(dirt,0.30,Color("#f4efcf"),Vector3(0.18,3.17,-0.53),8,4)
	face_splat.scale=Vector3(1.0,0.65,0.25)
	var coat_splat:=make_sphere(dirt,0.38,Color("#e9e1b2"),Vector3(-0.24,2.05,-0.43),8,4)
	coat_splat.scale=Vector3(1.1,0.80,0.22)
	var reaction_icon:=Label3D.new()
	reaction_icon.name="ReactionIcon"
	reaction_icon.text="!"
	reaction_icon.font=font
	reaction_icon.font_size=42
	reaction_icon.outline_size=10
	reaction_icon.modulate=Color("#ffca4a")
	reaction_icon.position=Vector3(0,4.25,0)
	reaction_icon.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	reaction_icon.pixel_size=0.014
	reaction_icon.no_depth_test=true
	reaction_icon.visible=false
	visual.add_child(reaction_icon)
	if type=="bike":
		make_cylinder(visual,0.78,0.12,Color("#303b43"),Vector3(-0.78,0.72,0.42),12).rotation.z=PI/2.0
		make_cylinder(visual,0.78,0.12,Color("#303b43"),Vector3(0.78,0.72,0.42),12).rotation.z=PI/2.0
		make_box(visual,Vector3(1.55,0.10,0.10),Color("#3f5961"),Vector3(0,0.94,0.42))
	if type=="special":make_cylinder(visual,0.68,0.24,Color("#ffe273"),Vector3(0,3.66,0),10)
	var meter:=Node3D.new()
	meter.name="DirtMeter"
	meter.position=Vector3(0,4.08,0)
	meter.rotation.x=-0.52
	root.add_child(meter)
	make_box(meter,Vector3(1.6,0.16,0.10),Color("#28353b"),Vector3.ZERO)
	var fill:=make_box(meter,Vector3(1.44,0.10,0.13),Color("#eee49b"),Vector3(-0.72,0,-0.03))
	fill.name="Fill"
	fill.scale.x=0.001
	return root

func make_box(parent: Node,size: Vector3,color: Color,position: Vector3) -> MeshInstance3D:
	var mesh:=BoxMesh.new()
	mesh.size=size
	return make_mesh(parent,mesh,color,position)

func make_sphere(parent: Node,radius: float,color: Color,position: Vector3,radial:=10,rings:=5) -> MeshInstance3D:
	var mesh:=SphereMesh.new()
	mesh.radius=radius
	mesh.height=radius*2.0
	mesh.radial_segments=radial
	mesh.rings=rings
	return make_mesh(parent,mesh,color,position)

func make_cylinder(parent: Node,radius: float,height: float,color: Color,position: Vector3,radial:=10,top_radius:=-1.0) -> MeshInstance3D:
	var mesh:=CylinderMesh.new()
	mesh.bottom_radius=radius
	mesh.top_radius=radius if top_radius<0.0 else top_radius
	mesh.height=height
	mesh.radial_segments=radial
	return make_mesh(parent,mesh,color,position)

func make_torus(parent: Node,ring_radius: float,pipe_radius: float,color: Color,position: Vector3,rings:=12,ring_segments:=6) -> MeshInstance3D:
	var mesh:=TorusMesh.new()
	mesh.inner_radius=maxf(0.02,ring_radius-pipe_radius)
	mesh.outer_radius=ring_radius+pipe_radius
	mesh.rings=rings
	mesh.ring_segments=ring_segments
	return make_mesh(parent,mesh,color,position)

func make_mesh(parent: Node,mesh: Mesh,color: Color,position: Vector3) -> MeshInstance3D:
	var instance:=MeshInstance3D.new()
	instance.mesh=mesh
	instance.position=position
	instance.material_override=material_for(color)
	parent.add_child(instance)
	return instance

func material_for(color: Color) -> StandardMaterial3D:
	var key:=color.to_html(true)
	if material_cache.has(key):return material_cache[key]
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=0.84
	if color.a<0.99:
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material_cache[key]=material
	return material

func clear_ui() -> void:
	for child in ui_root.get_children():child.queue_free()
	evo_bars.clear()
	evo_labels.clear()
	score_label=null
	anger_bar=null
	anger_notice_label=null
	combo_label=null
	nest_label=null
	banner_label=null

func make_label(text_value:String,rect:Rect2,size:int,color:=Color.WHITE,centered:=false) -> Label:
	var label:=Label.new()
	label.text=text_value
	label.position=rect.position
	label.size=rect.size
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	ui_root.add_child(label)
	return label

func make_panel(rect:Rect2,color:Color,radius:=18) -> Panel:
	var panel:=Panel.new()
	panel.position=rect.position
	panel.size=rect.size
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.corner_radius_top_left=radius
	style.corner_radius_top_right=radius
	style.corner_radius_bottom_left=radius
	style.corner_radius_bottom_right=radius
	panel.add_theme_stylebox_override("panel",style)
	ui_root.add_child(panel)
	return panel

func make_button(text_value:String,rect:Rect2,callback:Callable,color:=Color("#f8f0cf")) -> Button:
	var button:=Button.new()
	button.text=text_value
	button.position=rect.position
	button.size=rect.size
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",21)
	button.add_theme_color_override("font_color",Color("#26353b"))
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.corner_radius_top_left=16
	style.corner_radius_top_right=16
	style.corner_radius_bottom_left=16
	style.corner_radius_bottom_right=16
	style.shadow_color=Color(0.1,0.16,0.18,0.25)
	style.shadow_size=5
	button.add_theme_stylebox_override("normal",style)
	var hover:=style.duplicate()
	hover.bg_color=color.lightened(0.08)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover)
	button.pressed.connect(callback)
	ui_root.add_child(button)
	return button

func show_title() -> void:
	state=ScreenState.TITLE
	clear_dynamic_nodes()
	clear_ui()
	player_pos=Vector3(0,PLAYER_ALTITUDE,0)
	player_velocity=Vector2.ZERO
	update_player_transform(0.0)
	make_panel(Rect2(24,28,492,205),Color(0.06,0.12,0.15,0.82),22)
	make_label("ハト爆撃隊",Rect2(42,48,456,64),46,Color("#fff0af"),true)
	make_label("狙う → 進化する → 欲張るか帰るか",Rect2(42,116,456,40),18,Color.WHITE,true)
	make_label("血統：%s　BEST %05d"%[lineage_display(String(save_data.lineage)),int(save_data.best)],Rect2(42,164,456,36),17,Color("#c6e8ef"),true)
	make_panel(Rect2(40,690,460,210),Color(0.05,0.10,0.12,0.68),22)
	make_button("出撃する！",Rect2(95,724,350,76),start_sortie,Color("#ffd35e"))
	make_label("ドラッグ移動のみ・攻撃は自動",Rect2(75,820,390,34),17,Color.WHITE,true)
	make_label("パンくず %d"%int(save_data.breadcrumbs),Rect2(75,855,390,28),16,Color("#f2dfa1"),true)

func start_sortie() -> void:
	clear_dynamic_nodes()
	state=ScreenState.PLAYING
	player_pos=Vector3(0,PLAYER_ALTITUDE,0)
	player_velocity=Vector2.ZERO
	drag_active=false
	drag_vector=Vector2.ZERO
	score=0
	hit_count=0
	combo=0
	max_combo=0
	combo_clock=0.0
	anger=0.0
	drop_clock=0.25
	spawn_clock=0.05
	attack_serial=0
	target_spawn_serial=0
	has_flown_out=false
	anger_flash_clock=0.0
	anger_notice_clock=0.0
	evolution={"rapid":0.0,"split":0.0,"flock":0.0}
	evolved={"rapid":false,"split":false,"flock":false}
	showcase_kind=""
	showcase_clock=0.0
	evolution_slow_clock=0.0
	apply_evolution_visuals()
	build_hud()
	for cluster_index in TARGET_CLUSTER_CENTERS.size():
		for i in INITIAL_TARGETS_PER_CLUSTER:spawn_target(cluster_index)
	update_player_transform(0.0)
	play_tone(540.0,0.09)

func build_hud() -> void:
	clear_ui()
	make_panel(Rect2(12,12,516,184),Color(0.04,0.09,0.11,0.82),16)
	score_label=make_label("SCORE 00000",Rect2(25,20,260,34),20)
	combo_label=make_label("COMBO 0",Rect2(350,20,150,34),17,Color("#ffd35e"),true)
	var colors:={"rapid":Color("#70e6ff"),"split":Color("#ffcf62"),"flock":Color("#d19cff")}
	var names:={"rapid":"中心命中・連射","split":"複数命中・分裂","flock":"コンボ・群れ"}
	for index in EVOLUTION_TYPES.size():
		var kind:String=EVOLUTION_TYPES[index]
		make_panel(Rect2(25,61+index*26,330,16),Color("#26343a"),6)
		var bar:=ColorRect.new()
		bar.position=Vector2(28,64+index*26)
		bar.size=Vector2(0,10)
		bar.color=colors[kind]
		ui_root.add_child(bar)
		evo_bars[kind]=bar
		evo_labels[kind]=make_label(names[kind],Rect2(365,54+index*26,145,26),13,colors[kind],true)
	make_panel(Rect2(25,143,330,14),Color("#3b2022"),6)
	anger_bar=ColorRect.new()
	anger_bar.position=Vector2(28,146)
	anger_bar.size=Vector2(0,8)
	anger_bar.color=Color("#ff6a5f")
	ui_root.add_child(anger_bar)
	make_label("命中で怒り",Rect2(365,137,145,26),13,Color("#ff8d83"),true)
	anger_notice_label=make_label("命中すると上昇・100で失敗",Rect2(25,158,480,24),12,Color("#ffc0b9"),true)
	nest_label=make_label("最寄りの巣",Rect2(55,810,430,34),18,Color("#a8ffd5"),true)
	make_panel(Rect2(42,850,456,62),Color(0.04,0.09,0.11,0.72),16)
	make_label("3色の光柱の巣へ戻ると報酬を確定",Rect2(58,858,424,42),15,Color.WHITE,true)
	banner_label=make_label("",Rect2(30,370,480,100),44,Color.WHITE,true)

func update_hud() -> void:
	if not is_instance_valid(score_label):return
	score_label.text="SCORE %05d"%score
	combo_label.text="COMBO %d"%combo
	anger_bar.size.x=324.0*anger/100.0
	anger_bar.color=Color.WHITE if anger_flash_clock>0.0 and int(anger_flash_clock*24.0)%2==0 else Color("#ff6a5f")
	if anger_notice_clock<=0.0:
		anger_notice_label.text="命中すると上昇・100で失敗"
		anger_notice_label.modulate=Color(1.0,0.75,0.72,0.78)
	else:anger_notice_label.modulate.a=clampf(anger_notice_clock*1.8,0.35,1.0)
	var nearest:=nearest_nest_position()
	nest_label.text="最寄りの巣 %s %dm　未確定パン %d"%[nest_direction_arrow(nearest),int(distance_xz(player_pos,nearest)),int(score/120)]
	for kind in EVOLUTION_TYPES:
		evo_bars[kind].size.x=324.0*float(evolution[kind])/100.0
		if bool(evolved[kind]):evo_labels[kind].text="進化済み"
		elif float(evolution[kind])>=75.0:evo_labels[kind].text="進化予告！"

func build_result_ui() -> void:
	clear_ui()
	var success:=bool(last_result.success)
	make_panel(Rect2(28,70,484,820),Color(0.04,0.08,0.10,0.90),24)
	make_label("帰巣成功！" if success else "怒り爆発…",Rect2(50,100,440,70),40,Color("#a8ffd5") if success else Color("#ff8d83"),true)
	make_label("SCORE %05d"%int(last_result.score),Rect2(50,200,440,56),34,Color.WHITE,true)
	make_label("命中 %d　最大COMBO %d"%[int(last_result.hits),int(last_result.combo)],Rect2(50,270,440,40),20,Color("#c9e7ed"),true)
	if success:
		make_label("パンくず +%d　確定"%int(last_result.reward),Rect2(50,340,440,44),24,Color("#f4df9c"),true)
		make_label("継承：%s"%lineage_display(String(last_result.lineage)),Rect2(50,405,440,50),26,Color("#d8b6ff"),true)
	else:
		make_label("未確定パン %d を喪失"%int(last_result.lost),Rect2(50,340,440,44),24,Color("#ffaaa0"),true)
		make_label("前回の血統は保持",Rect2(50,405,440,50),22,Color("#d8b6ff"),true)
	make_panel(Rect2(75,500,390,86),Color(0.13,0.18,0.20,0.72),16)
	make_label("欲張るほど高得点、帰れば確定",Rect2(90,518,360,48),17,Color("#c9d8dc"),true)
	make_button("もう一度出撃",Rect2(80,650,380,68),start_sortie,Color("#ffd35e"))
	make_button("タイトルへ",Rect2(150,750,240,58),show_title,Color("#d9f0e2"))

func lineage_display(kind: String) -> String:
	return {"rapid":"連射の血統","split":"分裂の血統","flock":"群れの血統","":"なし"}.get(kind,"なし")

func debug_combo_burst() -> void:
	clear_dynamic_nodes()
	var offsets:=[Vector2(-3.0,-1.5),Vector2(0.0,-2.0),Vector2(3.0,-1.5),Vector2(-1.8,2.0),Vector2(1.8,2.0)]
	for index in offsets.size():
		spawn_target(index%TARGET_CLUSTER_CENTERS.size())
		var target:=targets[targets.size()-1]
		target.pos=Vector3(player_pos.x+offsets[index].x,0.0,player_pos.z+offsets[index].y)
		target.home=target.pos
		target.max_dirt=999.0
		target.node.position=target.pos
	for i in 3:impact_poop(Vector3(player_pos.x,0.35,player_pos.z))

func debug_single_hit(is_direct: bool) -> void:
	clear_dynamic_nodes()
	spawn_target(0)
	var target:=targets[0]
	target.pos=Vector3(player_pos.x+(0.0 if is_direct else 3.0),0.0,player_pos.z-2.0)
	target.home=target.pos
	target.max_dirt=999.0
	target.node.position=target.pos
	impact_poop(Vector3(player_pos.x,0.35,player_pos.z-2.0))

func debug_multi_hit() -> void:
	clear_dynamic_nodes()
	for index in 3:
		spawn_target(index)
		var target:=targets[index]
		target.pos=Vector3(player_pos.x+float(index-1)*2.6,0.0,player_pos.z-2.0)
		target.home=target.pos
		target.max_dirt=999.0
		target.node.position=target.pos
	impact_poop(Vector3(player_pos.x,0.35,player_pos.z-2.0))

func debug_show_hero_block() -> void:
	player_pos=Vector3(44.0,PLAYER_ALTITUDE,16.0)
	has_flown_out=true
	update_player_transform(0.0)

func _input(event: InputEvent) -> void:
	if OS.is_debug_build() and state==ScreenState.PLAYING and event is InputEventKey and event.pressed and not event.echo:
		match event.unicode:
			48:
				player_pos=nearest_nest_position()+Vector3(0.0,PLAYER_ALTITUDE,0.0)
				has_flown_out=true
				update_player_transform(0.0)
			49: trigger_evolution("rapid")
			50: trigger_evolution("split")
			51: trigger_evolution("flock")
			52: finish_sortie(true)
			53:
				anger=100.0
				finish_sortie(false)
			54: debug_combo_burst()
			68,100: debug_single_hit(true)
			78,110: debug_single_hit(false)
			77,109: debug_multi_hit()
			72,104: debug_show_hero_block()
			55,56,57:
				var nest_index:=int(event.unicode)-55
				player_pos=NEST_POSITIONS[nest_index]+Vector3(0.0,PLAYER_ALTITUDE,12.0)
				has_flown_out=true
				update_player_transform(0.0)
	if state!=ScreenState.PLAYING:return
	if event is InputEventScreenTouch:
		if event.pressed:
			drag_active=true
			drag_origin=event.position
			drag_vector=Vector2.ZERO
		else:
			drag_active=false
			drag_vector=Vector2.ZERO
	elif event is InputEventScreenDrag and drag_active:drag_vector=(event.position-drag_origin)/78.0
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_active=true
			drag_origin=event.position
			drag_vector=Vector2.ZERO
		else:
			drag_active=false
			drag_vector=Vector2.ZERO
	elif event is InputEventMouseMotion and drag_active:drag_vector=(event.position-drag_origin)/78.0

func play_tone(frequency: float,duration: float) -> void:
	audio_player.stream=make_tone_stream(frequency,duration,false)
	audio_player.play()

func play_drop_whoosh() -> void:
	play_one_shot(make_tone_stream(310.0,0.10,false),-15.0,0.72)

func play_impact_sound(is_direct: bool,hit_total: int) -> void:
	var impact_frequency:=92.0 if is_direct else 128.0
	play_one_shot(make_tone_stream(impact_frequency,0.12,true),-7.0,0.74)
	play_one_shot(make_tone_stream(660.0+float(hit_total)*32.0,0.08,false),-11.0,1.0)

func play_one_shot(stream: AudioStream,volume_db: float,pitch_scale: float) -> void:
	var player:=AudioStreamPlayer.new()
	player.volume_db=volume_db
	player.pitch_scale=pitch_scale
	player.stream=stream
	add_child(player)
	player.play()
	effects.append({"node":player,"time":0.32,"max_time":0.32,"kind":"audio"})

func play_reaction_sound(is_direct: bool,hit_total: int) -> void:
	var pitch:=(0.82 if is_direct else 1.10)+minf(0.15,float(hit_total-1)*0.03)
	play_one_shot(make_tone_stream(175.0 if is_direct else 245.0,0.22 if is_direct else 0.14,true),-4.0,pitch)

func make_tone_stream(frequency: float,duration: float,vocal: bool) -> AudioStreamWAV:
	var mix_rate:=22050
	var frames:=int(duration*mix_rate)
	var data:=PackedByteArray()
	data.resize(frames*2)
	for index in frames:
		var envelope:=1.0-float(index)/frames
		var phase:=TAU*frequency*index/mix_rate
		var wave:=sin(phase)
		if vocal:wave=sin(phase)+0.35*sin(phase*0.52)+0.18*sin(phase*1.96)
		var sample:=int(wave*envelope*(4100.0 if vocal else 6200.0))
		data[index*2]=sample&0xff
		data[index*2+1]=(sample>>8)&0xff
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=mix_rate
	stream.stereo=false
	stream.data=data
	return stream

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):return
	var file:=FileAccess.open(SAVE_PATH,FileAccess.READ)
	if file==null:return
	var parsed=JSON.parse_string(file.get_as_text())
	if typeof(parsed)!=TYPE_DICTIONARY:return
	if parsed.has("best"):save_data.best=int(parsed.best)
	if parsed.has("breadcrumbs"):save_data.breadcrumbs=int(parsed.breadcrumbs)
	if parsed.has("lineage"):save_data.lineage=String(parsed.lineage)

func save_game() -> void:
	var file:=FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(save_data))

func debug_run_checks() -> Array[String]:
	var errors:Array[String]=[]
	var previous_save:=save_data.duplicate(true)
	if PLAYER_ALTITUDE<=6.0:errors.append("player altitude")
	if EVOLUTION_TYPES.size()!=3:errors.append("evolution count")
	if NEST_POSITIONS.size()!=3:errors.append("nest count")
	start_sortie()
	if targets.size()!=TARGET_CLUSTER_CENTERS.size()*INITIAL_TARGETS_PER_CLUSTER:errors.append("clustered target count")
	clear_dynamic_nodes()
	drop_clock=99.0
	spawn_clock=99.0
	var passive_anger:=anger
	update_game(0.5)
	if not is_equal_approx(anger,passive_anger):errors.append("passive anger regression")
	perform_auto_drop()
	if poops.size()<3:errors.append("strong base attack")
	spawn_target()
	if targets.is_empty():errors.append("ground target")
	else:
		if absf(float(targets[0].pos.y))>0.1:errors.append("target altitude")
		var before:=player_pos
		targets[0].pos=Vector3(player_pos.x,0,player_pos.z)
		update_targets(0.1)
		if player_pos!=before:errors.append("contact damage regression")
		var anger_before_hit:=anger
		var score_before_hit:=score
		impact_poop(Vector3(player_pos.x,0.35,player_pos.z))
		if anger<=anger_before_hit:errors.append("hit anger feedback")
		if anger_notice_clock<=0.0:errors.append("anger notice")
		if score-score_before_hit<DIRECT_HIT_SCORE:errors.append("direct hit score")
		if String(targets[0].reaction_kind)!="direct":errors.append("direct reaction")
		if not bool(targets[0].dirt_node.visible):errors.append("persistent dirt")
		var found_popup:=false
		for effect in effects:
			if effect.kind=="popup":found_popup=true
		if not found_popup:errors.append("score popup")
	for kind in EVOLUTION_TYPES:
		trigger_evolution(kind)
		if not bool(evolved[kind]):errors.append("evolution "+kind)
	evolution.rapid=100.0
	for nest_index in NEST_POSITIONS.size():
		if nest_index>0:start_sortie()
		has_flown_out=true
		player_pos=NEST_POSITIONS[nest_index]+Vector3(0.0,PLAYER_ALTITUDE,0.0)
		drop_clock=99.0
		spawn_clock=99.0
		update_game(0.01)
		if state!=ScreenState.RESULT or not bool(last_result.success):errors.append("nest %d banking"%nest_index)
	if String(save_data.lineage)=="":errors.append("lineage save")
	start_sortie()
	anger=100.0
	update_game(0.01)
	if state!=ScreenState.RESULT:errors.append("anger result")
	if String(save_data.lineage)=="":errors.append("lineage lost on failure")
	save_data=previous_save
	save_game()
	return errors
