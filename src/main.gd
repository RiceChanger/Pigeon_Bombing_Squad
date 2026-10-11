extends Node2D

const VIEW := Vector2(540.0, 960.0)
const WORLD := Vector2(1700.0, 2200.0)
const SAVE_PATH := "user://pigeon_bombing_save.json"
const STAGE_SECONDS := 120.0

enum ScreenState { TITLE, SELECT, PLAYING, LEVEL_UP, RESULT, SHOP }

const STAGES := [
	{"name":"公園", "subtitle":"のんびり練習コース", "ground":Color("#b9dd9c"), "road":Color("#d9c89d"), "enemy_rate":1.55, "hazard_rate":4.8, "goal":900, "stars":[900,1800,3000], "reward":18},
	{"name":"商店街", "subtitle":"傘と自転車にご用心", "ground":Color("#f1d8b8"), "road":Color("#b7b5b1"), "enemy_rate":1.10, "hazard_rate":3.5, "goal":1500, "stars":[1500,2900,4600], "reward":28},
	{"name":"駅前", "subtitle":"カラスとドローンの猛攻", "ground":Color("#c8d2da"), "road":Color("#8fa0aa"), "enemy_rate":0.78, "hazard_rate":2.35, "goal":2200, "stars":[2200,4000,6200], "reward":42},
]

const UPGRADES := [
	{"id":"bread", "name":"消化促進パン", "icon":"PAN", "desc":"投下間隔を短縮"},
	{"id":"burst", "name":"追いフン", "icon":"•••", "desc":"連続投下が増える"},
	{"id":"trident", "name":"三つ又尾羽", "icon":"↙↓↘", "desc":"左右にも同時投下"},
	{"id":"mega", "name":"メガフン", "icon":"◎", "desc":"威力と範囲アップ"},
	{"id":"wing", "name":"強靭な翼", "icon":"≋", "desc":"速度と旋回性能アップ"},
	{"id":"barrier", "name":"羽毛バリア", "icon":"◇", "desc":"受けるダメージを軽減"},
	{"id":"flock", "name":"群れの呼び声", "icon":"ᴠᴠᴠ", "desc":"仲間が一定時間爆撃"},
	{"id":"storm", "name":"フンの嵐", "icon":"☂", "desc":"定期的に大量投下"},
]

var state := ScreenState.TITLE
var stage_index := 0
var player_pos := WORLD * 0.5
var player_velocity := Vector2.ZERO
var camera_pos := player_pos
var drag_active := false
var drag_origin := Vector2.ZERO
var drag_vector := Vector2.ZERO

var hp := 100.0
var score := 0
var xp := 0.0
var level := 1
var xp_next := 42.0
var time_left := STAGE_SECONDS
var drop_clock := 0.0
var spawn_clock := 0.0
var hazard_clock := 0.0
var invulnerable := 0.0
var shake := 0.0
var flock_time := 0.0
var storm_time := 0.0
var storm_clock := 0.0
var enemy_serial := 0

var enemies: Array[Dictionary] = []
var poops: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var upgrades := {}
var save_data := {"breadcrumbs":0, "permanent":{"interval":0,"radius":0,"speed":0}, "best":[0,0,0], "stars":[0,0,0]}
var choice_indices: Array[int] = []
var rng := RandomNumberGenerator.new()

var buttons: Array[Button] = []
var audio_player: AudioStreamPlayer
var font: Font

