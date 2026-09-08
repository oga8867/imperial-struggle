extends Control

# War Tile Viewer: shows all your basic+bonus tiles for the upcoming war,
# plus the opponent's count (face down). Also handles Military Upgrade.

signal closed
signal upgrade_done

@onready var title_label: Label = $Panel/VBox/Title
@onready var theaters_box: VBoxContainer = $Panel/VBox/Scroll/Theaters
@onready var pool_label: Label = $Panel/VBox/PoolLabel
@onready var info_label: Label = $Panel/VBox/InfoLabel
@onready var close_btn: Button = $Panel/VBox/CloseBtn

var viewer_side: Enums.Side = Enums.Side.NONE
var upgrade_mode: bool = false
var selected_theater_id: String = ""
var drawn_tile: WarTile = null
var viewing_war_id: String = ""  # currently shown war (default = current/upcoming)


func _ready() -> void:
	$Panel/VBox/Scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	visible = false
	close_btn.pressed.connect(_on_close)
	close_btn.text = LocaleManager.t("btn_close")
	LocaleManager.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_new_locale: String) -> void:
	close_btn.text = LocaleManager.t("btn_close")
	if visible:
		_refresh()


func show_for(side: Enums.Side, _upgrade_mode: bool = false) -> void:
	viewer_side = side
	upgrade_mode = _upgrade_mode
	if upgrade_mode and GameManager.state.current_turn == 6:
		ActionController.begin_upgrade()
		return
	if upgrade_mode and not ActionController.can_upgrade() and ActionController.upgrade_drawn == null: return
	selected_theater_id = ActionController.upgrade_theater if upgrade_mode else ""
	drawn_tile = ActionController.upgrade_drawn if upgrade_mode else null
	viewing_war_id = WarManager.get_upcoming_war_id()
	visible = true
	_refresh()


func _refresh() -> void:
	for child in theaters_box.get_children():
		theaters_box.remove_child(child)
		child.queue_free()

	# Use viewing_war_id (allows browsing future wars)
	if viewing_war_id == "":
		viewing_war_id = WarManager.get_upcoming_war_id()
	if viewing_war_id == "":
		title_label.text = LocaleManager.t("war_no_war")
		return
	if not (viewing_war_id in WarManager.wars):
		title_label.text = LocaleManager.t("war_unknown")
		return

	var war: WarData = WarManager.wars[viewing_war_id]
	var side_name := LocaleManager.side(viewer_side)
	var current_war_id := WarManager.get_upcoming_war_id()
	var is_current := viewing_war_id == current_war_id

	if upgrade_mode:
		if drawn_tile == null:
			title_label.text = LocaleManager.tf("war_upgrade_pick_theater", [side_name])
		else:
			title_label.text = LocaleManager.tf("war_upgrade_drew", [side_name, drawn_tile.strength])
	else:
		if is_current:
			title_label.text = LocaleManager.tf("war_viewer_current", [side_name, war.name])
		else:
			title_label.text = LocaleManager.tf("war_viewer_future", [side_name, war.name])

	# War navigation tabs (browse all wars)
	if not upgrade_mode:
		theaters_box.add_child(_make_war_nav_row())

	# Theater rows for the selected war
	for theater in war.theaters:
		theaters_box.add_child(_make_theater_row(theater, is_current))

	pool_label.text = LocaleManager.tf("war_pool_label", [
		WarManager.basic_war_tiles.get(viewer_side, []).size(),
		WarManager.bonus_tile_pool.get(viewer_side, []).size()])
	info_label.text = ""


func _make_war_nav_row() -> Control:
	# 영어 전쟁 이름은 길다. 두 열로 줄바꿈하여 탐색 버튼이 창을 넓히지 않게 한다.
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation",8)
	row.add_theme_constant_override("v_separation",8)
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = LocaleManager.t("war_nav_label")
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.74, 0.78))
	lbl.queue_free()
	for war_key in ["spanish_succession", "austrian_succession", "seven_years", "american_independence"]:
		if not (war_key in WarManager.wars):
			continue
		var btn := Button.new()
		var w: WarData = WarManager.wars[war_key]
		btn.text = LocaleManager.local_name(w.name,w.name_ko)
		btn.add_theme_font_size_override("font_size", 15)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 48
		btn.disabled = (war_key == viewing_war_id)
		btn.pressed.connect(_on_war_tab.bind(war_key))
		row.add_child(btn)
	return row


