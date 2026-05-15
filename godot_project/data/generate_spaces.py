"""Regenerate spaces.json from Vassal coordinate data with proper Korean encoding."""
import json
import re
import unicodedata
from collections import defaultdict

with open(r"X:\Imperial Struggle\godot_project\data\vassal_space_coords.json", "r", encoding="utf-8") as f:
    data = json.load(f)

geo_zones = ["North America", "Caribbean", "India", "Europe"]
board = [e for e in data if e.get("zone") in geo_zones]

zone_to_region = {
    "Europe": "europe", "North America": "north_america",
    "Caribbean": "caribbean", "India": "india",
}

KO = {
    "Hudson Bay": "허드슨만", "Québec & Montreal": "퀘벡 & 몬트리올", "Algonquin": "알곤킨",
    "Acadia": "아카디아", "Mass. Bay": "매사추세츠만", "Hudson Valley": "허드슨 계곡",
    "Champlain Valley": "샹플랭 계곡", "Northern Colonies": "북부 식민지", "Carolinas": "캐롤라이나",
    "San Agustín": "산아구스틴", "San Agustin": "산아구스틴", "Cherokee": "체로키",
    "Chesapeake": "체서피크", "Iroquois": "이로쿼이", "Newfoundland": "뉴펀들랜드",
    "Cataraqui": "카타라키", "Ile-aux-Noix": "일오누아", "Cumberland": "컴벌랜드",
    "Ohio Forks": "오하이오 포크", "Louisbourg": "루이부르", "Halifax": "핼리팩스",
    "Gulf of St. Lawrence": "세인트로렌스만", "Gulf of Maine": "메인만",
    "Louisiana": "루이지애나", "Port de Paix": "포드페", "St. Domingue": "생도맹그",
    "Saint Domingue": "생도맹그", "Martinique": "마르티니크", "Guadeloupe": "과들루프",
    "Georgia": "조지아", "St. Lucia": "세인트루시아", "Antigua": "앤티가",
    "Barbados": "바베이도스", "Trinidad": "트리니다드", "Jamaica": "자메이카",
    "Havana": "아바나", "Santiago": "산티아고", "Puerto Principe": "푸에르토프린시페",
    "Asiento": "아시엔토", "Madras": "마드라스", "Pondicherry": "퐁디셰리",
    "Karaikal": "카라이칼", "Tiruchirapalli": "티루치라팔리", "Vellore": "벨로르",
    "Vandavasi": "반다바시", "Calcutta": "캘커타", "Hooghly River": "후글리강",
    "Chandernagore": "찬데르나고르", "Bombay": "봄베이", "Malabar Coast": "말라바르 해안",
    "Malacca Route": "말라카 항로", "West Bengal": "서벵골", "Plassey": "플라시",
    "Mysore": "마이소르", "Nizam": "니잠", "Bengal": "벵골", "Maratha": "마라타",
    "Gibraltar": "지브롤터", "Minorca": "미노르카", "Spain": "스페인",
    "Portugal": "포르투갈", "Savoy": "사보이", "Sardinia": "사르데냐",
    "Austria": "오스트리아", "German States": "독일 제후국", "Prussia": "프로이센",
    "Dutch Republic": "네덜란드 공화국", "Denmark • Norway": "덴마크-노르웨이",
    "Sweden": "스웨덴", "Russia": "러시아", "Scotland": "스코틀랜드",
    "Ireland": "아일랜드", "Sons of Liberty": "자유의 아들들",
    "Biscay": "비스케이만", "North Sea": "북해", "Mediterranean": "지중해",
    "Atlantic Ocean": "대서양", "English Channel": "영국 해협",
    "York Factory": "요크 팩토리", "Niagara": "나이아가라", "Oswego": "오스위고",
    "Albany": "올버니", "Allegheny": "앨러게니", "Northeast Channel": "북동 해협",
    "Georges Bank": "조지스 뱅크", "Cabot Strait": "캐벗 해협",
    "USA Prestige": "미국 위신",
}


def slugify(s):
    s = s.replace("•", "").replace("&", "and").replace("'", "")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "_", s).strip("_").lower()
    return s


