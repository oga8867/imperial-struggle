"""2쇄 지도 검은 실선만 전사. 점선 정복선과 이점 연결선은 별도로 보존한다.

이전 데이터는 가까운 공간들을 연결해 실제 지도에 없는 경로를 허용했다.
한쪽에서 입력한 연결을 양방향으로 확장하여 불일치를 방지한다.
"""
import json
from pathlib import Path
root = Path(__file__).parent
spaces = json.loads((root/'spaces.json').read_text(encoding='utf8'))
by_id = {s['id']:s for s in spaces}
edges = '''
hudson_bay: york_factory
quebec_and_montreal: cataraqui ile_aux_noix gulf_of_st_lawrence
cataraqui: niagara
ile_aux_noix: niagara champlain_valley_fort albany
champlain_valley_fort: oswego albany
niagara: oswego allegheny ohio_forks_fort
oswego: albany
albany: cumberland hudson_valley
allegheny: ohio_forks_fort cumberland
ohio_forks_fort: cumberland
hudson_valley: cumberland northern_colonies
northern_colonies: cumberland mass_bay chesapeake
mass_bay: gulf_of_maine_naval georges_bank
gulf_of_maine_naval: halifax_fort georges_bank
gulf_of_st_lawrence: cabot_strait_naval louisbourg_fort georges_bank
cabot_strait_naval: louisbourg_fort
halifax_fort: northeast_channel georges_bank
acadia: northeast_channel louisbourg_fort
northeast_channel: louisbourg_fort georges_bank
georges_bank: louisbourg_fort atlantic_passage_naval
louisiana: st_james
san_agustin: panzacola
carolinas: georgia bahamas_run_west
st_james: bahamas_run_west cuba_passage_east cuba_passage_naval cayman_passage
bahamas_run_north: bahamas_run_west bahamas_run_naval caicos
bahamas_run_west: bahamas_run_naval cuba_passage_east caicos
bahamas_run_naval: caicos
cuba_passage_east: cuba_passage_naval cayman_passage
cayman_passage: cuba_passage_naval jamaica
havana: puerto_principe gulf_of_cazones_naval santiago
puerto_principe: puerto_rico santiago st_domingue
gulf_of_cazones_naval: santiago
santiago: jamaica
caicos: st_domingue
port_de_paix: st_domingue
puerto_rico: antigua
antigua: antilles_channel_naval st_lucia
martinique: guadeloupe antilles_channel_naval st_lucia
st_lucia: antilles_channel_naval barbados
west_bengal: mangalore plassey midnapore hooghly_river_naval
plassey: chandernagore hooghly_river_naval malacca_route
hooghly_river_naval: midnapore malacca_route
midnapore: calcutta kurpa
mangalore: calicut malabar_coast_naval
calicut: malabar_coast_naval tiruchirappalli
kurpa: vellore arcot_fort
vellore: arcot_fort kanchipuram tiruchirappalli
kanchipuram: madras vandavasi_fort tiruchirappalli karaikal
tiruchirappalli: vandavasi_fort karaikal
karaikal: vandavasi_fort pondicherry
'''
for s in spaces: s['connections']=[];s['sub_region']='none'
for line in edges.strip().splitlines():
 a,rest=line.split(':')
 for b in rest.split():
  assert a in by_id and b in by_id,(a,b)
  by_id[a]['connections'].append(b);by_id[b]['connections'].append(a)
# 지역 내 굵은 흰 경계로 구분된 하위 지역. 정치 공간도 위치한 하위 지역에 속한다.
subregions={
 'northern_colonies':'niagara champlain_valley_fort halifax_fort oswego albany hudson_valley mass_bay northern_colonies chesapeake allegheny ohio_forks_fort cumberland iroquois_la sons_of_liberty_la gulf_of_maine_naval atlantic_passage_naval usa_prestige_prestige usa_prestige_prestige_b',
 'canada':'hudson_bay york_factory algonquin_la cataraqui quebec_and_montreal ile_aux_noix gulf_of_st_lawrence cabot_strait_naval acadia louisbourg_fort northeast_channel georges_bank',
 'hooghly_river':'maratha_la plassey west_bengal midnapore chandernagore calcutta hooghly_river_naval malacca_route',
 'carnatic_coast':'mangalore calicut malabar_coast_naval nizam_la mysore_la kurpa vellore arcot_fort kanchipuram madras pondicherry karaikal vandavasi_fort tiruchirappalli',
}
for sub,ids in subregions.items():
 for sid in ids.split(): by_id[sid]['sub_region']=sub
for sid in ['prussia_alliance_b','prussia_prestige_b']: by_id[sid]['available_era']='empire'
by_id['sons_of_liberty_la']['available_era']='revolution'
for s in spaces: s['connections'].sort()
(root/'spaces.json').write_text(json.dumps(spaces,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
adv=json.loads((root/'advantage_connections.json').read_text(encoding='utf8'))
connections={
 'wheat':'chesapeake','fur_trade':'hudson_bay','algonquin_raids':'algonquin_la','iroquois_raids':'iroquois_la','patriot_agitation':'sons_of_liberty_la',
 'fruit':'san_agustin','letters_of_marque':'privateers_la','pirate_havens':'buccaneers_la','rum':'puerto_rico','slaving_contracts':'asiento',
 'silk':'west_bengal','power_struggle':'mysore_la','raids_and_incursions':'maratha_la','separatist_wars':'nizam_la','textiles':'tiruchirappalli',
 'mediterranean_intrigue':'spain_prestige_b savoy_alliance','naval_bastion':'gibraltar minorca','italy_influence':'austria_alliance_b sardinia_alliance',
 'central_europe_conflict':'german_states_saxony_alliance_b bavaria_alliance','german_diplomacy':'prussia_prestige_b','baltic_trade':'denmark_norway_alliance prussia_alliance','silesia_negotiations':'austria_prestige',
}
for key,ids in connections.items():
 assert all(sid in by_id for sid in ids.split())
 adv['advantages'][key+'_adv']['connected_spaces']=ids.split()
adv['comment']='2쇄 원본 지도의 이점 연결선 직접 대조. 효과는 advantage_rules.json에 별도 기록.'
(root/'advantage_connections.json').write_text(json.dumps(adv,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
