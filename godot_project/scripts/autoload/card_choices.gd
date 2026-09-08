extends Node

# 보드 클릭으로 표현할 수 없는 카드 선택. 선택지는 매번 현재 모델에서 만든다.
# 카드의 남은 작업과 뽑은 타일은 EventEffects.pending_choices에 저장된다.
const TYPES = ["ap_type","squadron_choice","war_loss","remove_bonus","draw_bonus","place_bonus","demand_add","demand_replace","advantage_choice","paid_advantage","byng","hyder","build_payment","score_commodity","discard_hand","huguenots","townshend"]

func handles(kind: String) -> bool:
	return kind in TYPES

func options(choice: Dictionary) -> Array:
	var p: Dictionary = choice.params
	var side: int = p.side
	var result: Array = []
	match choice.type:
		"paid_advantage": result=advantage_payment_options(p.advantage,side)
		"score_commodity": result.append({"id":"score","label":LocaleManager.commodity(p.commodity)+" 수요 보상 적용"})
		"discard_hand":
			for card in GameManager.state.get_player(side).hand: result.append({"id":str(card.id),"label":card.disp_title(),"card":card})
		"townshend":
			for commodity in [Enums.Commodity.FISH,Enums.Commodity.FUR,Enums.Commodity.SPICE,Enums.Commodity.TOBACCO,Enums.Commodity.SUGAR,Enums.Commodity.COTTON]: result.append({"id":str(commodity),"label":LocaleManager.commodity(commodity),"commodity":commodity})
		"huguenots":
			for ss in GameManager.state.spaces.values():
				if ss.controlled_by!=side or ss.data.space_type!=Enums.SpaceType.TERRITORY or ss.data.region not in [Enums.Region.NORTH_AMERICA,Enums.Region.CARIBBEAN]: continue
				if (p.flip and ss.has_huguenots and not ss.huguenots_exhausted) or (not p.flip and not ss.has_huguenots): result.append(_space(ss))
		"ap_type":
			for type in [Enums.ActionType.DIPLOMATIC,Enums.ActionType.ECONOMIC]: result.append({"id":str(type),"label":"%d %s 행동점수" % [p.amount,LocaleManager.action(type)],"value":type})
		"squadron_choice", "war_loss":
			var owner: int = p.get("owner",side)
			var player = GameManager.state.get_player(owner)
			if p.get("navy",true) and player.squadrons_in_navy_box>0: result.append({"id":"navy","label":LocaleManager.side(owner)+" 해군 상자의 함대"})
			for ss in GameManager.state.spaces.values():
				if ss.controlled_by != owner: continue
				if ss.data.space_type == Enums.SpaceType.NAVAL or (choice.type=="war_loss" and ss.data.space_type==Enums.SpaceType.FORT and not ss.is_fort_damaged): result.append(_space(ss))
			if choice.type == "war_loss": result.append_array(_bonus_options(owner))
		"remove_bonus": result = _bonus_options(p.owner)
		"draw_bonus":
			if not WarManager.bonus_tile_pool.get(side,[]).is_empty() and WarManager.bonus_war_tiles_in_theater.values().any(func(t):return t[side].size()<2): result.append({"id":"draw","label":"보너스 전쟁 타일 뽑기"})
		"place_bonus":
			for th in WarManager.get_upcoming_theaters():
				if p.has("only_theater") and th.id != p.only_theater: continue
				var tiles: Array = WarManager.bonus_war_tiles_in_theater[th.id][side]
				if tiles.size()<2:
					result.append({"id":th.id,"label":th.name_ko+"에 배치","theater":th.id})
				else:
					for i in tiles.size():
						for other in WarManager.get_upcoming_theaters():
							if other.id!=th.id and WarManager.bonus_war_tiles_in_theater[other.id][side].size()<2: result.append({"id":th.id+"|"+str(i)+"|"+other.id,"label":"%s에 배치 · 기존 %+d → %s" % [th.name_ko,tiles[i].strength,other.name_ko],"theater":th.id,"move_index":i,"move_to":other.id})
		"demand_add":
			for commodity in p.commodities:
				if commodity not in GameManager.state.current_global_demand: result.append({"id":str(commodity),"label":LocaleManager.commodity(commodity),"commodity":commodity})
		"demand_replace":
			for commodity in GameManager.state.current_global_demand: result.append({"id":str(commodity),"label":"%s 대신 %s" % [LocaleManager.commodity(commodity),LocaleManager.commodity(p.drawn)],"commodity":commodity})
		"advantage_choice":
			for adv in AdvantageManager.advantages.values():
				if p.has("owner") and adv.controlled_by != p.owner: continue
				if p.has("regions") and adv.region not in p.regions: continue
				if p.mode == "refresh" and not adv.is_exhausted: continue
				if p.mode == "exhaust" and adv.is_exhausted: continue
				if p.mode == "activate" and (adv.controlled_by!=side or not AdvantageManager._all_controlled_by(adv,side,true)): continue
				if p.mode=="activate" and AdvantageManager.effect_rules[adv.id].kind in ["naval","construct"] and advantage_payment_options(adv.id,side).is_empty(): continue
				result.append({"id":adv.id,"label":adv.name_ko})
		"byng":
			for th in WarManager.get_upcoming_theaters():
				if th.bonus_strength_keys.any(func(k): return k.begins_with("squadron_")): result.append({"id":th.id,"label":th.name_ko})
		"hyder":
			for ss in GameManager.state.spaces.values():
				if ss.data.is_local_alliance and ss.data.region==Enums.Region.INDIA and ss.controlled_by!=side: result.append(_space(ss))
			result.append({"id":"conflict","label":"인도의 비보호 공간에 분쟁 마커 2개"})
		"build_payment":
			result.append({"id":"debt","label":"부채 1 증가"})
			if GameManager.state.get_player(side).treaty_points>0: result.append({"id":"trp","label":"조약점수 1 소비"})
	if p.get("optional",false) and not result.is_empty(): result.append({"id":"skip","label":"선택 종료"})
	return result

