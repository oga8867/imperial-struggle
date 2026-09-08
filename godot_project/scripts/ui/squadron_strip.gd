extends Control

# 한 척당 원작 말 하나를 그린다. 여러 척도 영역 안에 맞추어 크기를 줄인다.
var side: int = Enums.Side.BRITAIN
var count: int = 0
var token_rects: Array[Rect2] = []
const BR = preload("res://assets/tokens/Squadron_BR.png")
const FR = preload("res://assets/tokens/Squadron_FR.png")

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func show_count(value: int) -> void:
	count = maxi(0,value)
	queue_redraw()

func _draw() -> void:
	token_rects.clear()
	if count == 0: return
	var gap = 3.0 if size.y > 20 else 1.0
	var edge = minf(size.y,(size.x-gap*(count-1))/count)
	for i in count:
		var rect = Rect2(i*(edge+gap),(size.y-edge)/2,edge,edge)
		token_rects.append(rect)
		draw_texture_rect(BR if side == Enums.Side.BRITAIN else FR,rect,false)
