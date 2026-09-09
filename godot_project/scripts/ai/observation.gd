extends RefCounted

# 정보 집합: 내 손패와 공개 정보가 같은 두 판은 같은 seed로 같은 관찰을 만든다.
# 실제 판은 Codec으로 먼저 복제한다. 이 함수는 원본 Resource/전역 RNG를 바꾸지 않는다.
const Codec = preload("res://scripts/models/session_codec.gd")

static func build(side: int, sample_seed: int) -> Dictionary:
	var raw = SaveLoad.capture_model()
	# 실행 취소 기록에는 과거의 양쪽 손패도 들어 있으므로 관찰에서 아예 제외한다.
	raw.ActionController = raw.ActionController.duplicate()
	raw.ActionController._undo_stack = []
	raw.GameLog = {"entries":[], "current_turn_section":1}
	var copy = Codec.new().decode(Codec.new().encode(raw))
	var rng = RandomNumberGenerator.new()
	rng.seed = sample_seed
	var st = copy.GameManager.state
	var opponent = WarManager._opp(side)
	var other = st.get_player(opponent)
	var known = []
	for c in st.get_player(side).hand + st.event_discard_pile + st.event_played_pile + copy.GameManager._pending_discards.get(side,[]): known.append(c.id)
	var candidates = []
	for c in GameData.events:
		# 제국 시대에는 왕위계승 카드도 남는다. 혁명 시대부터 왕위계승 카드가
		# 퇴장한다 (§4.1.1). 현재 시대 카드만 넣으면 중반 손패/덱 수가 줄어든다.
		var allowed=c.era<=st.current_era and not (st.current_era==Enums.Era.REVOLUTION and c.era==Enums.Era.SUCCESSION)
		if allowed and c.id not in known: candidates.append(c.duplicate(true))
	shuffle(candidates,rng)
	var hand_count = other.hand.size()
	var deck_count = st.event_draw_pile.size()
	var discard_count = copy.GameManager._pending_discards.get(opponent,[]).size()
	other.hand.clear()
	for i in hand_count:
		if not candidates.is_empty(): other.hand.append(candidates.pop_back())
	if copy.GameManager._pending_discards.has(opponent):
		copy.GameManager._pending_discards[opponent] = []
		for i in discard_count:
			if not candidates.is_empty(): copy.GameManager._pending_discards[opponent].append(candidates.pop_back())
	st.event_draw_pile.clear()
	for i in deck_count:
		if not candidates.is_empty(): st.event_draw_pile.append(candidates.pop_back())
	# 지도·손패에 중복 참조되지 않는 미공개 내각의 선택 플래그도 지운다.
	var hidden_count = other.ministry_cards.filter(func(c): return not c.is_revealed).size()
	other.ministry_cards.assign(other.ministry_cards.filter(func(c): return c.is_revealed))
	var ministries = []
	for c in copy.GameData.ministries:
		if c.side != opponent or c.is_revealed: continue
		c.is_in_play = false
		c.exhausted_abilities.clear()
		if c.is_available_in_era(st.current_era): ministries.append(c)
	shuffle(ministries,rng)
	for i in mini(hidden_count,ministries.size()):
		ministries[i].is_in_play = true
		other.ministry_cards.append(ministries[i])
	# 비공개 전쟁 타일은 인쇄된 구성표에서 새로 뽑는다. 상대의 실제 풀조차 읽지 않는다.
	var wm = copy.WarManager
	var basic = []
	for cfg in [[4,0,1],[4,1,0],[3,2,0],[3,-1,3],[2,0,2]]:
		for i in cfg[0]:
			var tile = WarTile.new()
			tile.side = opponent
			tile.tile_type = WarTile.TileType.BASIC
			tile.strength = cfg[1]
			tile.special_effect = cfg[2]
			basic.append(tile)
	var bonus = []
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/war_tiles.json")):
		if entry.war != wm.current_war_id or int(entry.side) != opponent: continue
		var tile = WarTile.new()
		tile.id = entry.id
		tile.side = opponent
		tile.tile_type = WarTile.TileType.BONUS
		tile.strength = int(entry.strength)
		tile.special_effect = int(entry.effect)
		tile.war = WarManager._war_id_to_enum(entry.war)
		bonus.append(tile)
	var visible = []
	if copy.WarFlow.active:
		var theaters = WarManager.get_upcoming_theaters()
		for i in mini(copy.WarFlow.index+1,theaters.size()): visible.append(theaters[i].id)
	for id in visible:
		var exposed = wm.basic_tile_in_theater.get(id,{}).get(opponent)
		if exposed: _remove_matching(basic,exposed)
		for tile in wm.bonus_war_tiles_in_theater.get(id,{}).get(opponent,[]): _remove_matching(bonus,tile)
	shuffle(basic,rng)
	shuffle(bonus,rng)
	for id in wm.basic_tile_in_theater:
		if id not in visible and wm.basic_tile_in_theater[id].get(opponent)!=null and not basic.is_empty(): wm.basic_tile_in_theater[id][opponent] = basic.pop_back()
	for id in wm.bonus_war_tiles_in_theater:
		if id in visible: continue
		var count = wm.bonus_war_tiles_in_theater[id].get(opponent,[]).size()
		wm.bonus_war_tiles_in_theater[id][opponent] = []
		for i in count:
			if not bonus.is_empty(): wm.bonus_war_tiles_in_theater[id][opponent].append(bonus.pop_back())
	wm.basic_war_tiles[opponent] = basic.slice(0,wm.basic_war_tiles.get(opponent,[]).size())
	wm.bonus_tile_pool[opponent] = bonus.slice(0,wm.bonus_tile_pool.get(opponent,[]).size())
	# 내 남은 타일 구성은 알지만 다음 순서는 모른다. 독립 난수로 섞는다.
	wm.basic_war_tiles.get(side,[]).sort_custom(func(a,b): return str([a.strength,a.special_effect,a.id])<str([b.strength,b.special_effect,b.id]))
	wm.bonus_tile_pool.get(side,[]).sort_custom(func(a,b): return a.id<b.id)
	st.investment_draw_pile.sort_custom(func(a,b): return a.id<b.id)
	copy.AwardManager.remaining_awards.sort_custom(func(a,b): return str(a)<str(b))
	shuffle(wm.basic_war_tiles.get(side,[]),rng)
	shuffle(wm.bonus_tile_pool.get(side,[]),rng)
	shuffle(st.investment_draw_pile,rng)
	shuffle(copy.AwardManager.remaining_awards,rng)
	st.war_tiles_in_play.clear() # 현재 엔진에서 사용하지 않는 구형 중복 필드
	copy.AIController.enabled = false
	return SaveLoad.encode_snapshot(copy)

static func shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size()-1,0,-1):
		var j = rng.randi_range(0,i)
		var value = items[i]
		items[i] = items[j]
		items[j] = value

static func _remove_matching(pool: Array, tile: WarTile) -> void:
	for candidate in pool:
		if candidate.strength==tile.strength and candidate.special_effect==tile.special_effect:
			pool.erase(candidate)
			return
