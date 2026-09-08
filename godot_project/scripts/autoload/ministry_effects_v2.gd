extends "res://scripts/autoload/ministry_effects.gd"

# 선택 능력은 사용자가 시점을 정한다. 자동 보너스와 일회성 능력을 섞으면
# 사용하지 않은 내각이 공개·소진되는 문제가 생기므로 경로를 분리했다 (§3.5).
var active_flags: Dictionary = {}
const LABELS={
	"M-1":["이번 외교 행동에 추가 DP"],"M-4":["군사점수로 스코틀랜드·아일랜드 이동","3 MP로 재커바이트 득점"],
	"M-5":["이벤트 1장 뽑고 1장 버리기"],"M-8":["부채 한도 +1"],"M-9":["위그노 마커 배치","위그노 마커를 뒤집어 시장 할인"],
	"M-10":["2 MP로 함대 건조","이벤트 1장 버리고 조약점수 +1"],"M-11":["군사 행동에 제한된 1 MP 추가","북미 함대를 바탕으로 2 MP 건조"],
	"M-15":["비위신 공간용 1 DP 추가","2 MP로 함대 건조"],"M-16":["이번 라운드 프랑스 깃발 제거 할인"],
	"M-20":["스코틀랜드·아일랜드용 2 DP"],"M-21":["이번 턴 보조 행동으로 제거할 상품 지정"],"M-22":["유럽 주요 외교 행동 추가 DP"]}

func _card(side: int, id: String) -> MinistryCard:
	for c in GameManager.state.get_player(side).ministry_cards:
		if c.id==id: return c
	return null

func get_extra_major_ap(_side: int,_type: int) -> int:
	return 0

func prepare_round() -> void:
	active_flags.clear()
	active_flags.trade_advantage=_fur_fish_advantage(GameManager.state.phasing_player)
	for player in [GameManager.state.britain,GameManager.state.france]:
		for c in player.ministry_cards:
			if c.id=="M-13": c.exhausted_abilities.erase(0)
			if c.id=="M-19": c.exhausted_abilities.erase(1)

func round_start(side: int) -> void:
	var trade=_card(side,"M-24")
	var tile=ActionController.current_tile
	if trade and tile:
		var economic=trade_advantage_at_start() and Enums.ActionType.ECONOMIC in [tile.major_action_type,tile.minor_action_type]
		var huguenots=GameManager.state.spaces.values().any(func(ss):return ss.has_huguenots and ss.huguenots_exhausted)
		if (economic or huguenots) and MinistryDecisions.offer(side,["M-24"],{"kind":"round","side":side}): return
	apply_trade_bonus(side)

func apply_trade_bonus(side: int) -> void:
	var trade=_card(side,"M-24")
	var ac=ActionController
	if not MinistryDecisions.active(trade) or ac.current_tile==null or ac.current_side!=side: return
	if trade_advantage_at_start():
		var granted=active_flags.get("trade_pools",[])
		for pool in ["major","minor"]:
			var type=ac.current_tile.major_action_type if pool=="major" else ac.current_tile.minor_action_type
			if type==Enums.ActionType.ECONOMIC and pool not in granted and pool not in ac.finished_pools:
				if pool=="major": ac.major_ap_remaining+=1
				else: ac.minor_ap_remaining+=1
				granted.append(pool)
		active_flags.trade_pools=granted
	# 두 번째 문장은 무역 우세 조건과 독립적인 위그노 회복 효과다.
	if trade:
		for ss in GameManager.state.spaces.values():
			if ss.has_huguenots and ss.huguenots_exhausted:
				ss.huguenots_exhausted=false

func trade_advantage_at_start() -> bool:
	# 라운드 중 시장을 얻은 뒤 공개하더라도 시작 시점의 조건을 소급해서 바꾸지 않는다.
	return active_flags.get("trade_advantage",false)

func on_advantage_exhausted(exhauster_side: int,region: int) -> void:
	if exhauster_side!=Enums.Side.FRANCE: return
	if region==Enums.Region.EUROPE and not active_flags.get("pompadour_seen",false):
		# '처음'이라는 기회는 공개를 거절해도 지나간다. 소진 여부와 별도로 기록한다.
		active_flags.pompadour_seen=true
		if not MinistryDecisions.offer(exhauster_side,["M-13"],{"kind":"pompadour","side":exhauster_side}): apply_pompadour_reward()
	if not active_flags.get("watt_seen",false):
		active_flags.watt_seen=true
		var watt=_card(Enums.Side.BRITAIN,"M-19")
		if MinistryDecisions.active(watt):
			GameManager.state.britain.add_treaty_points(1)
			watt.exhaust_ability(1)

