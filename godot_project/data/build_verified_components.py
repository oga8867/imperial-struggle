"""2쇄 전쟁 보드와 투자·지역 보상 타일에서 직접 대조한 데이터.

이 파일은 실행 게임의 일부가 아니라 데이터 재생성 도구다.
전쟁 순서와 보상은 assets/board/War Display_*.jpg에 근거한다.
표기 숫자를 임의로 일반화하면 전장별 전략이 달라지므로 각 행을 보존한다.
"""
import json
from pathlib import Path

ROOT = Path(__file__).parent
def write(name, value):
    (ROOT/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def row(margin, winner, loser=()):
    return dict(margin=margin, winner=list(winner), loser=list(loser))
def theater(id, name, ko, region, bonus, rows, additional=(), regions=None):
    return dict(id=id, name=name, name_ko=ko, region=region, regions=regions or [region],
                bonus_strength=bonus, spoils=rows, additional_territories=list(additional))

central = ['alliance_'+s for s in ['austria','bavaria','denmark','dutch_republic','german_states']]
na = ['conflict_marker','fort_north_america','squadron_north_america']
india = ['conflict_marker','fort_india','squadron_india']
overseas = ['san_agustin','asiento','hudson_bay','acadia']
wars = {
 'spanish_succession': dict(name='War of the Spanish Succession',name_ko='스페인 왕위계승 전쟁',war_dot=1,theaters=[
  theater('central_europe_wss','Central Europe','중부 유럽','europe',central+['alliance_savoy'],[
   row('1-2',['2vp'],['1tp']),row('3-4',['2vp','1cp'],['2tp']),row('5+',['3vp','2cp'],['3tp'])],overseas),
  theater('spain_wss','Spain','스페인','europe',['keyword_governance','alliance_sardinia','alliance_spain','squadron_europe'],[
   row('1',['1vp'],['1tp']),row('2-3',['1vp','1cp'],['2tp']),row('4+',['1vp','2cp'],['2tp'])],overseas[:2]),
  theater('queen_annes_war',"Queen Anne's War",'앤 여왕의 전쟁','north_america',na,[
   row('1-2',['1vp']),row('3',['1vp','1cp'],['1tp']),row('4+',['1vp','unflag_market_north_america','1cp'],['2tp'])]),
  theater('jacobite_rebellion_wss','Jacobite Rebellion','재커바이트 반란','europe',
   ['keyword_style','alliance_dutch_republic','alliance_ireland','alliance_scotland','conflict_marker'],[
   row('1-2',['1vp']),row('3-4',['2vp'],['1tp']),row('5+',['4vp'],['2tp'])]),
 ]),
 'austrian_succession': dict(name='War of the Austrian Succession',name_ko='오스트리아 왕위계승 전쟁',war_dot=2,theaters=[
  theater('central_europe_was','Central Europe','중부 유럽','europe',central+['alliance_prussia','alliance_sweden'],[
   row('1-2',['1vp']),row('3+',['1vp','1cp'],['1tp'])],overseas),
  theater('king_georges_war',"King George's War",'조지 왕의 전쟁','north_america',na,[
   row('1-2',['1cp']),row('3+',['1cp','unflag_market_north_america'],['1tp'])],['san_agustin']),
  theater('first_carnatic_war','First Carnatic War','제1차 카르나틱 전쟁','india',india,[
   row('1-2',['1cp']),row('3',['2cp'],['1tp']),row('4+',['2cp','unflag_market_india'],['2tp'])]),
  theater('jacobite_rebellion','Jacobite Rebellion','재커바이트 반란','europe',
   ['keyword_style','alliance_ireland','alliance_scotland','conflict_marker'],[
   row('fr_1',['2vp','jacobite_victory'],['1tp']),
   row('fr_2-3',['3vp','unflag_political_europe','jacobite_victory'],['2tp']),
   row('fr_4+',['5vp','unflag_political_europe','jacobite_victory'],['3tp']),
   row('br_1',['1vp']),row('br_2',['2vp','unflag_political_europe','jacobite_defeat'],['1tp']),
   row('br_3+',['3vp','unflag_political_europe','jacobite_defeat'],['2tp'])]),
 ]),
 'seven_years': dict(name="Seven Years' War",name_ko='7년 전쟁',war_dot=3,theaters=[
  theater('atlantic_dominance','Atlantic Dominance','대서양 제해권','europe',
   ['squadron_caribbean','squadron_europe','squadron_north_america'],[
   row('2',['atlantic_dominance']),row('3-4',['atlantic_dominance'],['unbuild_squadron']),
   row('5+',['atlantic_dominance'],['unbuild_squadron','unbuild_squadron'])]),
  theater('third_carnatic_war','Third Carnatic War','제3차 카르나틱 전쟁','india',india,[
   row('1-2',['1cp'],['1tp']),row('3-4',['1cp','unflag_market_india'],['2tp']),row('5+',['2cp','unflag_market_india'],['3tp'])]),
  theater('french_indian_war','French & Indian War','프렌치 인디언 전쟁','north_america',
   ['alliance_spain','conflict_marker','fort_north_america','fort_caribbean','squadron_caribbean','squadron_north_america','atlantic_dominance'],[
   row('1-2',['1cp','unflag_market_north_america'],['1tp']),row('3-4',['1vp','2cp'],['3tp']),row('5+',['2vp','3cp'],['4tp'])],
   ['minorca','gibraltar'],['north_america','caribbean']),
  theater('prussias_wars',"Prussia's Wars",'프로이센의 전쟁','europe',central+['alliance_prussia','alliance_russia','alliance_sweden'],[
   row('1-2',['2vp']),row('3-4',['3vp']),row('5+',['4vp'],['1tp'])]),
 ]),
 'american_independence': dict(name='American War of Independence',name_ko='미국 독립전쟁',war_dot=4,theaters=[
  theater('american_revolution','American Revolution','미국 혁명','north_america',
   ['alliance_german_states','keyword_sons_of_liberty','alliance_spain']+na,[
   row('fr_1-2',['2vp','usa'],['2tp']),row('fr_3-4',['3vp','usa'],['2tp']),row('fr_5+',['4vp','usa','canada'],['3tp']),
   row('br_1',['2vp']),row('br_2-3',['3vp','1cp'],['1tp']),row('br_4+',['4vp','2cp'],['2tp'])],['san_agustin']),
  theater('mysore_war','Mysore War','마이소르 전쟁','india',india,[row('1-2',['1cp'],['1tp']),row('3+',['2cp'],['3tp'])]),
  theater('antilles_war','Antilles War','앤틸리스 전쟁','caribbean',['alliance_spain','conflict_marker','squadron_caribbean'],[
   row('1',['1cp']),row('2-3',['1cp','unflag_market_caribbean'],['1tp']),row('4+',['2cp','unflag_market_caribbean'],['2tp'])],['hudson_bay','acadia']),
 ])
}
write('wars.json',wars)

# 지역에 고정된 타일이 아니다. 8개 중 4개를 매 턴 배정하고 시대마다 다시 섞는다 (§4.1.3).
awards=[]
for vp,trp,margin,count in [(0,1,1,2),(1,1,1,2),(1,0,1,2),(2,0,2,1),(3,0,2,1)]:
 for i in range(count):
  awards.append(dict(id=f'award_{len(awards)+1}',vp=vp,tp=trp,margin_required=margin,name=f'{vp} VP'+(' + TRP' if trp else '')))
write('awards.json',awards)

# 실제 Investment_01~24 이미지 순서. 4점짜리 타일이 각 조합마다 두 장 있다.
configs=[(2,4,3),(2,4,1),(2,4,1),(2,4,3),(2,3,3),(2,3,1),(1,4,2),(2,2,1),
 (2,2,3),(1,4,2),(1,4,3),(1,4,3),(1,2,3),(1,3,2),(1,3,3),(1,2,2),
 (3,4,1),(3,4,1),(3,3,1),(3,4,2),(3,4,2),(3,3,2),(3,2,1),(3,2,2)]
write('investments.json',[dict(id=i+1,major=m,points=p,minor=n,event=p<4,upgrade=p==2) for i,(m,p,n) in enumerate(configs)])