func _ready() -> void:
	font = preload("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	rng.randomize()
	load_save()
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	show_title()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if state == ScreenState.PLAYING:
		update_game(delta)
	queue_redraw()

func clear_buttons() -> void:
	for b in buttons:
		if is_instance_valid(b): b.queue_free()
	buttons.clear()

func make_button(text_value: String, rect: Rect2, callback: Callable, color := Color("#f8f0cf")) -> Button:
	var b := Button.new()
	b.text = text_value
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_font_override("font",font)
	b.add_theme_color_override("font_color", Color("#26353b"))
	b.add_theme_color_override("font_hover_color", Color("#15252d"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = 18
	normal.corner_radius_top_right = 18
	normal.corner_radius_bottom_left = 18
	normal.corner_radius_bottom_right = 18
	normal.shadow_color = Color(0.18,0.22,0.24,0.18)
	normal.shadow_size = 5
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.08)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(callback)
	add_child(b)
	buttons.append(b)
	return b

func show_title() -> void:
	state = ScreenState.TITLE
	clear_buttons()
	make_button("飛び立つ！", Rect2(120,690,300,70), show_stage_select, Color("#ffd56a"))
	make_button("巣の強化", Rect2(150,780,240,58), show_shop, Color("#d9f0e2"))
	queue_redraw()

func show_stage_select() -> void:
	state = ScreenState.SELECT
	clear_buttons()
	for i in STAGES.size():
		var label := "%d  %s  ★%d" % [i + 1, STAGES[i].name, int(save_data.stars[i])]
		make_button(label, Rect2(65,260 + i * 145,410,92), start_stage.bind(i), [Color("#bce4a8"),Color("#ffd49d"),Color("#c8d8e8")][i])
	make_button("← もどる", Rect2(170,760,200,55), show_title, Color("#e8edf0"))
	queue_redraw()

func show_shop() -> void:
	state = ScreenState.SHOP
	clear_buttons()
	var keys := ["interval","radius","speed"]
	var names := ["初期投下間隔","初期着弾範囲","初期移動速度"]
	for i in 3:
		var lv := int(save_data.permanent[keys[i]])
		var cost := 20 + lv * 20
		var label := "%s  Lv.%d/3\nパン %d" % [names[i],lv,cost] if lv < 3 else "%s  MAX" % names[i]
		make_button(label, Rect2(70,265 + i * 135,400,86), buy_permanent.bind(keys[i]), Color("#eef5d5"))
	make_button("← もどる", Rect2(170,715,200,55), show_title, Color("#e8edf0"))
	queue_redraw()

func buy_permanent(key: String) -> void:
	var lv := int(save_data.permanent[key])
	if lv >= 3: return
	var cost := 20 + lv * 20
	if int(save_data.breadcrumbs) >= cost:
		save_data.breadcrumbs = int(save_data.breadcrumbs) - cost
		save_data.permanent[key] = lv + 1
		save_game()
		play_tone(720.0,0.12)
		show_shop()
	else:
		play_tone(150.0,0.12)

func start_stage(index: int) -> void:
	stage_index = clampi(index,0,STAGES.size()-1)
	state = ScreenState.PLAYING
	clear_buttons()
	player_pos = WORLD * 0.5
	camera_pos = player_pos
	player_velocity = Vector2.ZERO
	hp = 100.0
	score = 0
	xp = 0.0
	level = 1
	xp_next = 42.0
	time_left = STAGE_SECONDS
	drop_clock = 0.35
	spawn_clock = 0.2
	hazard_clock = 2.0
	invulnerable = 0.0
	flock_time = 0.0
	storm_time = 0.0
	enemies.clear()
	poops.clear()
	projectiles.clear()
	effects.clear()
	upgrades.clear()
	play_tone(540.0,0.08)
	queue_redraw()

func update_game(delta: float) -> void:
	time_left = maxf(0.0,time_left-delta)
	invulnerable = maxf(0.0,invulnerable-delta)
	shake = maxf(0.0,shake-delta*15.0)
	flock_time = maxf(0.0,flock_time-delta)
	storm_time = maxf(0.0,storm_time-delta)
	var speed := 250.0 * (1.0 + 0.12 * int(save_data.permanent.speed)) * (1.0 + 0.14 * upgrade_level("wing"))
	var desired := drag_vector.limit_length(1.0) * speed
	var response := 7.5 + upgrade_level("wing") * 2.0
	player_velocity = player_velocity.lerp(desired,1.0-exp(-response*delta))
	if not drag_active: player_velocity = player_velocity.move_toward(Vector2.ZERO,speed*7.0*delta)
	player_pos += player_velocity*delta
	player_pos.x = clampf(player_pos.x,135.0,WORLD.x-135.0)
	player_pos.y = clampf(player_pos.y,150.0,WORLD.y-150.0)
	camera_pos = camera_pos.lerp(player_pos,1.0-exp(-6.0*delta))

	drop_clock -= delta
	if drop_clock <= 0.0:
		perform_auto_drop()
		drop_clock += current_drop_interval()
	if storm_time > 0.0:
		storm_clock -= delta
		if storm_clock <= 0.0:
			storm_clock = 0.16
			spawn_poop(player_pos + Vector2(rng.randf_range(-150,150),rng.randf_range(-130,150)),0.34)

	spawn_clock -= delta
	if spawn_clock <= 0.0:
		spawn_enemy()
		spawn_clock += float(STAGES[stage_index].enemy_rate) * rng.randf_range(0.72,1.22)
	hazard_clock -= delta
	if hazard_clock <= 0.0:
		spawn_hazard()
		hazard_clock += float(STAGES[stage_index].hazard_rate) * rng.randf_range(0.8,1.25)
	update_poops(delta)
	update_enemies(delta)
	update_projectiles(delta)
	update_effects(delta)
	if hp <= 0.0:
		finish_stage(false)
	elif time_left <= 0.0:
		finish_stage(score >= int(STAGES[stage_index].goal))

func current_drop_interval() -> float:
	var value: float = [3.0,2.0,1.0][mini(upgrade_level("bread"),2)]
	value -= 0.16 * int(save_data.permanent.interval)
	return maxf(0.7,value)

func perform_auto_drop() -> void:
	var burst := mini(1 + upgrade_level("burst"),3)
	var offsets := [Vector2.ZERO]
	if upgrade_level("trident") > 0:
		offsets.append(Vector2(-78,60))
		offsets.append(Vector2(78,60))
	for n in burst:
		for offset in offsets:
			spawn_poop(player_pos + offset + player_velocity*0.10,0.48+n*0.13)
	if flock_time > 0.0:
		spawn_poop(player_pos+Vector2(-115,30),0.52)
		spawn_poop(player_pos+Vector2(115,30),0.52)

func spawn_poop(target: Vector2, delay := 0.48) -> void:
	poops.append({"target":target,"time":0.0,"delay":delay,"start":target+Vector2(0,-190)})

func update_poops(delta: float) -> void:
	for i in range(poops.size()-1,-1,-1):
		poops[i].time += delta
		if float(poops[i].time) >= float(poops[i].delay):
			impact_poop(poops[i].target)
			poops.remove_at(i)

func impact_poop(pos: Vector2) -> void:
	var mega := upgrade_level("mega")
	var radius := 65.0 * (1.0 + 0.20*int(save_data.permanent.radius) + 0.30*mega)
	var damage := 38.0 * (1.0 + 0.42*mega)
	var hits := 0
	for e in enemies:
		if e.pos.distance_to(pos) <= radius + float(e.radius):
			e.dirt += damage
			hits += 1
			e.flash = 0.18
			add_xp(7.0)
			score += 45
	effects.append({"pos":pos,"time":0.42,"kind":"splat","radius":radius})
	play_tone(210.0 if hits == 0 else 410.0,0.055)

func spawn_enemy() -> void:
	if enemies.size() > 38: return
	enemy_serial += 1
	var angle := rng.randf_range(0,TAU)
	var distance := rng.randf_range(390,620)
	var p := player_pos + Vector2.from_angle(angle)*distance
	p.x = clampf(p.x,80,WORLD.x-80)
	p.y = clampf(p.y,80,WORLD.y-80)
	var type := "human"
	if stage_index >= 1 and enemy_serial % 5 == 0: type = "bike"
	if stage_index == 2 and enemy_serial % 4 == 0: type = "crow"
	var max_dirt := 72.0 if type == "human" else (95.0 if type == "bike" else 82.0)
	var radius := 25.0 if type == "human" else 32.0
	enemies.append({"pos":p,"vel":Vector2.from_angle(rng.randf_range(0,TAU))*rng.randf_range(22,48),"dirt":0.0,"max_dirt":max_dirt,"type":type,"radius":radius,"flash":0.0,"turn":rng.randf_range(0.8,2.4)})

func update_enemies(delta: float) -> void:
	for i in range(enemies.size()-1,-1,-1):
		var e := enemies[i]
		e.flash = maxf(0.0,float(e.flash)-delta)
		e.turn -= delta
		if e.turn <= 0.0:
			e.turn = rng.randf_range(1.0,3.0)
			var toward: Vector2 = (player_pos-e.pos).normalized()
			if e.type == "crow":
				e.vel = toward*95.0
			else:
				e.vel = e.vel.rotated(rng.randf_range(-1.0,1.0))
		e.pos += e.vel*delta
		if e.pos.x < 50 or e.pos.x > WORLD.x-50: e.vel.x *= -1
		if e.pos.y < 50 or e.pos.y > WORLD.y-50: e.vel.y *= -1
		if e.pos.distance_to(player_pos) < float(e.radius)+34.0:
			damage_player(10.0 if e.type != "crow" else 16.0)
			e.vel = (e.pos-player_pos).normalized()*120.0
		if float(e.dirt) >= float(e.max_dirt):
			score += 120 if e.type == "human" else 180
			add_xp(20.0)
			effects.append({"pos":e.pos,"time":0.65,"kind":"flee","radius":40.0})
			enemies.remove_at(i)

func spawn_hazard() -> void:
	var origin := player_pos + Vector2.from_angle(rng.randf_range(0,TAU))*rng.randf_range(340,520)
	var type := "ball"
	var speed := 215.0
	var damage := 13.0
	if stage_index == 1 and rng.randf() < 0.45:
		type = "umbrella"
		speed = 185.0
	elif stage_index == 2:
		type = "drone"
		speed = 260.0
		damage = 18.0
	projectiles.append({"pos":origin,"vel":(player_pos-origin).normalized()*speed,"life":4.0,"damage":damage,"type":type})

func update_projectiles(delta: float) -> void:
	for i in range(projectiles.size()-1,-1,-1):
		var p := projectiles[i]
		p.pos += p.vel*delta
		p.life -= delta
		if p.pos.distance_to(player_pos) < 38.0:
			damage_player(float(p.damage))
			projectiles.remove_at(i)
		elif p.life <= 0.0:
			projectiles.remove_at(i)

func damage_player(amount: float) -> void:
	if invulnerable > 0.0: return
	var reduction := minf(0.55,upgrade_level("barrier")*0.16)
	hp -= amount*(1.0-reduction)
	invulnerable = 0.65
	shake = 8.0
	effects.append({"pos":player_pos,"time":0.35,"kind":"hit","radius":48.0})
	play_tone(95.0,0.12)

func add_xp(amount: float) -> void:
	xp += amount
	if xp >= xp_next and state == ScreenState.PLAYING:
		xp -= xp_next
		level += 1
		xp_next = 42.0 + level*18.0
		show_level_up()

func show_level_up() -> void:
	state = ScreenState.LEVEL_UP
	clear_buttons()
	choice_indices.clear()
	var pool := range(UPGRADES.size())
	for i in 3:
		var pick := rng.randi_range(0,pool.size()-1)
		choice_indices.append(pool[pick])
		pool.remove_at(pick)
	for i in 3:
		var u: Dictionary = UPGRADES[choice_indices[i]]
		var lv := upgrade_level(u.id)
		var label := "%s  %s\n%s  Lv.%d → %d" % [u.icon,u.name,u.desc,lv,lv+1]
		make_button(label,Rect2(45,275+i*145,450,108),select_upgrade.bind(choice_indices[i]),[Color("#fff0b8"),Color("#d8f0e0"),Color("#ded8f4")][i])
	play_tone(760.0,0.16)

func select_upgrade(upgrade_index: int) -> void:
	var id: String = UPGRADES[upgrade_index].id
	upgrades[id] = upgrade_level(id)+1
	if id == "flock": flock_time = 18.0 + upgrade_level(id)*5.0
	if id == "storm":
		storm_time = 6.0 + upgrade_level(id)*2.0
		storm_clock = 0.0
	clear_buttons()
	state = ScreenState.PLAYING

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id,0))

