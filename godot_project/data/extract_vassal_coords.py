"""
Extract space (region) coordinate data from a Vassal module's buildFile.xml
for the Imperial Struggle game board.

Outputs JSON to vassal_space_coords.json with one object per region/zone:
    {"name": "Madras", "x": 3994, "y": 2525, "board": "main_map"}

Only the main map board ("Imperial Struggle Map_Final-150-Clean.png") is
included; player mats, war displays, etc. are skipped.
"""
import json
import xml.etree.ElementTree as ET
from pathlib import Path

XML_PATH = Path(r"X:\Imperial Struggle\vassal_extracted\buildFile.xml")
OUT_PATH = Path(r"X:\Imperial Struggle\godot_project\data\vassal_space_coords.json")
MAIN_MAP_IMAGE = "Imperial Struggle Map_Final-150-Clean.png"

# Vassal element tag names (no namespace -- they're literal class names)
BOARD_TAG = "VASSAL.build.module.map.boardPicker.Board"
ZONE_TAG = "VASSAL.build.module.map.boardPicker.board.mapgrid.Zone"
REGION_TAG = "VASSAL.build.module.map.boardPicker.board.Region"


def zone_centroid(path: str):
    """Compute the centroid of a Zone path 'x1,y1;x2,y2;...'."""
    pts = []
    for pair in path.split(";"):
        pair = pair.strip()
        if not pair:
            continue
        x_str, y_str = pair.split(",")
        pts.append((int(x_str), int(y_str)))
    if not pts:
        return None
    cx = sum(p[0] for p in pts) // len(pts)
    cy = sum(p[1] for p in pts) // len(pts)
    return cx, cy


def main():
    tree = ET.parse(XML_PATH)
    root = tree.getroot()

    out = []

    for board in root.iter(BOARD_TAG):
        if board.get("image") != MAIN_MAP_IMAGE:
            continue
        board_label = "main_map"

        for zone in board.iter(ZONE_TAG):
            zone_name = zone.get("name", "")
            child_regions = list(zone.iter(REGION_TAG))

            if child_regions:
                # Region grids: emit one entry per named region
                for region in child_regions:
                    name = region.get("name", "")
                    try:
                        x = int(region.get("originx", "0"))
                        y = int(region.get("originy", "0"))
                    except ValueError:
                        continue
                    out.append({
                        "name": name,
                        "x": x,
                        "y": y,
                        "board": board_label,
                        "zone": zone_name,
                    })
            else:
                # Standalone zone (no RegionGrid). Use path centroid as anchor.
                path = zone.get("path", "")
                centroid = zone_centroid(path) if path else None
                if centroid is None:
                    continue
                cx, cy = centroid
                out.append({
                    "name": zone_name,
                    "x": cx,
                    "y": cy,
                    "board": board_label,
                    "zone": zone_name,
                    "kind": "zone",
                })

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    print(f"Wrote {len(out)} entries to {OUT_PATH}")
    for entry in out[:10]:
        print(entry)


if __name__ == "__main__":
    main()