func _space(ss: SpaceState) -> Dictionary:
	return {"id":ss.data.id,"label":ss.data.name_ko}

func _bonus_options(side: int) -> Array:
	var result: Array = []
	for th in WarManager.get_upcoming_theaters():
		var tiles: Array = WarManager.bonus_war_tiles_in_theater[th.id][side]
		# 상대의 비공개 타일 전력은 선택 화면에 공개하지 않는다.
		for i in tiles.size(): result.append({"id":th.id+"|"+str(i),"label":th.name_ko+" · 보너스 타일 "+str(i+1),"theater":th.id,"index":i})
	return result

func resolve(choice: Dictionary, option: Dictionary) -> void:
	var p: Dictionary = choice.params
	var side: int = p.side
	if option.id == "skip": return
	match choice.type:
		"paid_advantage": _pay_advantage(p.advantage,side,option)
		"score_commodity": GameManager.score_commodity(p.commodity)
		"discard_hand":
			GameManager.state.get_player(side).hand.erase(option.card)
			GameManager.state.event_discard_pile.append(option.card)
			GameManager.state.get_player(side).add_treaty_points(p.get("trp",0))
		"townshend": GameManager.state.get_player(side).townshend_commodity=option.commodity
		"huguenots":
			var ss=GameManager.state.spaces[option.id]
			if p.flip:
				ss.huguenots_exhausted=true
				AdvantageManager.discounts.append({"side":side,"type":Enums.ActionType.ECONOMIC,"region":ss.data.region,"reduction":1,"friendly_allowed":true})
			else: ss.has_huguenots=true
		"ap_type": ActionController.grant_event_ap(p.amount,option.value,p.get("restrictions",{}))
		"squadron_choice", "war_loss":
			var owner: int = p.get("owner",side)
			var player = GameManager.state.get_player(owner)
			if option.has("theater"):
				_remove_bonus(owner,option)
			else:
				var ss: SpaceState = GameManager.state.spaces.get(option.id)
				if ss and ss.data.space_type==Enums.SpaceType.FORT:
					ss.is_fort_damaged=true
				else:
					if option.id=="navy": player.squadrons_in_navy_box-=1
					else: ss.controlled_by=Enums.Side.NONE
					match p.get("destination","navy"):
						"navy": player.squadrons_in_navy_box+=1
						"removed": player.squadrons_removed+=1
						"next_turn":
							var turn=GameManager.state.current_turn+1
							player.squadrons_returning[turn]=player.squadrons_returning.get(turn,0)+1
					if p.has("vp"): GameManager.state.score_vp(side,p.vp)
		"remove_bonus": _remove_bonus(p.owner,option)
		"draw_bonus":
			WarManager.bonus_tile_pool[side].shuffle()
			var tile=WarManager.bonus_tile_pool[side].pop_back()
			var next=p.duplicate(true)
			next.tile=tile
			next.erase("count")
			EventEffects.pending_choices.push_front({"type":"place_bonus","params":next})
		"place_bonus":
			var tiles: Array=WarManager.bonus_war_tiles_in_theater[option.theater][side]
			if option.has("move_to"): WarManager.bonus_war_tiles_in_theater[option.move_to][side].append(tiles.pop_at(option.move_index))
			tiles.append(p.tile)
		"demand_add": GameManager.state.current_global_demand.append(option.commodity)
		"demand_replace":
			GameManager.state.current_global_demand.erase(option.commodity)
			GameManager.state.current_global_demand.append(p.drawn)
		"advantage_choice":
			var adv=AdvantageManager.advantages[option.id]
			match p.mode:
				"refresh": adv.is_exhausted=false
				"exhaust":
					adv.is_exhausted=true
					MinistryEffects.on_advantage_exhausted(side,adv.region)
				"activate":
					if AdvantageManager.effect_rules[adv.id].kind in ["naval","construct"]:
						EventEffects.pending_choices.push_front({"type":"paid_advantage","params":{"side":side,"advantage":adv.id}})
					else:
						adv.is_exhausted=true
						# 이점이 만드는 선택을 현재 이벤트의 후속 보너스보다 먼저 해결한다.
						var remainder=EventEffects.pending_choices.duplicate(true)
						EventEffects.pending_choices.clear()
						AdvantageManager._apply_effect(adv)
						EventEffects.pending_choices.append_array(remainder)
						MinistryEffects.on_advantage_exhausted(side,adv.region)
		"byng": GameManager.state.byng_theater=option.id
		"hyder":
			if option.id=="conflict": EventEffects.pending_choices.push_front({"type":"place_conflict_marker_choice","params":{"side":side,"region":Enums.Region.INDIA,"unprotected":true,"count":2}})
			else: GameManager.state.spaces[option.id].take_control(side)
		"build_payment":
			if option.id=="debt": GameManager.state.get_player(side).incur_debt(1)
			else: GameManager.state.get_player(side).spend_treaty_points(1)
	ActionController._recount_squadrons()
	AdvantageManager.recompute_control()