func update_effects(delta: float) -> void:
	for i in range(effects.size()-1,-1,-1):
		effects[i].time -= delta
		if effects[i].time <= 0.0: effects.remove_at(i)

func finish_stage(survived: bool) -> void:
	if state == ScreenState.RESULT: return
	state = ScreenState.RESULT
	drag_active = false
	drag_vector = Vector2.ZERO
	clear_buttons()
	var earned_stars := 0
	if survived:
		for threshold in STAGES[stage_index].stars:
			if score >= int(threshold): earned_stars += 1
	var reward := int(STAGES[stage_index].reward)*earned_stars
	save_data.breadcrumbs = int(save_data.breadcrumbs)+reward
	save_data.best[stage_index] = maxi(int(save_data.best[stage_index]),score)
	save_data.stars[stage_index] = maxi(int(save_data.stars[stage_index]),earned_stars)
	save_game()
	make_button("もう一度",Rect2(55,700,200,64),start_stage.bind(stage_index),Color("#ffd56a"))
	make_button("ステージ選択",Rect2(285,700,200,64),show_stage_select,Color("#d9f0e2"))
	play_tone(680.0 if survived else 115.0,0.22)

func _unhandled_input(event: InputEvent) -> void:
	if state != ScreenState.PLAYING: return
	if event is InputEventScreenTouch:
		if event.pressed:
			drag_active = true
			drag_origin = event.position
			drag_vector = Vector2.ZERO
		else:
			drag_active = false
			drag_vector = Vector2.ZERO
	elif event is InputEventScreenDrag and drag_active:
		drag_vector = (event.position-drag_origin)/82.0
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_active = true
			drag_origin = event.position
			drag_vector = Vector2.ZERO
		else:
			drag_active = false
			drag_vector = Vector2.ZERO
	elif event is InputEventMouseMotion and drag_active:
		drag_vector = (event.position-drag_origin)/82.0

