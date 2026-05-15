"""Generate proximity-based connections for spaces.json."""
import json
import math

with open(r"X:\Imperial Struggle\godot_project\data\spaces.json", "r", encoding="utf-8") as f:
    spaces = json.load(f)

# Distance threshold per region (Vassal pixels)
THRESHOLDS = {
    "europe": 380,
    "north_america": 420,
    "caribbean": 420,
    "india": 420,
}

# Build connections using proximity within same region
for s in spaces:
    s["connections"] = []

for i, s1 in enumerate(spaces):
    threshold = THRESHOLDS.get(s1["region"], 400)
    for s2 in spaces:
        if s1["id"] == s2["id"]:
            continue
        if s1["region"] != s2["region"]:
            continue
        dx = s1["x"] - s2["x"]
        dy = s1["y"] - s2["y"]
        dist = math.hypot(dx, dy)
        if dist <= threshold:
            s1["connections"].append(s2["id"])

# Sort connections for stability
for s in spaces:
    s["connections"].sort()

# Cross-region/sub-region manual additions
extras = {
    "carolinas": ["san_agustin"],
    "san_agustin": ["carolinas"],
    # Fort Conquest Lines (placeholder - to be refined)
}
for sid, conn_ids in extras.items():
    for s in spaces:
        if s["id"] == sid:
            for c in conn_ids:
                if c not in s["connections"]:
                    s["connections"].append(c)

# Print stats
total_conn = sum(len(s["connections"]) for s in spaces)
print(f"Total spaces: {len(spaces)}")
print(f"Total connections: {total_conn}")
print(f"Avg connections/space: {total_conn / len(spaces):.1f}")
print(f"Max connections: {max(len(s['connections']) for s in spaces)}")
print(f"Spaces with 0 connections: {sum(1 for s in spaces if not s['connections'])}")

# Conquest lines for territories - copy from connections (subset of connections that are Conquest Lines)
# In rule terms, Conquest Lines are dashed lines on the board. We approximate by using all territory connections.
for s in spaces:
    if s.get("type") == "territory":
        s["conquest_lines"] = list(s["connections"])

with open(r"X:\Imperial Struggle\godot_project\data\spaces.json", "w", encoding="utf-8") as f:
    json.dump(spaces, f, indent=2, ensure_ascii=False)

print("\nWritten spaces.json with connections.")