func _on_war_tab(war_id: String) -> void:
	viewing_war_id = war_id
	_refresh()


func _make_future_war_summary(war: WarData) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 50)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	var title := Label.new()
	title.text = LocaleManager.tf("war_future_summary", [war.name])
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	vb.add_child(title)
	var th_names: Array[String] = []
	for t in war.theaters:
		th_names.append(t.name)
	var th_lbl := Label.new()
	th_lbl.text = " · ".join(th_names)
	th_lbl.add_theme_font_size_override("font_size", 11)
	th_lbl.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	th_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(th_lbl)
	return panel


func _make_theater_row(theater: TheaterData, is_current_war: bool = true) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 100)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# Header row: theater name + tiles
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	vb.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.custom_minimum_size = Vector2(180, 0)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.text = LocaleManager.local_name(theater.name,theater.name_ko)
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	hbox.add_child(name_lbl)

	# Show tile info only for the CURRENT war (future wars haven't been set up yet)
	if is_current_war:
		var basic_tile = WarManager.basic_tile_in_theater.get(theater.id, {}).get(viewer_side)
		var basic_lbl := Label.new()
		basic_lbl.custom_minimum_size = Vector2(150, 0)
		basic_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		basic_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if basic_tile:
			basic_lbl.text = LocaleManager.tf("war_basic_label", [_format_tile(basic_tile)])
		else:
			basic_lbl.text = LocaleManager.t("war_basic_none")
		basic_lbl.tooltip_text = _tile_tooltip(basic_tile) if basic_tile else ""
		hbox.add_child(basic_lbl)

		var bonus_tiles: Array = WarManager.bonus_war_tiles_in_theater.get(theater.id, {}).get(viewer_side, [])
		var bonus_lbl := Label.new()
		bonus_lbl.custom_minimum_size = Vector2(180, 0)
		bonus_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bonus_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if bonus_tiles.size() > 0:
			var parts: Array[String] = []
			for t in bonus_tiles:
				parts.append(_format_tile(t))
			bonus_lbl.text = LocaleManager.tf("war_bonus_label", [", ".join(parts)])
		else:
			bonus_lbl.text = LocaleManager.t("war_bonus_none")
		hbox.add_child(bonus_lbl)

		var opp: Enums.Side = Enums.Side.FRANCE if viewer_side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
		var opp_basic = WarManager.basic_tile_in_theater.get(theater.id, {}).get(opp)
		var opp_bonus_count = WarManager.bonus_war_tiles_in_theater.get(theater.id, {}).get(opp, []).size()
		var opp_lbl := Label.new()
		opp_lbl.custom_minimum_size = Vector2(160, 0)
		opp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		opp_lbl.text = LocaleManager.tf("war_enemy_label", [
			LocaleManager.t("war_hidden") if opp_basic else "-", opp_bonus_count])
		opp_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		hbox.add_child(opp_lbl)
	else:
		var preview := Label.new()
		preview.text = LocaleManager.t("war_future_note")
		preview.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
		preview.add_theme_font_size_override("font_size", 11)
		hbox.add_child(preview)

	if upgrade_mode and drawn_tile == null and is_current_war:
		var pick_btn := Button.new()
		pick_btn.text = LocaleManager.t("war_pick_theater")
		pick_btn.pressed.connect(_on_pick_theater.bind(theater.id))
		hbox.add_child(pick_btn)
		# Old swap/keep buttons removed — now handled by 4-button upgrade decision UI below
		pass

	# Upgrade decision UI (swap/keep + remove/return) — only for selected theater in upgrade mode
	if upgrade_mode and drawn_tile != null and theater.id == selected_theater_id and is_current_war:
		var current_t = WarManager.basic_tile_in_theater.get(theater.id, {}).get(viewer_side)
		var decision_panel := PanelContainer.new()
		var dec_vb := VBoxContainer.new()
		dec_vb.add_theme_constant_override("separation", 4)
		decision_panel.add_child(dec_vb)
		var info := Label.new()
		info.text = LocaleManager.tf("war_drew_current", [
			_format_tile(drawn_tile),
			_format_tile(current_t) if current_t else "-"])
		info.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
		dec_vb.add_child(info)
		# Swap row
		var swap_row := HBoxContainer.new()
		swap_row.add_theme_constant_override("separation", 6)
		var swap_keep := Button.new()
		swap_keep.text = LocaleManager.t("war_swap_return")
		swap_keep.pressed.connect(_on_upgrade_decision.bind(true, false))
		swap_row.add_child(swap_keep)
		var swap_remove := Button.new()
		swap_remove.text = LocaleManager.t("war_swap_remove")
		swap_remove.disabled = not _can_remove_one(viewer_side)
		swap_remove.pressed.connect(_on_upgrade_decision.bind(true, true))
		swap_row.add_child(swap_remove)
		dec_vb.add_child(swap_row)
		# Keep row
		var keep_row := HBoxContainer.new()
		keep_row.add_theme_constant_override("separation", 6)
		var keep_return := Button.new()
		keep_return.text = LocaleManager.t("war_keep_return")
		keep_return.pressed.connect(_on_upgrade_decision.bind(false, false))
		keep_row.add_child(keep_return)
		var keep_remove := Button.new()
		keep_remove.text = LocaleManager.t("war_keep_remove")
		keep_remove.disabled = not _can_remove_one(viewer_side)
		keep_remove.pressed.connect(_on_upgrade_decision.bind(false, true))
		keep_row.add_child(keep_remove)
		dec_vb.add_child(keep_row)
		vb.add_child(decision_panel)

	# Spoils row: shows what each victory margin gives
	var spoils_lbl := Label.new()
	spoils_lbl.text = _format_spoils(theater)
	spoils_lbl.add_theme_font_size_override("font_size", 15)
	spoils_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	spoils_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(spoils_lbl)

	# Bonus strength sources
	var bonus_lbl2 := Label.new()
	bonus_lbl2.text = LocaleManager.tf("war_bonus_str_label", [_format_bonus_keys(theater)])
	bonus_lbl2.add_theme_font_size_override("font_size", 15)
	bonus_lbl2.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	bonus_lbl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(bonus_lbl2)

	return panel


