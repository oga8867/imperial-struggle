"""assets/war_tiles 실제 96장 앞면을 대조한 수치. 파일 이름 순으로 대응한다."""
from pathlib import Path
import json,re
root=Path(__file__).parent
# 숫자=전력, D=강제 부채, F=요새 손상 또는 함대 귀환. 이름은 원본 이미지와 연결한다.
values={
 '7YW_BR':'2 1F 3 2 1D 1 1D 1F 2 3 1 2',
 '7YW_FR':'1D 2 1 3 1F 2 1D 1 1F 3 2 2',
 'AWI_BR':'1F 2 1F 1D 2 3 1 1 2 2 3 1D',
 'AWI_FR':'2 1D 1D 1 1F 2 2 3 1F 1 2 3',
 'WAS_BR':'2 1D 3 1 2 1D 1 1F 1F 3 2 2',
 'WAS_FR':'2 2 1 1D 2 3 1F 2 1D 1 3 1F',
 'WSS_BR':'2 1 2 1D 1F 1F 3 3 1D 2 2 1',
 'WSS_FR':'2 1D 2 1F 1 2 1D 3 1 2 1F 3',
}
war_ids={'WSS':'spanish_succession','WAS':'austrian_succession','7YW':'seven_years','AWI':'american_independence'}
entries=[]
for group,tokens in values.items():
 files=sorted(p for p in (root.parent/'assets/war_tiles').glob(f'WarTile_{group}-Bonus-*.png') if 'Back' not in p.name)
 assert len(files)==12,(group,len(files))
 for file,token in zip(files,tokens.split(),strict=True):
  title=file.stem.split('-Bonus-')[1]
  entries.append(dict(id=file.stem,war=war_ids[group.split('_')[0]],side=1 if group.endswith('BR') else 2,
   name=re.sub(r'(?<=[a-z])(?=[A-Z])',' ',title),strength=int(token[0]),effect=1 if 'D' in token else 2 if 'F' in token else 0,
   image='res://assets/war_tiles/'+file.name))
 for side_entries in [entries[-12:]]:
  assert sum(x['strength'] for x in side_entries)==20
  assert sum(x['effect']==1 for x in side_entries)==2
  assert sum(x['effect']==2 for x in side_entries)==2
(root/'war_tiles.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