func world_to_screen(pos: Vector2) -> Vector2:
	var jitter := Vector2(rng.randf_range(-shake,shake),rng.randf_range(-shake,shake)) if shake > 0.0 else Vector2.ZERO
	return pos-camera_pos+Vector2(270,520)+jitter

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),Color("#cae9ef"))
	if state in [ScreenState.PLAYING,ScreenState.LEVEL_UP,ScreenState.RESULT]:
		draw_world()
		draw_hud()
	match state:
		ScreenState.TITLE: draw_title_screen()
		ScreenState.SELECT: draw_select_screen()
		ScreenState.SHOP: draw_shop_screen()
		ScreenState.LEVEL_UP: draw_level_overlay()
		ScreenState.RESULT: draw_result_overlay()

func draw_title_screen() -> void:
	draw_circle(Vector2(270,255),205,Color("#f4e7bd"))
	draw_pigeon(Vector2(270,330),1.55,0.0)
	draw_centered("ハト爆撃隊",95,62,Color("#263b43"))
	draw_centered("PIGEON BOMBING SQUAD",155,18,Color("#50727b"))
	draw_centered("ドラッグだけで飛び回れ。攻撃はハトにお任せ！",625,18,Color("#40545a"))
	draw_centered("パンくず %d" % int(save_data.breadcrumbs),870,22,Color("#73562d"))

