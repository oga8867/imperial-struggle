"""Merge conquest_lines.json into spaces.json conquest_lines fields."""
import json

with open(r"X:\Imperial Struggle\godot_project\data\spaces.json", "r", encoding="utf-8") as f:
    spaces = json.load(f)
with open(r"X:\Imperial Struggle\godot_project\data\conquest_lines.json", "r", encoding="utf-8") as f:
    cl_data = json.load(f)

# Reset conquest lines from manual data only
for s in spaces:
    if s.get("type") == "territory":
        s["conquest_lines"] = []

# Build mapping
sid_set = {s["id"] for s in spaces}

valid_lines = 0
invalid_lines = 0
for line in cl_data["lines"]:
    f_id, t_id = line["from"], line["to"]
    if f_id not in sid_set or t_id not in sid_set:
        invalid_lines += 1
        print(f"  Skipping invalid line: {f_id} -> {t_id}")
        continue
    valid_lines += 1
    # Add bidirectional conquest line ref
    for s in spaces:
        if s["id"] == f_id and t_id not in s.get("conquest_lines", []):
            s.setdefault("conquest_lines", []).append(t_id)
        if s["id"] == t_id and f_id not in s.get("conquest_lines", []):
            s.setdefault("conquest_lines", []).append(f_id)

print(f"Valid lines: {valid_lines}, invalid: {invalid_lines}")

with open(r"X:\Imperial Struggle\godot_project\data\spaces.json", "w", encoding="utf-8") as f:
    json.dump(spaces, f, indent=2, ensure_ascii=False)
print("Updated spaces.json with conquest lines.")