func apply_pompadour_reward() -> void:
	var card=_card(Enums.Side.FRANCE,"M-13")
	if MinistryDecisions.active(card) and not card.is_ability_exhausted(0):
		GameManager.state.france.add_treaty_points(1)
		card.exhaust_ability(0)

func reveal_shift_benefit(side: int,ss: SpaceState,minor: bool) -> void:
	# 비용 미리 보기에서는 공개하지 않는다. 실제로 능력을 적용한 행동만 공개한다.
	if _has(side,"M-6") and ((ss.controlled_by==Enums.Side.NONE and (ss.data.id.begins_with("ireland") or ss.data.id.begins_with("scotland"))) or (minor and ss.controlled_by!=side and not ss.has_conflict_marker and minor_can_unflag(side,ss))): _reveal(side,"M-6")
	if _has(side,"M-22") and (ss.data.id.begins_with("sons_of_liberty") or ss.data.id.begins_with("usa_")): _reveal(side,"M-22")

func ability_labels(card: MinistryCard) -> Array:
	return LABELS.get(card.id,[])

func can_activate(card: MinistryCard,side: int,index: int=0) -> bool:
	var ac=ActionController
	if card not in GameManager.state.get_player(side).ministry_cards or not MinistryDecisions.own_round(side) or MinistryDecisions.has_pending(): return false
	if EventEffects.has_pending() or ac.upgrade_drawn or ac.bonus_drawn: return false
	if card.id != "M-9" or index==0:
		if card.is_ability_exhausted(index): return false
	if ac.current_tile==null:
		# §5.0은 Walpole처럼 타일 선택 전에 쓸 수 있는 능력을 명시한다.
		return (card.id in ["M-5","M-8","M-9","M-21"] and index==0) or (card.id=="M-10" and index==1 and not GameManager.state.get_player(side).hand.is_empty() and EventEffects._count_naval_controlled(side,Enums.Region.EUROPE)>0)
	if side!=ac.current_side: return false
	if card.id=="M-22" and ac.pool_key() in active_flags.get("burke_europe",[]): return false
	if card.id in ["M-1","M-21"] and ac.action_started: return false
	if card.id=="M-1": return Enums.ActionType.DIPLOMATIC in [ac.current_tile.major_action_type,ac.current_tile.minor_action_type]
	if card.id in ["M-11","M-15","M-20"] and index==0:
		return ac.current_action_type()==(Enums.ActionType.MILITARY if card.id=="M-11" else Enums.ActionType.DIPLOMATIC) and ac.pool_key() not in ac.finished_pools
	if card.id=="M-22": return ac.state in [ac.ActionState.SPENDING_MAJOR,ac.ActionState.SPENDING_EVENT] and ac.current_action_type()==Enums.ActionType.DIPLOMATIC and ac.pool_key() not in ac.finished_pools and not ac.regions_by_pool.get(ac.pool_key(),[]).any(func(r): return r!=Enums.Region.EUROPE)
	if card.id=="M-4":
		if ac.current_action_type()!=Enums.ActionType.MILITARY: return false
		if card.exhausted_abilities.get("round_"+str(1-index),-1)==GameManager.state.current_action_round: return false
		if index==1: return ac.can_spend_ap(3,null,"jacobite")
	if (card.id=="M-10" and index==0) or (card.id in ["M-11","M-15"] and index==1):
		if not GameManager.state.get_player(side).can_build_squadron() or ac.current_action_type()!=Enums.ActionType.MILITARY or not ac.can_spend_ap(maxi(0,2-ac.event_construct_discount),null,"construct"): return false
		if card.id=="M-11" and EventEffects._count_naval_controlled(side,Enums.Region.NORTH_AMERICA)==0: return false
	if card.id=="M-10" and index==1: return not GameManager.state.get_player(side).hand.is_empty() and EventEffects._count_naval_controlled(side,Enums.Region.EUROPE)>0
	return true