func draw_select_screen() -> void:
	draw_centered("どこを爆撃する？",96,34,Color("#263b43"))
	draw_centered("各ステージ 2分 / 生存＋目標スコアでクリア",146,17,Color("#536b72"))
	for i in 3:
		draw_centered(STAGES[i].subtitle,362+i*145,15,Color("#5c6568"))
	draw_centered("パンくず %d" % int(save_data.breadcrumbs),870,22,Color("#73562d"))

func draw_shop_screen() -> void:
	draw_centered("巣の永続強化",90,36,Color("#263b43"))
	draw_centered("パンくず %d" % int(save_data.breadcrumbs),145,24,Color("#73562d"))
	draw_centered("各項目は最大3段階・ブラウザに自動保存",205,16,Color("#536b72"))

func draw_world() -> void:
	var ground: Color = STAGES[stage_index].ground
	draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),ground)
	# Lightweight repeated scenery gives each stage a readable map without textures.
	for x in range(-1,5):
		for y in range(-1,7):
			var wp := Vector2(x*260+90,y*340+100)
			var sp := world_to_screen(wp)
			if sp.x < -120 or sp.x > 660 or sp.y < -140 or sp.y > 1080: continue
			if stage_index == 0:
				draw_tree(sp+Vector2(-70,-35),0.85)
				draw_bench(sp+Vector2(40,35))
			elif stage_index == 1:
				draw_shop(sp+Vector2(-95,-55),x+y)
				draw_sign(sp+Vector2(75,65))
			else:
				draw_rect(Rect2(sp-Vector2(95,55),Vector2(190,110)),Color("#e4edf0"))
				draw_rect(Rect2(sp-Vector2(78,35),Vector2(156,70)),Color("#7895a2"))
				draw_line(sp+Vector2(-75,0),sp+Vector2(75,0),Color.WHITE,7)
	# Roads and lane markings.
	var road_x := world_to_screen(Vector2(850,0)).x
	draw_rect(Rect2(road_x-95,0,190,get_viewport_rect().size.y),STAGES[stage_index].road)
	for yy in range(-1,8):
		var marker := world_to_screen(Vector2(850,yy*170)).y
		draw_rect(Rect2(road_x-5,marker,10,70),Color(1,1,1,0.72))
	for e in enemies: draw_enemy(e,world_to_screen(e.pos))
	for p in projectiles: draw_projectile(p,world_to_screen(p.pos))
	for p in poops: draw_falling_poop(p)
	for fx in effects: draw_effect(fx,world_to_screen(fx.pos))
	if flock_time > 0.0:
		draw_pigeon(world_to_screen(player_pos)+Vector2(-105,28),0.55,-0.2)
		draw_pigeon(world_to_screen(player_pos)+Vector2(105,28),0.55,0.2)
	draw_pigeon(world_to_screen(player_pos),0.92,player_velocity.x/450.0)
	draw_drop_gauge(world_to_screen(player_pos)+Vector2(0,66))

