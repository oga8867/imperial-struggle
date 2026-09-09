extends RefCounted

# 평가값은 승률이 아니라 탐색 순서를 비교하는 효용 단위다.
# 이미 충분히 앞선 지역보다 '동점→보상 획득' 변화에 큰 가치를 준다.
static func edge(diff: int, margin: int = 1) -> float:
	if diff == 0: return 0.0
	return signf(diff) * (0.30 + 0.70 * minf(1.0,float(absi(diff))/maxi(1,margin)))

static func value(side: int) -> float:
	var st = GameManager.state
	var opp = WarManager._opp(side)
	var own = st.get_player(side)
	var other = st.get_player(opp)
	if st.winner != Enums.Side.NONE: return 100000.0 if st.winner==side else -100000.0
	var result = (st.vp-15)*12.0*(1 if side==Enums.Side.FRANCE else -1)
	for region in [Enums.Region.EUROPE,Enums.Region.NORTH_AMERICA,Enums.Region.CARIBBEAN,Enums.Region.INDIA]:
		var diff = GameManager._count_flags_in_region(side,region)-GameManager._count_flags_in_region(opp,region)
		var award = AwardManager.get_award_for_region(region)
		result += edge(diff,int(award.get("margin_required",1))) * (float(award.get("vp",0))*8.0+float(award.get("tp",0))*1.5)
		result += clampf(diff,-5,5)*0.4
	for commodity in st.current_global_demand:
		var diff = GameManager._count_commodity_markets(side,commodity)-GameManager._count_commodity_markets(opp,commodity)
		var reward = GameManager.commodity_reward(commodity)
		result += edge(diff)*(reward[0]*8.0-reward[1]*1.5+reward[2]*1.5)
	var prestige = 0
	for ss in st.spaces.values():
		if ss.controlled_by==Enums.Side.NONE: continue
		var polarity = 1 if ss.controlled_by==side else -1
		if not ss.has_conflict_marker:
			if _prestige_eligible(ss): prestige += polarity
			result += polarity*_infrastructure(ss)
		elif ss.data.space_type==Enums.SpaceType.MARKET: result -= polarity*0.7
	result += edge(prestige)*16.0
	var debt_value = 2.7 if st.current_turn==6 else 1.7
	result += (own.available_debt()-other.available_debt())*debt_value
	result += (mini(own.treaty_points,4)-mini(other.treaty_points,4))*1.8
	result += (maxi(0,own.treaty_points-4)-maxi(0,other.treaty_points-4))*0.6
	result += (own.total_squadrons()-other.total_squadrons())*2.0
	# 상대 카드의 내용은 평가하지 않는다. 장수만 공개 정보다.
	result += minf(own.hand.size(),3)*1.5-minf(other.hand.size(),3)*1.5
	for card in own.hand: result += card_value(card,side)*0.15
	# 미공개 내각은 다음 내각 단계에 교체할 선택권이 있다. 효과 없는 공개에는
	# 작은 기회비용을 두어 '모두 공개'가 공짜 기본 행동이 되지 않게 한다.
	for card in own.ministry_cards:
		if not card.is_revealed: result += 0.8
		else: result += passive_ministry_value(card,side)
	for card in other.ministry_cards:
		if card.is_revealed: result -= passive_ministry_value(card,opp)
	if st.current_turn<6:
		for th in WarManager.get_upcoming_theaters():
			result += war_value(th.id,side)
	return result

static func _prestige_eligible(ss: SpaceState) -> bool:
	if not ss.data.is_prestige: return false
	return ss.data.region==Enums.Region.EUROPE or (GameManager.state.current_turn==6 and ss.data.id.begins_with("usa_") and GameManager.state.spaces.values().any(func(s): return s.has_usa_flag))

static func _infrastructure(ss: SpaceState) -> float:
	var base = 0.7 + ss.data.connections.size()*0.13
	if ss.data.is_alliance: base += 1.1
	if ss.data.space_type==Enums.SpaceType.TERRITORY: base += 4.0
	if ss.data.space_type==Enums.SpaceType.NAVAL: base += 0.8
	if ss.data.space_type==Enums.SpaceType.FORT: base += 0.6 if ss.is_fort_damaged else 1.2
	return base

