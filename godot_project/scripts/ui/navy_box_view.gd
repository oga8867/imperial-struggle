extends Control

# 지도와 정보창의 공통 해군 표시. 귀환 예정·영구 제거 함대를 대기 말에 섞지 않는다.
const Strip = preload("res://scripts/ui/squadron_strip.gd")
var compact = false
var rows: Dictionary = {}
var _last_state: Array = []

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE if compact else MOUSE_FILTER_PASS
	for side in [Enums.Side.BRITAIN,Enums.Side.FRANCE]:
		var row = Control.new()
		row.position.y = rows.size()*(18 if compact else 74)
		row.size = Vector2(96,18) if compact else Vector2(272,72)
		row.mouse_filter = mouse_filter
		add_child(row)
		var color = Color("eb8576") if side == Enums.Side.BRITAIN else Color("80b9ed")
		var title = _label(row,Rect2(0,0,48 if compact else 80,18 if compact else 26),9 if compact else 17,color)
		var count_label = _label(row,Rect2(80,0,192,26),21,Color("ebc982"))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.visible = not compact
		var tokens = Strip.new()
		tokens.side = side
		tokens.position = Vector2(49,1) if compact else Vector2(0,27)
		tokens.size = Vector2(47,16) if compact else Vector2(272,25)
		row.add_child(tokens)
		var empty = _label(row,Rect2(0,27,272,25),15,Color("a8b4b1"))
		var details = _label(row,Rect2(0,53,272,19),14,Color("b8c6c8"))
		details.visible = not compact
		rows[side] = {"row":row,"title":title,"count":count_label,"tokens":tokens,"empty":empty,"details":details}
	refresh()

func _label(parent: Node, rect: Rect2, font_size: int, color: Color) -> Label:
	var label = Label.new()
	label.position = rect.position
	# 지도 글자는 최대 4배 확대된다. 더 큰 글리프로 생성한 뒤 축소하여
	# 9px 글자를 그대로 늘렸을 때 생기는 한글 획의 흐림을 줄인다.
	var resolution = 4 if compact else 1
	label.size = rect.size*resolution
	label.scale = Vector2.ONE/resolution
	label.add_theme_font_size_override("font_size",font_size*resolution)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _process(_delta: float) -> void:
	# PlayerState에는 함대 변경 신호가 없다. 작은 숫자 묶음만 비교해 바뀔 때만
	# 갱신한다. 행동·전쟁·귀환·저장 복원 경로의 알림 순서에 의존하지 않는다.
	var snapshot: Array = [LocaleManager.current_locale]
	if GameManager.state == null: return
	for side in rows:
		var player = GameManager.state.get_player(side)
		if player == null: return
		snapshot.append([player.squadrons_in_navy_box,player.squadrons_on_map,player.total_squadrons(),player.squadrons_removed])
	if snapshot != _last_state:
		_last_state = snapshot
		refresh()

func refresh() -> void:
	if GameManager.state == null: return
	for side in rows:
		var player = GameManager.state.get_player(side)
		if player == null: continue
		var ui = rows[side]
		var waiting = player.squadrons_in_navy_box
		var returning = player.total_squadrons()-waiting-player.squadrons_on_map
		ui.title.text = ("%s · %d" % [LocaleManager.side(side),waiting]) if compact else LocaleManager.side(side)
		ui.count.text = LocaleManager.tx("대기 %d척") % waiting
		ui.tokens.show_count(waiting)
		ui.empty.visible = waiting == 0 and not compact
		ui.empty.text = LocaleManager.tx("대기 함대 없음")
		ui.details.text = LocaleManager.tx("지도 %d · 미건조 %d") % [player.squadrons_on_map,maxi(0,player.max_squadrons()-player.total_squadrons())]
		if not compact:
			ui.row.tooltip_text = LocaleManager.tx("해군 상자: 지금 배치 가능한 함대 %d척\n귀환 예정 %d척 · 영구 제거 %d척") % [waiting,returning,player.squadrons_removed]
