extends Node2D

@onready var page_front:Sprite2D = $PageFront
@onready var page_back:Sprite2D  = $PageBack
@onready var sfx:AudioStreamPlayer = $TurnSfx

var flipping := false
var drag_active := false
var drag_start := Vector2.ZERO
var drag_progress := 0.0
var drag_dir := 0

const COMPLETE_THRESHOLD := 0.45

func _ready():
	TaskManager.page_changed.connect(_on_page_changed)
	_refresh_visuals()

func _input(event):
	if flipping: return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local := to_local(event.position)
		if event.pressed:
			if !_point_on_page(local): return
			drag_active = true
			drag_start = local
			drag_dir = 1 if local.x > _page_size().x * 0.5 else -1
			_set_shader_dir(drag_dir)
		else:
			if drag_active:
				drag_active = false
				if drag_progress >= COMPLETE_THRESHOLD and _can_flip(drag_dir):
					_animate_flip_to(1.0, func():
						if drag_dir == 1: TaskManager.next_page() else: TaskManager.prev_page()
						flipping = false
						drag_progress = 0.0
						_reset_shader()
					)
				else:
					_animate_flip_to(0.0, func():
						flipping = false
						drag_progress = 0.0
						_reset_shader()
					)

	elif event is InputEventMouseMotion and drag_active:
		var local := to_local(event.position)
		var dx := abs(local.x - drag_start.x)
		drag_progress = clamp(dx / (_page_size().x * 0.9), 0.0, 1.0)
		if _can_flip(drag_dir): _set_shader_progress(drag_progress)
		else: _set_shader_progress(min(drag_progress, 0.2))

func _page_size() -> Vector2:
	if page_front.texture == null: return Vector2(1,1)
	return page_front.texture.get_size() * page_front.scale

func _page_rect() -> Rect2:
	var sz := _page_size()
	return Rect2(Vector2.ZERO, sz)

func _point_on_page(p:Vector2) -> bool:
	return _page_rect().has_point(p)

func _can_flip(dir:int) -> bool:
	if dir == 1:
		return TaskManager.is_page_cleared(TaskManager.current_page) and TaskManager.current_page < TaskManager.get_page_count()-1
	else:
		return TaskManager.current_page > 0

func _on_page_changed(_p:int) -> void:
	_refresh_visuals()

func _refresh_visuals() -> void:
	var idx := TaskManager.current_page
	var next_idx := clamp(idx + 1, 0, TaskManager.get_page_count()-1)
	page_front.texture = TaskManager.get_page_texture(idx)
	page_back.texture  = TaskManager.get_page_texture(next_idx)
	_reset_shader()

func _reset_shader():
	for n in [page_front]:
		var mat := n.material
		if mat is ShaderMaterial:
			mat.set_shader_parameter("u_progress", 0.0)
			mat.set_shader_parameter("u_direction", 1.0)

func _set_shader_dir(dir:int):
	var mat := page_front.material
	if mat is ShaderMaterial:
		mat.set_shader_parameter("u_direction", float(dir))

func _set_shader_progress(p:float):
	var mat := page_front.material
	if mat is ShaderMaterial:
		mat.set_shader_parameter("u_progress", clamp(p, 0.0, 1.0))

func _animate_flip_to(target:float, on_done:Callable):
	flipping = true
	if sfx: sfx.play()
	var mat := page_front.material
	if mat is ShaderMaterial:
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_method(_set_shader_progress, drag_progress, target, 0.35)
		tw.finished.connect(on_done)
	else:
		# fallback: легкий поворот спрайту
		var sz := _page_size()
		page_front.pivot_offset = Vector2(sz.x if drag_dir == 1 else 0.0, sz.y * 0.5)
		var tw2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var angle := ((-165 if drag_dir == 1 else 165) if target > 0.5 else 0)
		tw2.tween_property(page_front, "rotation_degrees", angle, 0.3)
		tw2.finished.connect(on_done)