func _format_spoils(theater: TheaterData) -> String:
	var parts: Array[String] = []
	for row in theater.spoils_table:
		var margin = row.get("margin", "?")
		var winner_arr = row.get("winner", [])
		var loser_arr = row.get("loser", [])
		var w_parts: Array[String] = []
		for r in winner_arr: w_parts.append(_reward_name(str(r)))
		var l_parts: Array[String] = []
		for r in loser_arr: l_parts.append(_reward_name(str(r)))
		var w_str = ", ".join(w_parts) if w_parts.size() > 0 else "-"
		var l_str = ", ".join(l_parts) if l_parts.size() > 0 else "-"
		parts.append(LocaleManager.tf("war_win_lose", [margin, w_str, l_str]))
	return LocaleManager.tf("war_spoils_label", ["\n".join(parts)])


func _reward_name(value: String) -> String:
	if value.ends_with("vp"): return value.trim_suffix("vp")+" VP"
	if value.ends_with("tp"): return value.trim_suffix("tp")+LocaleManager.tx(" 조약점수")
	if value.ends_with("cp"): return value.trim_suffix("cp")+LocaleManager.tx(" 정복점수")
	var names={"unflag_market_north_america":LocaleManager.tx("북미 시장 제거"),"unflag_market_caribbean":LocaleManager.tx("카리브 시장 제거"),"unflag_market_india":LocaleManager.tx("인도 시장 제거"),"unflag_political_europe":LocaleManager.tx("유럽 정치 깃발 제거"),"unbuild_squadron":LocaleManager.tx("함대 1척 해체"),"atlantic_dominance":LocaleManager.tx("대서양 우세"),"usa":LocaleManager.tx("미국 독립"),"canada":LocaleManager.tx("캐나다 미국 깃발"),"jacobite_defeat":LocaleManager.tx("재커바이트 패배"),"jacobite_victory":LocaleManager.tx("재커바이트 승리")}
	return names.get(value,value)