static func space_gain(ss: SpaceState,side: int) -> float:
	var opp = WarManager._opp(side)
	var diff = GameManager._count_flags_in_region(side,ss.data.region)-GameManager._count_flags_in_region(opp,ss.data.region)
	var award = AwardManager.get_award_for_region(ss.data.region)
	var margin = int(award.get("margin_required",1))
	var gain = (edge(diff+1,margin)-edge(diff,margin))*(float(award.get("vp",0))*8.0+float(award.get("tp",0))*1.5)
	if ss.data.space_type==Enums.SpaceType.MARKET and ss.data.commodity in GameManager.state.current_global_demand:
		var cd = GameManager._count_commodity_markets(side,ss.data.commodity)-GameManager._count_commodity_markets(opp,ss.data.commodity)
		var reward = GameManager.commodity_reward(ss.data.commodity)
		gain += (edge(cd+1)-edge(cd))*(reward[0]*8.0-reward[1]*1.5+reward[2]*1.5)
	if _prestige_eligible(ss):
		var pd = 0
		for s in GameManager.state.spaces.values():
			if _prestige_eligible(s) and not s.has_conflict_marker and s.controlled_by!=Enums.Side.NONE: pd += 1 if s.controlled_by==side else -1
		gain += (edge(pd+1)-edge(pd))*16.0
	return gain + _infrastructure(ss) + 0.4

static func war_value(id: String,side: int,added: float = 0.0) -> float:
	var th = WarManager.get_upcoming_theaters().filter(func(t): return t.id==id)[0]
	var opp = WarManager._opp(side)
	var own = WarManager._calculate_army_strength(id,side)+WarManager._calculate_bonus_strength(th,side)
	# 상대 뒷면의 실제 전력 대신 공개 장수와 인쇄 구성의 기대치를 쓴다.
	var enemy = WarManager._calculate_bonus_strength(th,opp,true)+0.44+WarManager.bonus_war_tiles_in_theater.get(id,{}).get(opp,[]).size()*1.5
	if WarFlow.active:
		var theaters=WarManager.get_upcoming_theaters()
		if theaters.find(th)<=WarFlow.index: enemy=WarManager._calculate_army_strength(id,opp)+WarManager._calculate_bonus_strength(th,opp)
	var diff = own+added-enemy
	var urgency = 0.65 if GameManager.state.current_turn==1 else 1.0
	return tanh(diff/3.0)*22.0*urgency

static func card_value(card: EventCard,side: int) -> float:
	var score = 2.0
	if EventEffects.bonus_condition_met(card,side,false): score += 2.0
	if card.major_action==Enums.ActionType.NONE: score += 0.5
	return score

static func passive_ministry_value(card: MinistryCard,side: int) -> float:
	# 득점 때 공개할 수 없으므로 이번 자기 라운드에 미리 공개할 가치도 계산한다.
	var st=GameManager.state
	var opp=WarManager._opp(side)
	var europe=GameManager._count_flags_in_region(side,Enums.Region.EUROPE)-GameManager._count_flags_in_region(opp,Enums.Region.EUROPE)
	var award=AwardManager.get_award_for_region(Enums.Region.EUROPE)
	var margin=int(award.get("margin_required",1))
	match card.id:
		"M-2": return mini(st.get_player(side).current_debt,2 if MinistryEffects._count_controlled_containing(side,"scotland")>0 else 1)*1.7
		"M-3": return 8.0 if europe>=margin else 0.0
		"M-18": return 8.0 if europe>=margin or (europe<=-margin and int(award.get("vp",0))>0) else 0.0
		"M-12":
			var result=0.0
			var india=GameManager._count_flags_in_region(side,Enums.Region.INDIA)-GameManager._count_flags_in_region(opp,Enums.Region.INDIA)
			if india>=int(AwardManager.get_award_for_region(Enums.Region.INDIA).get("margin_required",1)): result+=1.8
			for commodity in [Enums.Commodity.COTTON,Enums.Commodity.SPICE]:
				if commodity in st.current_global_demand and GameManager._count_commodity_markets(side,commodity)>GameManager._count_commodity_markets(opp,commodity): result+=1.8
			return result
		"M-7":
			var count=0
			for adv in AdvantageManager.advantages.values():
				if adv.controlled_by==side and not adv.is_exhausted and adv.id in ["textiles_adv","silk_adv","fruit_adv","fur_trade_adv","rum_adv"]: count+=1
			return mini(3,count)*8.0
		"M-14":
			var countries={}
			for ss in st.spaces.values():
				if ss.controlled_by!=side or not ss.data.is_prestige or ss.has_conflict_marker: continue
				for country in ["spain","austria","prussia","dutch_republic","scotland","ireland"]:
					if ss.data.id.begins_with(country): countries[country]=true
			return mini(3,countries.size())*1.8
	return 0.0