def parse_entry(e):
    name = e["name"]
    base = name.split(" (")[0].strip()
    region = zone_to_region[e["zone"]]
    out = {"display_name": base, "name_ko": KO.get(base, base),
           "x": e["x"], "y": e["y"], "region": region}

    if "(Advantage)" in name:
        out.update({"type": "advantage"})
        return out, slugify(base) + "_adv"
    if "(Territory)" in name:
        out.update({"type": "territory", "conquest_cost": 1})
        return out, slugify(base)
    if "(Naval)" in name:
        out.update({"type": "naval", "base_cost": 1})
        return out, slugify(base) + "_naval"
    m = re.search(r"\(Fort:\s*(\d+)\)", name)
    if m:
        out.update({"type": "fort", "base_cost": int(m.group(1))})
        return out, slugify(base) + "_fort"
    m = re.search(r"\(Local Alliance:\s*(\d+)\)", name)
    if m:
        out.update({"type": "political", "base_cost": int(m.group(1)),
                    "is_local_alliance": True})
        return out, slugify(base) + "_la"
    m = re.search(r"\(Alliance:\s*(\d+)\)", name)
    if m:
        out.update({"type": "political", "base_cost": int(m.group(1)),
                    "is_alliance": True})
        return out, slugify(base) + "_alliance"
    m = re.search(r"\(Prestige:\s*(\d+)\)", name)
    if m:
        out.update({"type": "political", "base_cost": int(m.group(1)),
                    "is_prestige": True})
        return out, slugify(base) + "_prestige"
    m = re.search(r"\(Alliance . Prestige:\s*(\d+)\)", name)
    if m:
        out.update({"type": "political", "base_cost": int(m.group(1)),
                    "is_alliance": True, "is_prestige": True})
        return out, slugify(base) + "_alliance"
    m = re.search(r"\((Fish|Furs?|Spice|Sugar|Tobacco|Cotton):\s*(\d+)\)", name)
    if m:
        commodity = m.group(1).lower().rstrip("s")
        out.update({"type": "market", "base_cost": int(m.group(2)),
                    "commodity": commodity})
        return out, slugify(base)
    m = re.search(r"\(Market:\s*(\d+)\)", name)
    if m:
        commodity = "tobacco" if "Chesapeake" in name else "fish"
        out.update({"type": "market", "base_cost": int(m.group(1)),
                    "commodity": commodity})
        return out, slugify(base)
    if "Award" in name:
        return None, None
    return None, None


spaces = {}
for e in board:
    parsed, sid = parse_entry(e)
    if parsed is None or sid is None:
        continue
    base_sid = sid
    suffix = 0
    while sid in spaces:
        suffix += 1
        sid = f"{base_sid}_{chr(ord('b') + suffix - 1)}"
    parsed["id"] = sid
    spaces[sid] = parsed

INITIAL_BR = ["gibraltar", "minorca", "halifax_naval", "halifax_fort", "hudson_bay",
              "newfoundland", "mass_bay", "carolinas", "northern_colonies",
              "jamaica", "barbados", "antigua", "bombay", "madras", "calcutta",
              "georges_bank"]
INITIAL_FR = ["quebec_and_montreal", "acadia", "louisbourg_fort", "louisiana",
              "champlain_valley", "champlain_valley_fort", "ile_aux_noix",
              "martinique", "saint_domingue", "st_domingue", "guadeloupe",
              "port_de_paix", "pondicherry", "chandernagore"]

for sid, sp in spaces.items():
    if sid in INITIAL_BR:
        sp["starting_control"] = "britain"
    elif sid in INITIAL_FR:
        sp["starting_control"] = "france"

gameplay_spaces = [s for s in spaces.values() if s.get("type") != "advantage"]
advantage_spaces = [s for s in spaces.values() if s.get("type") == "advantage"]

for s in gameplay_spaces:
    s["connections"] = []
    if s.get("type") == "territory":
        s["conquest_lines"] = []

with open(r"X:\Imperial Struggle\godot_project\data\spaces.json", "w", encoding="utf-8") as f:
    json.dump(gameplay_spaces, f, indent=2, ensure_ascii=False)

with open(r"X:\Imperial Struggle\godot_project\data\advantages.json", "w", encoding="utf-8") as f:
    json.dump(advantage_spaces, f, indent=2, ensure_ascii=False)

coords = [{"id": s["id"], "x": s["x"], "y": s["y"]} for s in gameplay_spaces]
with open(r"X:\Imperial Struggle\godot_project\data\space_coords.json", "w", encoding="utf-8") as f:
    json.dump(coords, f, indent=2)

print(f"Gameplay spaces: {len(gameplay_spaces)}")
print(f"Advantage spaces: {len(advantage_spaces)}")
print(f"Coords: {len(coords)}")

by_r = defaultdict(list)
for s in gameplay_spaces:
    by_r[s["region"]].append(s)
for r, items in by_r.items():
    print(f"  {r}: {len(items)}")

# Verify Korean encoding
with open(r"X:\Imperial Struggle\godot_project\data\spaces.json", "rb") as f:
    raw = f.read()
print(f"\nFile size: {len(raw)} bytes")
print(f"Sample of file (first 600 chars):")
print(raw[:600].decode("utf-8"))