func draw_pigeon(p: Vector2, scale_value: float, tilt: float) -> void:
	# 2.5D low-poly look made only from layered primitives.
	var s := scale_value
	draw_set_transform(p,tilt,Vector2(s,s))
	draw_colored_polygon(PackedVector2Array([Vector2(-55,8),Vector2(-92,-5),Vector2(-70,35),Vector2(-30,34)]),Color("#818892"))
	draw_colored_polygon(PackedVector2Array([Vector2(55,8),Vector2(92,-5),Vector2(70,35),Vector2(30,34)]),Color("#747c88"))
	draw_circle(Vector2(0,12),52,Color("#aeb2bb"))
	draw_colored_polygon(PackedVector2Array([Vector2(-42,8),Vector2(0,-32),Vector2(42,8),Vector2(25,48),Vector2(-30,42)]),Color("#9a9faa"))
	draw_circle(Vector2(0,-34),34,Color("#858b97"))
	draw_arc(Vector2(0,-15),30,-2.8,-0.2,18,Color("#78a997"),13)
	draw_arc(Vector2(0,-13),26,0.15,2.95,18,Color("#8875a0"),10)
	draw_circle(Vector2(-15,-42),11,Color("#fff9e8"))
	draw_circle(Vector2(15,-42),11,Color("#fff9e8"))
	draw_circle(Vector2(-12,-42),5,Color("#292a2d"))
	draw_circle(Vector2(12,-42),5,Color("#292a2d"))
	draw_colored_polygon(PackedVector2Array([Vector2(-9,-29),Vector2(9,-29),Vector2(0,-17)]),Color("#3c4048"))
	draw_line(Vector2(-15,54),Vector2(-15,65),Color("#ee7544"),6)
	draw_line(Vector2(15,54),Vector2(15,65),Color("#ee7544"),6)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func draw_enemy(e: Dictionary, p: Vector2) -> void:
	var body := Color("#ee8f77") if e.type == "human" else (Color("#e5bd54") if e.type == "bike" else Color("#313844"))
	if float(e.flash)>0: body=Color.WHITE
	draw_circle(p,22 if e.type=="human" else 27,body)
	if e.type == "human":
		draw_circle(p+Vector2(0,-24),13,Color("#f2c6a5"))
		draw_line(p+Vector2(-12,20),p+Vector2(-18,43),Color("#45566b"),7)
		draw_line(p+Vector2(12,20),p+Vector2(18,43),Color("#45566b"),7)
	elif e.type == "bike":
		draw_arc(p+Vector2(-25,20),15,0,TAU,16,Color("#37444b"),5)
		draw_arc(p+Vector2(25,20),15,0,TAU,16,Color("#37444b"),5)
	else:
		draw_colored_polygon(PackedVector2Array([p+Vector2(-38,0),p,p+Vector2(-15,15)]),body)
		draw_colored_polygon(PackedVector2Array([p+Vector2(38,0),p,p+Vector2(15,15)]),body)
	var ratio := clampf(float(e.dirt)/float(e.max_dirt),0,1)
	draw_rect(Rect2(p+Vector2(-27,-48),Vector2(54,7)),Color("#26343a"))
	draw_rect(Rect2(p+Vector2(-25,-46),Vector2(50*ratio,3)),Color("#f3f0c0"))

func draw_falling_poop(poop: Dictionary) -> void:
	var t := clampf(float(poop.time)/float(poop.delay),0,1)
	var pos: Vector2 = poop.start.lerp(poop.target,t)
	var sp := world_to_screen(pos)
	draw_circle(world_to_screen(poop.target),18+10*t,Color(1,1,1,0.12))
	draw_circle(sp,9,Color("#faf7dc"))
	draw_circle(sp+Vector2(0,6),7,Color("#dedbbd"))