func _remove_bonus(side: int, option: Dictionary) -> void:
	WarManager.bonus_tile_pool[side].append(WarManager.bonus_war_tiles_in_theater[option.theater][side].pop_at(option.index))

func advantage_payment_options(id: String,side: int) -> Array:
	var result: Array=[]
	var ac=ActionController
	if ac.current_tile==null: return result
	var rule=AdvantageManager.effect_rules[id]
	var cost=maxi(0,rule.cost-(ac.event_construct_discount if rule.kind=="construct" else 0))
	var player=GameManager.state.get_player(side)
	if rule.kind=="construct" and not player.can_build_squadron(): return result
	# 즉시 사용하는 이점도 군사점수가 있는 출처와 그 출처의 제한을 따라야 한다.
	var saved_state=ac.state
	for pool in ["major","minor"]:
		ac.state=ac.ActionState.SPENDING_MAJOR if pool=="major" else ac.ActionState.SPENDING_MINOR
		if ac.current_action_type()!=Enums.ActionType.MILITARY or pool in ac.finished_pools or (pool=="minor" and (ac.minor_action_used_first_expense or rule.kind=="naval")): continue
		var missing=maxi(0,cost-ac.ap_for_current(null,"construct" if rule.kind=="construct" else "advantage"))
		for debt in range(missing+1):
			var trp=missing-debt
			if debt>player.available_debt() or trp>player.treaty_points: continue
			result.append({"id":pool+"|"+str(debt),"pool":pool,"debt":debt,"trp":trp,"cost":cost,"label":"%s 군사점수 · 추가 부채 %d / 조약점수 %d" % ["주요" if pool=="major" else "보조",debt,trp]})
	ac.state=saved_state
	return result

func _pay_advantage(id: String,side: int,option: Dictionary) -> void:
	var ac=ActionController
	var remainder=EventEffects.pending_choices.duplicate(true)
	EventEffects.pending_choices.clear()
	var saved_state=ac.state
	ac.state=ac.ActionState.SPENDING_MAJOR if option.pool=="major" else ac.ActionState.SPENDING_MINOR
	if option.debt>0: ac.take_debt_for_ap(option.debt)
	if option.trp>0: ac.spend_treaty_points_for_ap(option.trp)
	var adv=AdvantageManager.advantages[id]
	adv.is_exhausted=true
	AdvantageManager._apply_effect(adv)
	MinistryEffects.on_advantage_exhausted(side,adv.region)
	ac.state=saved_state
	EventEffects.pending_choices.append_array(remainder)
	ac.clear_undo_stack()
