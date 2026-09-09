extends RefCounted

# AI 명령도 사람이 누르는 버튼과 같은 규칙 함수를 통과한다.
# 점수/소유권을 직접 쓰는 'AI 전용 지름길'을 만들지 않는다.
const Eval = preload("res://scripts/ai/evaluation.gd")

static func options(side: int) -> Array:
	var out = []
	var ac = ActionController
	var st = GameManager.state
	if st.winner!=Enums.Side.NONE: return out
	if MinistryDecisions.has_pending():
		if MinistryDecisions.pending.side==side:
			out = [{"kind":"reveal_choice","yes":true,"rank":3.0},{"kind":"reveal_choice","yes":false,"rank":0.0}]
		return out
	if EventEffects.has_pending():
		var choice = EventEffects.pending_choices[0]
		if choice.params.get("chooser",choice.params.get("side",EventEffects.current_side))!=side: return out
		for option in EventEffects.choice_options():
			var rank = -5.0 if option.id=="skip" else 1.0
			if st.spaces.has(option.id): rank = Eval.space_gain(st.spaces[option.id],side)
			if option.has("card"): rank = -Eval.card_value(option.card,side)
			if option.has("theater") and choice.type not in ["remove_bonus","war_loss"]: rank = Eval.war_value(option.theater,side,2.0)-Eval.war_value(option.theater,side)
			if option.has("commodity"): rank = GameManager._count_commodity_markets(side,option.commodity)-GameManager._count_commodity_markets(WarManager._opp(side),option.commodity)
			out.append({"kind":"option","id":option.id,"rank":rank})
		if not out.is_empty(): return out
		for ss in st.spaces.values():
			if not EventEffects.is_valid_target(ss.data.id): continue
			var rank = Eval.space_gain(ss,side)
			if "conflict" in choice.type and ss.controlled_by==side: rank = -rank
			if choice.params.get("from","")=="friendly": rank = -rank
			out.append({"kind":"target","id":ss.data.id,"rank":rank})
		return out
	if WarFlow.active:
		if WarFlow.choice.get("side",Enums.Side.NONE)!=side: return out
		for option in WarFlow.choice.get("options",[]):
			var rank = -8.0 if option.id=="skip" else 0.0
			var target = st.spaces.get(option.get("target",option.id))
			if target: rank = Eval.space_gain(target,side)
			if WarFlow.choice.kind=="remove_squadron": rank = -rank
			if option.id=="refuse": rank = -15.0
			out.append({"kind":"war","id":option.id,"rank":rank})
		return out
	if st.phasing_player!=side: return out
	var player = st.get_player(side)
	if ac.current_tile==null:
		for tile in st.available_investment_tiles:
			out.append({"kind":"tile","id":tile.id,"rank":tile.major_action_points*2.0+(2.0 if tile.has_event_symbol and not player.hand.is_empty() else 0.0)})
		for card in player.ministry_cards:
			for index in MinistryEffects.ability_labels(card).size():
				if MinistryEffects.can_activate(card,side,index): out.append({"kind":"ministry","id":card.id,"index":index,"rank":5.0})
		return out
	if ac.upgrade_drawn:
		var old = WarManager.basic_tile_in_theater[ac.upgrade_theater][side]
		for swap in [false,true]:
			for remove in [false,true]:
				if remove and not ac.can_remove_upgrade_tile(): continue
				var discarded = old if swap else ac.upgrade_drawn
				var rank = float(ac.upgrade_drawn.strength-old.strength)*3.0 if swap else 0.0
				if remove: rank += 0.5-float(discarded.strength)
				out.append({"kind":"finish_upgrade","swap":swap,"remove":remove,"rank":rank})
		return out
	if ac.bonus_drawn:
		for id in ac.bonus_allowed_theaters:
			var rank = Eval.war_value(id,side,ac.bonus_drawn.strength)-Eval.war_value(id,side)
			var placed = WarManager.bonus_war_tiles_in_theater[id][side]
			if placed.size()<2:
				out.append({"kind":"place_bonus","id":id,"rank":rank})
			else:
				for dest in WarManager.bonus_war_tiles_in_theater:
					if dest==id or WarManager.bonus_war_tiles_in_theater[dest][side].size()>=2: continue
					for i in placed.size():
						var strength = placed[i].strength
						out.append({"kind":"place_bonus","id":id,"index":i,"to":dest,"rank":rank+Eval.war_value(dest,side,strength)-Eval.war_value(dest,side)})
		return out
	# 미리 공개도 합법적인 선택이다. 즉시 효용 없는 공개를 강제하지 않는다.
	for card in player.ministry_cards:
		if MinistryDecisions.can_reveal(card,side):
			var benefit=Eval.passive_ministry_value(card,side)
			out.append({"kind":"reveal","id":card.id,"rank":benefit-1.0 if benefit>0 else -25.0})
		for index in MinistryEffects.ability_labels(card).size():
			if MinistryEffects.can_activate(card,side,index): out.append({"kind":"ministry","id":card.id,"index":index,"rank":6.0})
	if ac.state==ac.ActionState.AWAITING_EVENT:
		out.append({"kind":"skip_event","rank":-3.0})
		for card in player.hand:
			if ac._can_play_event(card):
				out.append({"kind":"event","id":card.id,"bonus":true,"rank":Eval.card_value(card,side)+3.0})
		return out
	for id in AdvantageManager.advantages:
		if AdvantageManager.can_activate(id): out.append({"kind":"advantage","id":id,"rank":5.0})
	var current = ac.pool_key()
	for pool in ["major","minor"]:
		if pool!=current and ac.can_switch_pool(pool) and ac.remaining_for_pool(pool)>0:
			out.append({"kind":"pool","id":pool,"rank":-2.0})
	for i in ac.event_grants.size():
		var grant = ac.event_grants[i]
		var key = "event_%d" % i
		if grant.pool==key and key!=current and grant.amount>0 and ac.can_switch_pool(key): out.append({"kind":"pool","id":key,"index":i,"rank":-1.5})
		if ac.spent_pools.is_empty() and not grant.get("locked",false):
			for pool in ["major","minor"]:
				var match_type = ac.current_tile.major_action_type if pool=="major" else ac.current_tile.minor_action_type
				if grant.type==match_type and grant.pool!=pool: out.append({"kind":"assign","index":i,"id":pool,"rank":2.0})
	if ac.can_upgrade():
		if st.current_turn==6: out.append({"kind":"upgrade","id":"","rank":3.0})
		else:
			for th in WarManager.get_upcoming_theaters():
				var tile = WarManager.basic_tile_in_theater.get(th.id,{}).get(side)
				if tile: out.append({"kind":"upgrade","id":th.id,"rank":1.0-tile.strength})
	if ac.can_end_action_round(): out.append({"kind":"end","rank":-20.0})
	if not ac.action_started and ac.can_end_action_round() and player.current_debt>0:
		out.append({"kind":"pass","rank":float(mini(2,player.current_debt))*1.7-6.0})
	if current in ac.finished_pools or ac.state==ac.ActionState.UPGRADING or (current=="minor" and ac.minor_action_used_first_expense): return out
	var action = ac.current_action_type()
	for ss in st.spaces.values():
		if ss.data.space_type==Enums.SpaceType.NAVAL and action==Enums.ActionType.MILITARY:
			var sources = ["navy"]
			for source in st.spaces.values():
				if source.data.space_type==Enums.SpaceType.NAVAL and source.controlled_by==side and source.data.id not in ac.deployed_squadrons: sources.append(source.data.id)
			for source in sources:
				var plan = ac.squadron_deployment_plan(ss.data.id,source)
				if plan.is_empty() or not ac.can_spend_ap(plan.cost,ss,"naval"): continue
				var rank = Eval.space_gain(ss,side)-plan.cost*0.5
				if source!="navy": rank -= Eval.space_gain(st.spaces[source],side)
				out.append({"kind":"deploy","id":ss.data.id,"source":source,"rank":rank})
		elif ac.can_shift_space(ss):
			out.append({"kind":"shift","id":ss.data.id,"rank":Eval.space_gain(ss,side)-ac.calculate_shift_cost(ss,ss.data.region)*0.5})
		if action==Enums.ActionType.MILITARY and ss.has_conflict_marker:
			var cost = (1 if ss.data.space_type==Enums.SpaceType.MARKET and ac._is_market_protected(ss,side) else 2)+(1 if ss.conflict_marker_extra_cost else 0)
			if ac.can_spend_ap(cost,ss,"conflict"): out.append({"kind":"conflict","id":ss.data.id,"rank":Eval.space_gain(ss,side)*(1 if ss.controlled_by==side else -1)-cost*0.5})
		if ac.can_flip_huguenots(ss.data.id): out.append({"kind":"huguenots","id":ss.data.id,"rank":4.0})
	if ac.can_draw_event(): out.append({"kind":"draw","rank":5.0 if player.hand.is_empty() else -0.5})
	if action==Enums.ActionType.MILITARY:
		if player.can_build_squadron() and ac.can_spend_ap(maxi(0,4-ac.event_construct_discount),null,"construct"): out.append({"kind":"construct","rank":1.5 if player.squadrons_in_navy_box<2 else -3.0})
		if not ac.bonus_purchase_theaters().is_empty() and st.current_turn<6 and ac.bonus_tiles_bought_this_ar<2 and not WarManager.bonus_tile_pool.get(side,[]).is_empty(): out.append({"kind":"bonus","rank":4.0})
		if st.current_turn==6 and not ac.conversion_plan().is_empty():
			for type in [Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC]:
				if ac.turn6_conversion_type in [Enums.ActionType.NONE,type]: out.append({"kind":"convert","type":type,"rank":2.0})
	# 자금 확보는 뒤의 실제 지출까지 묶어서 탐색에서 평가한다. 남긴 AP는 보상하지 않는다.
	if ac.ap_for_current()<5 and ac.state in [ac.ActionState.SPENDING_MAJOR,ac.ActionState.SPENDING_MINOR,ac.ActionState.SPENDING_EVENT]:
		for amount in [1,2]:
			if player.available_debt()>=amount: out.append({"kind":"debt","amount":amount,"rank":-4.0-float(amount)})
			if player.treaty_points>=amount: out.append({"kind":"treaty","amount":amount,"rank":-3.0-float(amount)})
	return out