func draw_projectile(p: Dictionary, sp: Vector2) -> void:
	if p.type == "drone":
		draw_rect(Rect2(sp-Vector2(18,9),Vector2(36,18)),Color("#d64e4e"))
		draw_line(sp+Vector2(-28,-10),sp+Vector2(28,-10),Color("#27343d"),4)
	elif p.type == "umbrella":
		draw_arc(sp,22,PI,TAU,16,Color("#826ead"),12)
		draw_line(sp,sp+Vector2(0,28),Color("#4f4f55"),4)
	else:
		draw_circle(sp,12,Color("#e66d54"))

func draw_effect(fx: Dictionary, sp: Vector2) -> void:
	var alpha := clampf(float(fx.time)*2.0,0,1)
	if fx.kind == "splat":
		draw_circle(sp,float(fx.radius)*(1.0-alpha*0.25),Color(0.96,0.95,0.73,alpha*0.65))
		for a in 7: draw_circle(sp+Vector2.from_angle(a*TAU/7.0)*float(fx.radius)*0.72,8,Color(0.95,0.94,0.70,alpha))
	elif fx.kind == "hit":
		draw_arc(sp,float(fx.radius),0,TAU,24,Color(1,0.25,0.25,alpha),7)
	else:
		draw_string(font,sp+Vector2(-22,-35),"退散!",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(1,1,1,alpha))

func draw_drop_gauge(p: Vector2) -> void:
	var ratio := 1.0-clampf(drop_clock/current_drop_interval(),0,1)
	draw_arc(p,28,0,TAU,32,Color(0.12,0.18,0.2,0.45),7)
	draw_arc(p,28,-PI/2,-PI/2+TAU*ratio,32,Color("#fff2a8"),7)
	if ratio > 0.86: draw_string(font,p+Vector2(-15,7),"DROP",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("#34454c"))

func draw_tree(p: Vector2,s: float) -> void:
	draw_rect(Rect2(p+Vector2(-7,15)*s,Vector2(14,42)*s),Color("#917050"))
	draw_circle(p,37*s,Color("#6eac73"))
	draw_circle(p+Vector2(22,-12)*s,28*s,Color("#83bd79"))

func draw_bench(p: Vector2) -> void:
	draw_rect(Rect2(p-Vector2(35,12),Vector2(70,14)),Color("#a26f48"))
	draw_line(p+Vector2(-25,0),p+Vector2(-25,23),Color("#44525a"),5)
	draw_line(p+Vector2(25,0),p+Vector2(25,23),Color("#44525a"),5)

func draw_shop(p: Vector2,variant: int) -> void:
	var c: Color = [Color("#f0a9a2"),Color("#9fc9dd"),Color("#f0cf85")][abs(variant)%3]
	draw_rect(Rect2(p,Vector2(190,110)),c)
	draw_colored_polygon(PackedVector2Array([p,p+Vector2(190,0),p+Vector2(170,-35),p+Vector2(20,-35)]),c.darkened(0.18))
	for i in 4: draw_rect(Rect2(p+Vector2(12+i*45,12),Vector2(30,38)),Color("#e8f4ef"))

func draw_sign(p: Vector2) -> void:
	draw_line(p,p+Vector2(0,55),Color("#59666c"),6)
	draw_rect(Rect2(p-Vector2(25,18),Vector2(50,32)),Color("#fff2a8"))

func draw_hud() -> void:
	draw_rect(Rect2(16,18,508,90),Color(0.10,0.16,0.18,0.72),true)
	draw_string(font,Vector2(32,50),"HP %d" % ceili(maxf(hp,0)),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("#ff9a94"))
	draw_string(font,Vector2(190,50),"SCORE %05d" % score,HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color.WHITE)
	draw_string(font,Vector2(420,50),"%d:%02d" % [int(time_left)/60,int(time_left)%60],HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("#fff2a8"))
	draw_string(font,Vector2(32,83),"Lv.%d" % level,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("#d8f3ff"))
	draw_rect(Rect2(98,69,250,13),Color("#27363c"))
	draw_rect(Rect2(100,71,246*clampf(xp/xp_next,0,1),9),Color("#8bd6e8"))
	draw_string(font,Vector2(370,84),STAGES[stage_index].name,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	draw_centered("画面をドラッグして移動 / 離すと停止",930,15,Color(0.15,0.22,0.24,0.72))

func draw_level_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),Color(0.08,0.12,0.14,0.76))
	draw_centered("LEVEL UP!",115,42,Color("#fff0a4"))
	draw_centered("強化を1つ選ぼう",175,23,Color.WHITE)

