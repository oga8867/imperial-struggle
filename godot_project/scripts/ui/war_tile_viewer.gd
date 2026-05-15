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
	visible = false
	close_btn.pressed.connect(_on_close)


func show_for(side: Enums.Side, _upgrade_mode: bool = false) -> void:
	viewer_side = side
	upgrade_mode = _upgrade_mode
	selected_theater_id = ""
	drawn_tile = null
	viewing_war_id = WarManager.get_upcoming_war_id()
	visible = true
	_refresh()


func _refresh() -> void:
	for child in theaters_box.get_children():
		child.queue_free()

	# Use viewing_war_id (allows browsing future wars)
	if viewing_war_id == "":
		viewing_war_id = WarManager.get_upcoming_war_id()
	if viewing_war_id == "":
		title_label.text = "No War in Progress"
		return
	if not (viewing_war_id in WarManager.wars):
		title_label.text = "Unknown war"
		return

	var war: WarData = WarManager.wars[viewing_war_id]
	var side_name := "Britain" if viewer_side == Enums.Side.BRITAIN else "France"
	var current_war_id := WarManager.get_upcoming_war_id()
	var is_current := viewing_war_id == current_war_id

	if upgrade_mode:
		if drawn_tile == null:
			title_label.text = "%s — Military Upgrade: pick a theater" % side_name
		else:
			title_label.text = "%s — Drew strength %+d. Swap?" % [side_name, drawn_tile.strength]
	else:
		var prefix := "[CURRENT] " if is_current else "[Preview] "
		title_label.text = "%s%s — %s" % [prefix, side_name, war.name]

	# War navigation tabs (browse all wars)
	if not upgrade_mode:
		theaters_box.add_child(_make_war_nav_row())

	# Theater rows for the selected war
	for theater in war.theaters:
		theaters_box.add_child(_make_theater_row(theater, is_current))

	pool_label.text = "Basic Pool: %d  |  Bonus Pool: %d" % [
		WarManager.basic_war_tiles.get(viewer_side, []).size(),
		WarManager.bonus_tile_pool.get(viewer_side, []).size()]
	info_label.text = ""


func _make_war_nav_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = "View war: "
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.74, 0.78))
	row.add_child(lbl)
	for war_key in ["spanish_succession", "austrian_succession", "seven_years", "american_independence"]:
		if not (war_key in WarManager.wars):
			continue
		var btn := Button.new()
		var w: WarData = WarManager.wars[war_key]
		btn.text = w.name
		btn.add_theme_font_size_override("font_size", 11)
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
	title.text = "[Future] %s — Theaters:" % war.name
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
	name_lbl.text = theater.name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	hbox.add_child(name_lbl)

	# Show tile info only for the CURRENT war (future wars haven't been set up yet)
	if is_current_war:
		var basic_tile = WarManager.basic_tile_in_theater.get(theater.id, {}).get(viewer_side)
		var basic_lbl := Label.new()
		basic_lbl.custom_minimum_size = Vector2(150, 0)
		if basic_tile:
			basic_lbl.text = "Basic: " + _format_tile(basic_tile)
		else:
			basic_lbl.text = "Basic: -"
		basic_lbl.tooltip_text = _tile_tooltip(basic_tile) if basic_tile else ""
		hbox.add_child(basic_lbl)

		var bonus_tiles: Array = WarManager.bonus_war_tiles_in_theater.get(theater.id, {}).get(viewer_side, [])
		var bonus_lbl := Label.new()
		bonus_lbl.custom_minimum_size = Vector2(180, 0)
		if bonus_tiles.size() > 0:
			var parts: Array[String] = []
			for t in bonus_tiles:
				parts.append(_format_tile(t))
			bonus_lbl.text = "Bonus: " + ", ".join(parts)
		else:
			bonus_lbl.text = "Bonus: -"
		hbox.add_child(bonus_lbl)

		var opp: Enums.Side = Enums.Side.FRANCE if viewer_side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
		var opp_basic = WarManager.basic_tile_in_theater.get(theater.id, {}).get(opp)
		var opp_bonus_count = WarManager.bonus_war_tiles_in_theater.get(theater.id, {}).get(opp, []).size()
		var opp_lbl := Label.new()
		opp_lbl.custom_minimum_size = Vector2(160, 0)
		opp_lbl.text = "Enemy: %s + %d bonus" % ["[hidden]" if opp_basic else "-", opp_bonus_count]
		opp_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		hbox.add_child(opp_lbl)
	else:
		var preview := Label.new()
		preview.text = "(future war — tiles not placed yet)"
		preview.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
		preview.add_theme_font_size_override("font_size", 11)
		hbox.add_child(preview)

	if upgrade_mode and drawn_tile == null and is_current_war:
		var pick_btn := Button.new()
		pick_btn.text = "Upgrade Here"
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
		info.text = "Drew: %s — Current here: %s. Choose:" % [
			_format_tile(drawn_tile),
			_format_tile(current_t) if current_t else "-"]
		info.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
		dec_vb.add_child(info)
		# Swap row
		var swap_row := HBoxContainer.new()
		swap_row.add_theme_constant_override("separation", 6)
		var swap_keep := Button.new()
		swap_keep.text = "Swap & RETURN old to pool"
		swap_keep.pressed.connect(_on_upgrade_decision.bind(true, false))
		swap_row.add_child(swap_keep)
		var swap_remove := Button.new()
		swap_remove.text = "Swap & REMOVE old from game"
		swap_remove.disabled = not _can_remove_one(viewer_side)
		swap_remove.pressed.connect(_on_upgrade_decision.bind(true, true))
		swap_row.add_child(swap_remove)
		dec_vb.add_child(swap_row)
		# Keep row
		var keep_row := HBoxContainer.new()
		keep_row.add_theme_constant_override("separation", 6)
		var keep_return := Button.new()
		keep_return.text = "Keep current & RETURN drawn"
		keep_return.pressed.connect(_on_upgrade_decision.bind(false, false))
		keep_row.add_child(keep_return)
		var keep_remove := Button.new()
		keep_remove.text = "Keep current & REMOVE drawn"
		keep_remove.disabled = not _can_remove_one(viewer_side)
		keep_remove.pressed.connect(_on_upgrade_decision.bind(false, true))
		keep_row.add_child(keep_remove)
		dec_vb.add_child(keep_row)
		vb.add_child(decision_panel)

	# Spoils row: shows what each victory margin gives
	var spoils_lbl := Label.new()
	spoils_lbl.text = _format_spoils(theater)
	spoils_lbl.add_theme_font_size_override("font_size", 11)
	spoils_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	spoils_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(spoils_lbl)

	# Bonus strength sources
	var bonus_lbl2 := Label.new()
	bonus_lbl2.text = "Bonus Strength: " + _format_bonus_keys(theater)
	bonus_lbl2.add_theme_font_size_override("font_size", 11)
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
		for r in winner_arr: w_parts.append(str(r))
		var l_parts: Array[String] = []
		for r in loser_arr: l_parts.append(str(r))
		var w_str = ", ".join(w_parts) if w_parts.size() > 0 else "-"
		var l_str = ", ".join(l_parts) if l_parts.size() > 0 else "-"
		parts.append("%s ⇒ Win[%s] / Lose[%s]" % [margin, w_str, l_str])
	return "Spoils: " + "  ;  ".join(parts)