static func apply(command: Dictionary,side: int,validate: bool = true) -> bool:
	# 백그라운드 결과를 실제 판에 적용하기 전에도 현재의 합법 후보와 대조한다.
	if validate and not options(side).any(func(c): return same(c,command)): return false
	var ac = ActionController
	match command.kind:
		"tile":
			var tiles = GameManager.state.available_investment_tiles.filter(func(t): return t.id==int(command.id))
			if tiles.is_empty(): return false
			GameManager.select_investment_tile(side,tiles[0])
		"reveal_choice": MinistryDecisions.choose(command.yes)
		"reveal": return MinistryEffects._card(side,command.id).reveal()
		"ministry":
			MinistryEffects.activate_manual(MinistryEffects._card(side,command.id),side,int(command.index))
		"option": return EventEffects.resolve_option(command.id)
		"target": return EventEffects.resolve_choice(0,command.id)
		"war": return WarFlow.choose(command.id)
		"skip_event": ac.skip_event()
		"event": return ac.play_event(GameManager.state.get_player(side).hand.filter(func(c): return c.id==int(command.id))[0],command.bonus) or MinistryDecisions.has_pending()
		"pool":
			if command.id=="major": ac.switch_to_major()
			elif command.id=="minor": ac.switch_to_minor()
			else: ac.switch_to_event(int(command.index))
		"assign": return ac.assign_event_grant(int(command.index),command.id)
		"shift": return ac.attempt_shift(command.id) or MinistryDecisions.has_pending()
		"deploy": return ac.deploy_squadron_to(command.id,command.source)
		"conflict": return ac.remove_conflict_marker(command.id)
		"huguenots": return ac.flip_huguenots(command.id)
		"draw": return ac.draw_event_card()
		"construct": return ac.construct_squadron()
		"bonus": return ac.begin_bonus_purchase()
		"place_bonus": return ac.place_bonus_tile(command.id,int(command.get("index",-1)),command.get("to",""))
		"upgrade": return ac.begin_upgrade(command.id)
		"finish_upgrade": return ac.finish_upgrade(command.swap,command.remove)
		"convert": return ac.convert_turn6_military(int(command.type))
		"advantage": return AdvantageManager.activate(command.id) or MinistryDecisions.has_pending()
		"debt": return ac.take_debt_for_ap(int(command.amount))>0 or MinistryDecisions.has_pending()
		"treaty": return ac.spend_treaty_points_for_ap(int(command.amount))>0
		"end": ac.end_action_round()
		"pass": GameManager.pass_action_round(side)
		_: return false
	return true

static func same(a: Dictionary,b: Dictionary) -> bool:
	var x = a.duplicate()
	var y = b.duplicate()
	x.erase("rank")
	y.erase("rank")
	# JSON은 정수를 float로 읽는다. 명령의 정수 인자는 값으로 비교하되
	# 1.5 같은 잘못된 인자를 1로 잘라서 승인하지 않는다.
	for values in [x,y]:
		for key in values:
			if values[key] is float:
				if values[key]!=floor(values[key]): return false
				values[key]=int(values[key])
	return x==y

static func chooser() -> int:
	if MinistryDecisions.has_pending(): return MinistryDecisions.pending.side
	if EventEffects.has_pending():
		var params=EventEffects.pending_choices[0].params
		return params.get("chooser",params.get("side",EventEffects.current_side))
	if WarFlow.active: return WarFlow.choice.get("side",Enums.Side.NONE)
	return GameManager.state.phasing_player

static func boundary(command: Dictionary) -> bool:
	# 숨겨진 결과를 관찰한 뒤에만 다음 결정을 적용한다. 계산에서 본 카드는 가정이다.
	return command.kind in ["draw","bonus","upgrade","event","ministry","advantage","war","end","pass"]