func activate_manual(card: MinistryCard,side: int,index: int=0) -> void:
	if not can_activate(card,side,index): return
	if MinistryDecisions.offer(side,[card.id],{"kind":"manual","card":card,"side":side,"index":index}): return
	if not card.is_revealed: return
	var ac=ActionController
	ac.clear_undo_stack()
	ac.action_started=true
	if ac.current_tile==null: MinistryDecisions.pre_tile_action_used=true
	card.reveal()
	if card.id not in ["M-9","M-22"] or (card.id=="M-9" and index==0): card.exhaust_ability(index)
	match card.id:
		"M-1": _grant(card,mini(3,_cardinal_ministers_count(side)),Enums.ActionType.DIPLOMATIC,{},"major" if ac.current_tile.major_action_type==Enums.ActionType.DIPLOMATIC else "minor")
		"M-4":
			card.exhausted_abilities["round_"+str(index)]=GameManager.state.current_action_round
			if index==0: active_flags.jacobite=true
			elif ac.spend_ap(3,null,"jacobite"): _jacobite_score(side)
		"M-5":
			var drawn=GameManager._draw_event()
			if drawn: GameManager.state.get_player(side).hand.append(drawn)
			EventEffects._add_pending("discard_hand",{"side":side})
		"M-8": GameManager.state.get_player(side).debt_limit+=1
		"M-9": EventEffects._add_pending("huguenots",{"side":side,"flip":index==1})
		"M-10":
			if index==0: _cheap_squadron(side)
			else: EventEffects._add_pending("discard_hand",{"side":side,"trp":1})
		"M-11":
			if index==0: _grant(card,1,Enums.ActionType.MILITARY,{"kinds":["war_tile","naval"]})
			else: _cheap_squadron(side)
		"M-15":
			if index==0: _grant(card,1,Enums.ActionType.DIPLOMATIC,{"non_prestige":true})
			else: _cheap_squadron(side)
		"M-16": active_flags.hanbury=true
		"M-20":
			defeat_jacobites()
			_grant(card,2,Enums.ActionType.DIPLOMATIC,{"countries":["scotland","ireland"]})
		"M-21": EventEffects._add_pending("townshend",{"side":side})
		"M-22":
			if not active_flags.has("burke_europe"): active_flags.burke_europe=[]
			active_flags.burke_europe.append(ac.pool_key())
			_grant(card,mini(2,_count_controlled_containing(side,"ireland")),Enums.ActionType.DIPLOMATIC,{"region":Enums.Region.EUROPE})
	EventEffects._finalize_pending()
	ac.ap_changed.emit()

func _grant(card: MinistryCard,amount: int,type: int,rules: Dictionary,pool: String="") -> void:
	if amount<=0: return
	ActionController.event_grants.append({"amount":amount,"type":type,"restrictions":rules,"pool":pool if pool!="" else ActionController.pool_key(),"source":card.id,"locked":true})
	ActionController._sync_event_total()

func _cheap_squadron(side: int) -> void:
	if ActionController.spend_ap(maxi(0,2-ActionController.event_construct_discount),null,"construct"): GameManager.state.get_player(side).squadrons_in_navy_box+=1

func passive_shift_discount(side: int,id: String,type: int) -> int:
	var ss: SpaceState=GameManager.state.spaces[id]
	if type!=Enums.ActionType.DIPLOMATIC: return 0
	var total=0
	if _has(side,"M-6") and (id.begins_with("ireland") or id.begins_with("scotland")) and ss.controlled_by==Enums.Side.NONE: total+=1
	if active_flags.get("hanbury",false) and ss.controlled_by==Enums.Side.FRANCE and ["prussia","german_states","russia"].any(func(c):return id.begins_with(c)): total+=1
	if _has(side,"M-22") and (id.begins_with("sons_of_liberty") or id.begins_with("usa_")): total+=1
	return total

func minor_can_unflag(side: int,ss: SpaceState) -> bool:
	if ss.data.space_type==Enums.SpaceType.POLITICAL and ss.data.region==Enums.Region.EUROPE and _has(side,"M-6") and _count_controlled_containing(side,"ireland")>0:
		return true
	return ss.data.space_type==Enums.SpaceType.MARKET and GameManager.state.get_player(side).townshend_commodity==ss.data.commodity

func on_debt_taken(_side: int,amount: int) -> int:
	# Merchant Banks의 EP 전용 면제는 차입 시 ActionController와 이 함수 아래에서 처리한다.
	return amount

