extends RefCounted

# 1920×1080 논리 화면을 창 크기에 맞춰 Godot가 동일 비율로 축소한다.
# 지도 이미지와 클릭 좌표의 원점·크기를 한 곳에 두어 배치 변경 시 어긋나지 않게 한다.
const BOARD_RECT = Rect2(24,280,584.0*5100.0/3300.0,584)
const RIGHT_X = 1280.0
const RIGHT_WIDTH = 616.0
const WORK_TOP = 280.0
const WORK_BOTTOM = 1024.0

static func place(control: Control, rect: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.custom_minimum_size = Vector2.ZERO
	control.position = rect.position
	control.size = rect.size