func _format_tile(tile: WarTile) -> String:
	# Compact: "+2", "+1[D]" (Debt), "-1[U]" (Unflag), "0[F]" (Fort/Squadron)
	var s := "%+d" % tile.strength
	match tile.special_effect:
		WarTile.SpecialEffect.DEBT: s += LocaleManager.tx(" [부채]")
		WarTile.SpecialEffect.UNFLAG: s += LocaleManager.tx(" [깃발 제거]")
		WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON: s += LocaleManager.tx(" [군사 피해]")
	return s


func _tile_tooltip(tile: WarTile) -> String:
	var s := LocaleManager.tf("war_strength_tooltip", [tile.strength])
	match tile.special_effect:
		WarTile.SpecialEffect.DEBT: s += LocaleManager.t("war_effect_debt")
		WarTile.SpecialEffect.UNFLAG: s += LocaleManager.t("war_effect_unflag")
		WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON: s += LocaleManager.t("war_effect_fort")
	return s


func _format_bonus_keys(theater: TheaterData) -> String:
	var pretty: Array[String] = []
	for k in theater.bonus_strength_keys:
		var names={"alliance_austria":LocaleManager.tx("오스트리아 동맹"),"alliance_bavaria":LocaleManager.tx("바이에른 동맹"),"alliance_denmark":LocaleManager.tx("덴마크 동맹"),"alliance_dutch_republic":LocaleManager.tx("네덜란드 동맹"),"alliance_german_states":LocaleManager.tx("독일 동맹"),"alliance_savoy":LocaleManager.tx("사보이 동맹"),"alliance_sardinia":LocaleManager.tx("사르데냐 동맹"),"alliance_spain":LocaleManager.tx("스페인 동맹"),"alliance_scotland":LocaleManager.tx("스코틀랜드 동맹"),"alliance_ireland":LocaleManager.tx("아일랜드 동맹"),"conflict_marker":LocaleManager.tx("상대 분쟁"),"keyword_governance":LocaleManager.tx("통치"),"keyword_style":LocaleManager.tx("양식"),"keyword_mercantilism":LocaleManager.tx("중상주의"),"keyword_scholarship":LocaleManager.tx("학문"),"keyword_finance":LocaleManager.tx("금융"),"squadron_europe":LocaleManager.tx("유럽 함대"),"squadron_north_america":LocaleManager.tx("북미 함대"),"fort_north_america":LocaleManager.tx("북미 요새"),"fort_india":LocaleManager.tx("인도 요새"),"squadron_india":LocaleManager.tx("인도 함대"),"squadron_caribbean":LocaleManager.tx("카리브 함대")}
		pretty.append(names.get(k,k.replace("_", " ")))
	return ", ".join(pretty) if pretty.size() > 0 else "-"


func _on_pick_theater(theater_id: String) -> void:
	if not ActionController.begin_upgrade(theater_id): return
	selected_theater_id = ActionController.upgrade_theater
	drawn_tile = ActionController.upgrade_drawn
	_refresh()

func _can_remove_one(_side: Enums.Side) -> bool:
	return ActionController.can_remove_upgrade_tile()

func _on_upgrade_decision(swap: bool, remove_from_game: bool) -> void:
	if not ActionController.finish_upgrade(swap,remove_from_game): return
	upgrade_mode = false
	drawn_tile = null
	upgrade_done.emit()
	hide()

func _on_close() -> void:
	if upgrade_mode and drawn_tile != null:
		info_label.text = LocaleManager.tx("뽑은 타일의 교체·유지 선택을 먼저 완료하세요.")
		return
	hide()
	closed.emit()