func draw_result_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO,get_viewport_rect().size),Color(0.08,0.12,0.14,0.80))
	var cleared := score >= int(STAGES[stage_index].goal) and hp>0
	draw_centered("ステージクリア！" if cleared else "ざんねん…",170,43,Color("#fff0a4") if cleared else Color("#ffaaa0"))
	draw_centered(STAGES[stage_index].name,225,23,Color.WHITE)
	draw_centered("SCORE  %05d" % score,315,33,Color.WHITE)
	var stars_now := 0
	if cleared:
		for threshold in STAGES[stage_index].stars:
			if score >= int(threshold): stars_now+=1
	draw_centered("★".repeat(stars_now)+"☆".repeat(3-stars_now),390,58,Color("#ffd963"))
	draw_centered("パンくず  +%d" % (int(STAGES[stage_index].reward)*stars_now),475,24,Color("#f6e5ad"))
	draw_centered("BEST  %05d" % int(save_data.best[stage_index]),530,19,Color("#b9d8e5"))

func draw_centered(text_value: String,y: float,size: int,color: Color) -> void:
	draw_string(font,Vector2(0,y),text_value,HORIZONTAL_ALIGNMENT_CENTER,VIEW.x,size,color)

func play_tone(frequency: float,duration: float) -> void:
	var mix_rate := 22050
	var frames := int(duration*mix_rate)
	var data := PackedByteArray()
	data.resize(frames*2)
	for i in frames:
		var envelope := 1.0-float(i)/frames
		var sample := int(sin(TAU*frequency*i/mix_rate)*envelope*6500.0)
		data[i*2] = sample & 0xff
		data[i*2+1] = (sample>>8)&0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	audio_player.stream = stream
	audio_player.play()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file := FileAccess.open(SAVE_PATH,FileAccess.READ)
	if file == null: return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY: return
	if parsed.has("breadcrumbs"): save_data.breadcrumbs = int(parsed.breadcrumbs)
	if parsed.has("permanent"):
		for key in ["interval","radius","speed"]:
			if parsed.permanent.has(key): save_data.permanent[key]=clampi(int(parsed.permanent[key]),0,3)
	if parsed.has("best") and parsed.best.size()>=3: save_data.best=parsed.best.slice(0,3)
	if parsed.has("stars") and parsed.stars.size()>=3: save_data.stars=parsed.stars.slice(0,3)

func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(save_data))

func debug_run_checks() -> Array[String]:
	var errors: Array[String] = []
	if STAGES.size()!=3: errors.append("stage count")
	if UPGRADES.size()!=8: errors.append("upgrade count")
	for u in UPGRADES:
		if not u.has("id") or not u.has("name"): errors.append("upgrade schema")
	start_stage(0)
	perform_auto_drop()
	if poops.is_empty(): errors.append("auto drop")
	spawn_enemy()
	if enemies.is_empty(): errors.append("enemy spawn")
	for i in 8: upgrades[UPGRADES[i].id]=1
	if upgrade_level("storm")!=1 or upgrade_level("bread")!=1: errors.append("upgrade state")
	state = ScreenState.PLAYING
	show_level_up()
	if choice_indices.size()!=3 or buttons.size()!=3 or state!=ScreenState.LEVEL_UP: errors.append("level-up choices")
	else:
		select_upgrade(choice_indices[0])
		if state!=ScreenState.PLAYING: errors.append("level-up selection")
	for s in STAGES.size():
		start_stage(s)
		if stage_index != s or state != ScreenState.PLAYING: errors.append("stage transition %d" % s)
	finish_stage(true)
	if state != ScreenState.RESULT: errors.append("result transition")
	var previous_breadcrumbs := int(save_data.breadcrumbs)
	save_data.breadcrumbs = 77
	save_game()
	save_data.breadcrumbs = 0
	load_save()
	if int(save_data.breadcrumbs)!=77: errors.append("local save round-trip")
	save_data.breadcrumbs = previous_breadcrumbs
	save_game()
	return errors
