extends RefCounted

# 원작 지도에 읽기 쉬운 제목과 진영 선택을 겹친다. 그림은 기존 자산을 재사용한다.
static func decorate(menu: Control) -> void:
	var background: ColorRect = menu.get_node("Background")
	background.color = Color("101a20")
	var map = TextureRect.new()
	map.texture = load("res://assets/board/Imperial Struggle Map_Final-150-Clean.png")
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(map)
	var material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ vec4 tex = texture(TEXTURE, UV); float shade = smoothstep(0.20, 0.85, UV.x); float edge = smoothstep(0.0,0.22,UV.y)*smoothstep(1.0,0.70,UV.y); vec3 paper=tex.rgb*vec3(0.72,0.75,0.69); COLOR=vec4(mix(vec3(0.063,0.102,0.125),paper,shade*edge*0.65),1.0); }"
	material.shader = shader
	map.material = material
	var center: CenterContainer = menu.get_node("CenterContainer")
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -1050
	center.offset_left = 80
	var body: VBoxContainer = center.get_node("VBox")
	body.custom_minimum_size.x = 580
	body.add_theme_constant_override("separation",14)
	var eyebrow = Label.new()
	eyebrow.text = "1697 — 1789    /    THE SECOND HUNDRED YEARS’ WAR"
	eyebrow.add_theme_color_override("font_color",Color("c6ac78"))
	eyebrow.add_theme_font_size_override("font_size",16)
	body.add_child(eyebrow)
	body.move_child(eyebrow,0)
	for label_name in ["Title","Subtitle"]:
		body.get_node(label_name).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.get_node("Spacer").custom_minimum_size.y = 10
	for node in body.get_children():
		if node is Button:
			node.alignment = HORIZONTAL_ALIGNMENT_LEFT
			node.custom_minimum_size = Vector2(580,52)
			node.add_theme_font_size_override("font_size",19)
	var note = Label.new()
	note.text = LocaleManager.tx("두 제국. 네 개의 전쟁. 한 세기의 패권.\n투자와 외교, 무역과 전쟁으로 역사를 바꾸세요.")
	note.add_theme_color_override("font_color",Color("a8b2b1"))
	note.add_theme_font_size_override("font_size",19)
	body.add_child(note)
	body.move_child(note,3)
	var footer = Label.new()
	footer.text = LocaleManager.tx("IMPERIAL STRUGGLE   ·   Ananda Gupta & Jason Matthews   ·   GMT Games\n개인 플레이용 디지털 프로젝트")
	footer.position = Vector2(100,984)
	footer.add_theme_font_size_override("font_size",14)
	footer.add_theme_color_override("font_color",Color("9faaa8"))
	menu.add_child(footer)
	var rule = ColorRect.new()
	rule.position = Vector2(100,961)
	rule.size = Vector2(580,1)
	rule.color = Color("786f55")
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(rule)