func bank_credit(side: int,amount: int) -> int:
	var card=_card(side,"M-17")
	if not MinistryDecisions.active(card) or ActionController.current_action_type()!=Enums.ActionType.ECONOMIC: return 0
	var reserved=0
	for grant in ActionController.event_grants:
		if grant.get("bank",false): reserved+=grant.amount
	return mini(amount,maxi(0,2-int(card.exhausted_abilities.get("credit",0))-reserved))

func bank_credit_spent(side: int,amount: int) -> void:
	var card=_card(side,"M-17")
	if card:
		card.exhausted_abilities["credit"]=card.exhausted_abilities.get("credit",0)+amount
		card.reveal()

func defeat_jacobites() -> void:
	GameManager.state.jacobite_defeated=true
	for card in GameManager.state.france.ministry_cards.duplicate():
		if card.id=="M-4":
			GameManager.state.france.ministry_cards.erase(card)
			card.is_in_play=false

func event_exception(side: int,card: EventCard,tile: InvestmentTile,consume: bool=false) -> bool:
	if not tile.has_event_symbol:
		var condorcet=_card(side,"M-25")
		if condorcet==null or condorcet.is_ability_exhausted(0): return false
		if card.major_action not in [Enums.ActionType.NONE,tile.major_action_type]: return false
		if consume:
			if not condorcet.is_revealed: return false
			condorcet.exhaust_ability(0)
		return true
	var bank=_card(side,"M-8")
	if bank and not bank.is_ability_exhausted(1) and card.major_action==Enums.ActionType.ECONOMIC:
		if consume:
			if not bank.is_revealed: return false
			bank.exhaust_ability(1)
		return true
	return false

func bonus_received(side: int) -> void:
	if _has(side,"M-26"):
		ActionController.major_ap_remaining+=1
		ActionController.minor_ap_remaining+=1
		_reveal(side,"M-26")

func apply_award_bonus(region: int,winner: int) -> void:
	if region==Enums.Region.EUROPE:
		if winner==Enums.Side.FRANCE and _has(Enums.Side.FRANCE,"M-3"):
			GameManager.state.score_vp(winner,1)
			_reveal(winner,"M-3")
		if _has(Enums.Side.BRITAIN,"M-18"):
			if winner==Enums.Side.BRITAIN: GameManager.state.score_vp(winner,1)
			elif winner==Enums.Side.FRANCE and (AwardManager.get_award_for_region(region).get("vp",0)>0 or _has(winner,"M-3")): GameManager.state.score_vp(Enums.Side.BRITAIN,1)
			_reveal(Enums.Side.BRITAIN,"M-18")
	if winner==Enums.Side.FRANCE and region==Enums.Region.INDIA: commodity_award(winner,Enums.Commodity.COTTON)

func commodity_award(side: int,commodity: int) -> void:
	if side==Enums.Side.FRANCE and commodity in [Enums.Commodity.COTTON,Enums.Commodity.SPICE]:
		if MinistryDecisions.offer(side,["M-12"],{"kind":"commodity_award","side":side,"commodity":commodity}): return
	if side==Enums.Side.FRANCE and commodity in [Enums.Commodity.COTTON,Enums.Commodity.SPICE] and _has(side,"M-12"):
		GameManager.state.france.add_treaty_points(1)
		_reveal(side,"M-12")

func apply_scoring_bonuses() -> void:
	for side in [Enums.Side.BRITAIN,Enums.Side.FRANCE]:
		if _has(side,"M-7"):
			var count=0
			for adv in AdvantageManager.advantages.values():
				if adv.controlled_by==side and not adv.is_exhausted and adv.id in ["textiles_adv","silk_adv","fruit_adv","fur_trade_adv","rum_adv"]: count+=1
			GameManager.state.score_vp(side,mini(3,count))
			if count>0: _reveal(side,"M-7")
		if _has(side,"M-14"):
			var countries={}
			for ss in GameManager.state.spaces.values():
				if ss.controlled_by!=side or not ss.data.is_prestige or ss.has_conflict_marker: continue
				for country in ["spain","austria","prussia","dutch_republic","scotland","ireland"]:
					if ss.data.id.begins_with(country): countries[country]=true
			GameManager.state.get_player(side).add_treaty_points(mini(3,countries.size()))
			if not countries.is_empty(): _reveal(side,"M-14")

func reset_exhaustion_for_turn() -> void:
	super.reset_exhaustion_for_turn()
	active_flags.clear()
	GameManager.state.britain.townshend_commodity=Enums.Commodity.NONE
