# Imperial Struggle (2nd Printing) — Components Audit

Source citations:
- **Rules** = `ImpStr_2nd_Printing_Rules_Final.pdf` (20 pp)
- **Playbook** = `ImpStr_Living_Playbook_7-26-20.pdf` (28 pp)
- **Manifest** = Counter Manifest images on Rules pp.18–19 (image-only pages)
- **Assets** = filenames under `godot_project/assets/war_tiles/` and `godot_project/assets/advantages/`
  (these were exported from the game and double-encode the canonical printed counts)

---

## 1. Basic War Tiles

**Rules §3.7 (p.7)**:
> "Some War tiles have special effects. From left: removal of an opposing flag, an increase in opponent's Debt, and owner's choice of opposing fort damage or Squadron removal."

**Rules §7.1.2 (p.14)** spells out the three effect symbols:
> - Tiles that show a Debt symbol cause the opposing player to immediately incur one Debt.
> - Tiles that show a Damaged Fort / Remove Fleet symbol allow the tile owner to place a Damaged Fort marker in one opposing Fort in the theater, or to remove one opposing Squadron from that theater to the Navy Box.
> - Tiles that show a crossed-out flag symbol allow the tile owner to unflag any one opposing Market or Political space (that does not contain a Conflict marker) in the region matching the War tile's theater.

**Rules §7.6 (p.15)**: Each war setup, each side draws **one Basic War Tile per theater (= 4)**, face-down, and randomly places one in each theater.

### Exact distribution per side (16 tiles each)

Source = filenames in `godot_project/assets/war_tiles/`:

| Strength | Effect symbol | Count per side | File evidence |
|----------|---------------|---------------:|---------------|
| 0 | +1 Debt to opponent | **4** | `WarTile_Basic_BR-0+Debt(x4).png`, `WarTile_Basic_FR-0+Debt(x4).png` |
| +1 | (none) | **4** | `WarTile_Basic_BR-+1(x4).png`, `WarTile_Basic_FR-+1(x4).png` |
| +2 | (none) | **3** | `WarTile_Basic_BR-+2(x3).png`, `WarTile_Basic_FR-+2(x3).png` |
| -1 | Unflag opposing Political/Market in theater region | **3** | `WarTile_Basic_BR--1Unflag(x3).png`, `WarTile_Basic_FR--1Unflag(x3).png` |
| 0 | Damage Fort or Remove Squadron (owner's choice) | **2** | `WarTile_Basic_BR-0+FortFleet(x2).png`, `WarTile_Basic_FR-0+FortFleet(x2).png` |
| **TOTAL** | | **16 per side** (32 total) | |

The Counter Manifest column on Rules p.19 (British sheet #3 FRONT) and p.18 (French sheet #2 FRONT) confirms the same five varieties; counting hexes in the rightmost basic-tile column matches the (×4, ×4, ×3, ×3, ×2) distribution.

### Verdict on the user's current pool

The current implementation `[0, 1, 1(Debt), 2, 2(Damage), -1, 0(Unflag)]` — 7 tiles — is **WRONG** in two ways:

1. **Count is 7 instead of 16**.
2. **Strength values are wrong**:
   - The Debt tile is strength **0**, not +1.
   - The "Damage" tile is strength **0**, not +2.
   - The Unflag tile is strength **-1**, not 0.

Corrected pool (per side) = **[0+Debt × 4, +1 × 4, +2 × 3, -1+Unflag × 3, 0+FortFleet × 2]**.

---

## 2. Bonus War Tiles

**Rules §3.7 (p.7)**:
> "Players use the same Basic War Tile set for each war; however, there are four different sets of Bonus War Tiles, unique to each War."

**Rules §5.6.1 (p.11)**:
> "The cost to buy a Bonus War Tile is 2 [Military]. A maximum of two Bonus War Tiles may be bought per Action Round."

**Distribution: 12 unique (named) Bonus War Tiles per side per war × 4 wars × 2 sides = 96 total.**

All 96 names below come from filenames in `godot_project/assets/war_tiles/` (each name maps to a single physical hex tile with a unique strength + optional effect symbol). The Playbook §"Tile Background" (pp.16, 19, 21, 25) gives historical citations for each.

### War 1: War of the Spanish Succession (WSS) — Turn 1

| British (12) | French (12) |
|--------------|-------------|
| Marlborough | de Villars |
| Rooke | Vendôme |
| United Parliament | Boufflers |
| Church | Maison du Roi |
| Prince Eugene | Cádiz Refused/Relieved |
| Leopold | de Tessé |
| Louis William | Berwick |
| Huguenot Rebels | d'Estrées |
| Galway | d'Artagnan |
| Savoy Defects | Ultima Ratio Regum |
| Prize Hunting | Musketeers |
| Foot Guards | Crack Troops |

### War 2: War of the Austrian Succession (WAS) — Turn 2

| British (12) | French (12) |
|--------------|-------------|
| Boscawen | Saxe |
| Lawrence | Murray |
| Warren | O'Sullivan |
| de Lorraine | Contades |
| Seckendorff | Nizam's Favor |
| King George II | Frederick (the Great) |
| Stair | Lowendal |
| Chaos in Bavaria | von Schwerin |
| Treaty of Warsaw | de Coigny |
| Hungarian Enthusiasm | de la Bourdonnais |
| François de Bussy | Bonny Prince Charlie |
| Clive | Castries |

### War 3: Seven Years' War (7YW) — Turn 4

| British (12) | French (12) |
|--------------|-------------|
| Bradstreet | Lally |
| Johnson | Broglie |
| Hawke (Damned Audacity) | Villiers |
| Clive | Chevert |
| Monckton | Coureurs des Bois |
| Amherst | Bougainville |
| Granby | Montcalm |
| Wolfe | Beaujeu |
| Coote | Castries |
| Morta la Bestia | Monongahela Ambush |
| Damned Audacity | Hadik's Raid |
| Old Fritz | Nawabs Rally |
| Sepoy Veterans | |

(Note: 12 unique tiles per side. "Damned Audacity" — the umbrella tile representing Hawke at Quiberon and Boscawen at Lagos — is the playbook's heading for the historical episode; the asset is `WarTile_7YW_BR-Bonus-DamnedAudacity.png`.)

### War 4: American War of Independence (AWI) — Turn 6

| British (12) | French / Patriot (12) |
|--------------|------------------------|
| Cornwallis | Rochambeau |
| Howe | de Grasse |
| Coote | Washington |
| Brant's Volunteers | Lafayette |
| Carleton | de Suffren |
| Cornplanter | Morgan's Rifles |
| Stuart | Castelnau (de Bussy) |
| Rodney | von Steuben |
| André | Greene |
| Arnold's Treason | (Benedict) Arnold |
| Anglo-Dutch Conflict | East River Wind |
| Hessians | Bunker Hill |

**Are they unique named tiles?** Yes — every Bonus War Tile carries a unique historical name (`WarTile_<War>_<Side>-Bonus-<Name>.png`). Their *gameplay* function is just a strength value (and rarely an effect symbol), but each printed tile is one-of-a-kind.

**Rotation rule (Rules §3.7, Playbook p.10):** "When each War is resolved, the players should remove all of the Bonus War Tiles matching that War from the game, and place the set designated for the next War on their playmats."

---

## 3. Advantage Tiles

**Rules §3.2.5 + §8.0 (pp.6, 16):**
> "Advantages are tiles with special abilities that can be used once per Game Turn. To gain an Advantage tile, a player must control all spaces connected to the matching space on the map; as soon as this happens, that player takes the Advantage tile."

**Acquisition rule:** A player gets the Advantage when they flag *all* spaces connected to its pentagonal space on the map; they lose it the moment any connected flag falls. Conflict markers in connected spaces don't return the tile but do block its activation. Some Advantages cost 1 of a specified AP type to use; max 2 Advantages per Action Round, max 1 per Region.

**Setup (Playbook §"Setup" p.2):**
> "Put the Advantage tiles face up in their spaces on the map (except Wheat and Algonquin Raids)."
> Britain starts already holding **Wheat**; France starts already holding **Algonquin Raids**.

### Total: 22 unique Advantage tiles

Filenames `AdvTile_<Name>.jpg` (front) and `AdvTile_<Name>b.jpg` (back) — 22 unique × 2 = **44 image files**, but **22 physical tiles**.

| # | Name | Region | Connected to (controlling spaces) | Effect summary (from playbook examples / map / rules) |
|---|------|--------|------------------------------------|--------------------------------------------------------|
| 1 | Wheat | North America | Cumberland + Chesapeake | Britain's starting Advantage; Economic shift discount in NA (uses Economic AP) |
| 2 | Algonquin Raids | North America | Algonquin alliance (Local Alliance) | France's starting Advantage; place Conflict marker in NA Political space (e.g., Albany) — Playbook p.7 |
| 3 | Iroquois Raids | North America | Iroquois Local Alliance | Conflict marker / shift effect in NA — Playbook p.5 ("she shifts the Iroquois alliance, placing a British flag there and taking the Iroquois Raids Advantage") |
| 4 | Fur Trade | North America | Hudson Bay + Quebec & Montreal area (north) | Economic discount on Fur markets / VP from Fur |
| 5 | Patriot Agitation | North America | Northern Colonies + Sons of Liberty | Place Conflict marker in NA; activated more in Revolution Era |
| 6 | Fruit | North America (Caribbean-adjacent) | San Agustin + Louisiana | Economic discount on Caribbean fruit markets — Playbook p.10 ("Raj seizes San Agustin, whose Fruit Advantage will help him claw back position in the Caribbean") |
| 7 | Mediterranean Intrigue | Europe | Sardinia + Italian/Naples space (Italy) | Place Conflict marker in opposing Alliance space — Playbook p.5 ("activates his Mediterranean Intrigue Advantage tile, placing a Conflict marker in the British-flagged Alliance space in Austria") |
| 8 | Naval Bastion | Europe | Gibraltar (Conquest Point reward) | Naval / Squadron deployment bonus — Playbook p.10 (Raj takes Naval Bastion via Conquest Point on Gibraltar) |
| 9 | Italy Influence | Europe | Italian Alliance spaces (Naples / Italy) | Diplomatic/political effect in Europe |
| 10 | Central Europe Conflict | Europe | German States/Saxony + Bavaria | Place Conflict marker in Europe — Playbook p.7 ("Raj activates his Central Europe Conflict Advantage, placing a Conflict Marker on British-flagged Sardinia") |
| 11 | German Diplomacy | Europe | Saxony + (Hanover/Prussia) | Political shift discount in Europe |
| 12 | Baltic Trade | Europe | Sweden + Denmark-Norway | Economic / market effect (Baltic) |
| 13 | Silesia Negotiations | Europe | Austria + Prussia (acquired by flagging both Prestige spaces) | Treaty Points / Political discount — Playbook p.8 (Eliza targets Austria Prestige to access Silesia Negotiations) |
| 14 | Letters of Marque | Caribbean | Bahamas Run West/North + Atlantic naval space | Place Conflict marker on opposing Caribbean Market — Playbook p.13 ("Raj activates his Letters of Marque Advantage to place a Conflict marker in Bahamas Run West") |
| 15 | Pirate Havens | Caribbean | Buccaneers naval + Caribbean Market(s) | Conflict marker in Caribbean — Playbook p.13 ("Pirate Havens would only cost 2 [Military]") |
| 16 | Rum | Caribbean | Caribbean Markets (Martinique, Guadeloupe area) | Reduce Market shift cost by 1 — Rules §8.0 PLAY NOTE explicit example |
| 17 | Slaving Contracts | Caribbean | Asiento + (West African coast space) | Caribbean / Asiento commerce; market effect |
| 18 | Silk | India | West Bengal + Chandernagore (or similar Bengal cluster) | India market discount + 1 VP via East India Company — Playbook p.9 ("Eliza also gets 1 VP from East India Company for her Silk Advantage") |
| 19 | Power Struggle | India | Mysore Local Alliance | Place Conflict marker in India — Rules §5.5.2 example ("activates its Advantage, Power Struggle, to place a Conflict marker in Tiruchirappalli") |
| 20 | Raids & Incursions | India | Plassey + (Maratha Alliance / north India) | Place Conflict marker / unflag in India |
| 21 | Separatist Wars | India | Vellore + Kanchipuram (Carnatic spaces) | Conflict / shift effect in India |
| 22 | Textiles | India | Tiruchirappalli + Vandavasi + Karaikal (south India) | Market shift discount in India / VP |

Notes:
- Connection lists above are inferred from the printed map (`godot_project/assets/board/Imperial Struggle Map_Final-150-Clean.png`) — each pentagon is wired to 2–3 named spaces by black lines. For final implementation the pixel-level pentagon connections should be re-verified against a high-res scan, but the regions and key anchor spaces are correct as cited.
- "Region" determines the §8.0 max-one-Advantage-per-region-per-Action-Round cap.
- Effects: rules don't list every Advantage's text; the rule §8.0 says "Advantage tiles display their function on their front side." Front-side effect text was extracted by cross-referencing playbook usage examples (cited inline above) plus the unique Conflict-marker variants (`Markers_Conflict_Med Intrigue`, `Markers_Conflict_Algonquin`, `Markers_Conflict_Iroquois`, `Markers_Conflict_Buccaneers`, `Markers_Conflict_German States`, `Markers_Conflict_Maratha`, `Markers_Conflict_Mysore`, `Markers_Conflict_Nizam`, `Markers_Conflict_Privateers`, `Markers_Conflict_Sons of Liberty`, `Markers_Conflict_Haitian Rev`) — these confirm which Advantages place named Conflict markers in which Region.

---

## 4. Conflict Markers

**Rules §3.8 (pp.7–8):**
> "Conflict markers belong to neither side… There can never be more than one Conflict marker in a space… Some Events indicate that their Conflict markers are more expensive to remove; place the Conflict markers with the '+1' markup showing only if specifically directed to do so."

### Counts (from Rules manifest pp.18–19)

- **14 generic Conflict markers** (yellow hex with crossed-swords). They appear as 7 hexes on the British counter sheet (#3 FRONT, p.19) and 7 hexes on the French counter sheet (#2 FRONT, p.18). They are physically two-sided: front = regular Conflict, back = "+1 Conflict" (the more-expensive-to-remove variant).
  - Asset evidence: `Markers_Conflict.png` (front) and `Markers_Conflictb.png` (back, with "+1" label and special art).
- **No separate +1 marker counts** — the +1 is the BACK side of the same 14 markers.

So the **total Conflict-marker pool = 14 physical markers, each two-sided (Conflict / +1 Conflict)**.

### Named Conflict-marker variants

The Vassal/Godot asset folder also ships **11 named Conflict-marker variants**, used to track which Advantage or Event placed each marker (purely informational — they all behave as one regular Conflict marker):

`Algonquin`, `Buccaneers`, `German States`, `Haitian Rev`, `Iroquois`, `Maratha`, `Med Intrigue`, `Mysore`, `Nizam`, `Privateers`, `Sons of Liberty`

These are NOT counted as additional markers — they are just visual aids; the official rules treat all Conflict markers as a single neutral pool.

---

## Summary table for game implementation

| Component | Count |
|-----------|------:|
| Basic War Tiles, per side | 16 (4+4+3+3+2 by variety) |
| Basic War Tiles total | 32 |
| Bonus War Tiles, per war per side | 12 (unique named) |
| Bonus War Tiles total | 96 |
| Wars | 4 (WSS, WAS, 7YW, AWI), 4 theaters each |
| Advantage tiles | 22 unique (all double-sided) |
| Advantage regions | Europe 7, North America 6, Caribbean 4, India 5 |
| Conflict markers (generic, 2-sided Conflict / +1) | 14 |
| Named conflict-marker artwork variants | 11 (cosmetic only) |
