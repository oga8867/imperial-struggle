extends Control

# 도형 아이콘은 이모지 글꼴에 의존하지 않는다. 전체 이름·숫자를 옆에 병기한다.
# 0=승점(우승 잔), 1=조약점수(서명 문서), 2=채무(겹친 동전).
var kind = 0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var ink = Color("ebc982") if kind == 0 else (Color("9bd2c9") if kind == 1 else Color("dca384"))
	var s = minf(size.x,size.y)/24.0
	draw_set_transform(Vector2.ZERO,0,Vector2(s,s))
	if kind == 0:
		draw_colored_polygon(PackedVector2Array([Vector2(6,4),Vector2(18,4),Vector2(16,13),Vector2(12,16),Vector2(8,13)]),ink)
		draw_arc(Vector2(6,7),4,PI/2,PI*1.5,14,ink,1.7,true)
		draw_arc(Vector2(18,7),4,-PI/2,PI/2,14,ink,1.7,true)
		draw_line(Vector2(12,15),Vector2(12,20),ink,2,true)
		draw_line(Vector2(7,21),Vector2(17,21),ink,2,true)
	elif kind == 1:
		var style = StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.border_color = ink
		style.set_border_width_all(2)
		style.set_corner_radius_all(2)
		draw_style_box(style,Rect2(5,3,14,18))
		for y in [8,12]: draw_line(Vector2(8,y),Vector2(16,y),ink,1.4,true)
		draw_circle(Vector2(15,18),2.7,ink)
	else:
		# 채무의 이득·불이익은 동전 그림이 아니라 숫자의 +/− 부호로 구분한다.
		for y in [17,12,7]:
			draw_rect(Rect2(5,y-2,14,4),Color("543d30"))
			var points = PackedVector2Array()
			for i in 25:
				var a = TAU*i/24.0
				points.append(Vector2(12,y)+Vector2(cos(a)*7,sin(a)*3))
			draw_polyline(points,ink,1.5,true)