func _format_tile(tile: WarTile) -> String:
	# Compact: "+2", "+1[D]" (Debt), "-1[U]" (Unflag), "0[F]" (Fort/Squadron)
	var s := "%+d" % tile.strength
	match tile.special_effect:
		WarTile.SpecialEffect.DEBT: s += "[D]"
		WarTile.SpecialEffect.UNFLAG: s += "[U]"
		WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON: s += "[F]"
	return s


func _tile_tooltip(tile: WarTile) -> String:
	var s := "Strength %+d" % tile.strength
	match tile.special_effect:
		WarTile.SpecialEffect.DEBT: s += "\nEffect: Opponent takes 1 Debt"
		WarTile.SpecialEffect.UNFLAG: s += "\nEffect: Unflag opposing Market or Political space in theater region"
		WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON: s += "\nEffect: Damage opposing Fort OR remove opposing Squadron in theater"
	return s


func _format_bonus_keys(theater: TheaterData) -> String:
	var pretty: Array[String] = []
	for k in theater.bonus_strength_keys:
		pretty.append(k.replace("_", " "))
	return ", ".join(pretty) if pretty.size() > 0 else "-"


func _on_pick_theater(theater_id: String) -> void:
	selected_theater_id = theater_id
	# Draw a new basic tile
	var pool: Array = WarManager.basic_war_tiles[viewer_side]
	if pool.is_empty():
		info_label.text = "Basic war tile pool empty!"
		return
	pool.shuffle()
	drawn_tile = pool.pop_back()
	_refresh()


func _can_remove_one(side: Enums.Side) -> bool:
	# Per §5.3.3: can't remove if it would leave fewer than 4 basic tiles total
	# Total = pool + tiles in theaters
	var pool_count: int = WarManager.basic_war_tiles.get(side, []).size()
	var theater_count := 0
	for tid in WarManager.basic_tile_in_theater:
		if WarManager.basic_tile_in_theater[tid].get(side) != null:
			theater_count += 1
	return (pool_count + theater_count) > 4


func _on_upgrade_decision(swap: bool, remove_from_game: bool) -> void:
	# Per §5.3.3: player chooses swap or keep, AND chooses whether to remove or return discarded tile
	var current_t = WarManager.basic_tile_in_theater[selected_theater_id].get(viewer_side)
	var discarded: WarTile = null
	if swap:
		WarManager.basic_tile_in_theater[selected_theater_id][viewer_side] = drawn_tile
		discarded = current_t
	else:
		discarded = drawn_tile
	if discarded != null:
		if remove_from_game and _can_remove_one(viewer_side):
			# Permanently removed — do not add back to pool
			if has_node("/root/GameLog"):
				GameLog.log_entry(viewer_side, "upgrade", "%s tile (removed from game)" % ("swapped" if swap else "kept; drew"))
		else:
			WarManager.basic_war_tiles[viewer_side].append(discarded)
			if has_node("/root/GameLog"):
				GameLog.log_entry(viewer_side, "upgrade", "%s tile (returned to pool)" % ("swapped" if swap else "kept; drew"))
	upgrade_mode = false
	drawn_tile = null
	selected_theater_id = ""
	upgrade_done.emit()
	visible = false


func _on_close() -> void:
	visible = false
	closed.emit()
