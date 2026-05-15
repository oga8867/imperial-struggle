# Imperial Struggle — Rule-by-Rule Code Audit

Source rulebook: `ImpStr_2nd_Printing_Rules_Final.pdf`
Source playbook: `vassal_extracted/ImpStr_Living_Playbook_7-26-20.pdf`
Code root: `X:/Imperial Struggle/godot_project/scripts/`

Verdict legend: **OK** / **MISSING** / **WRONG**. OK items omitted unless ambiguity warrants a note.

---

## 1. §2.5 Automatic Victory — three conditions

Rule quote (rulebook p.2/p.3):
1. "During the Victory Check Phase of any turn, France wins if VP ≥ 30, Britain if VP ≤ 0."
2. "After any war's last theater is resolved, if the same player won all of that war's theaters by the maximum indicated strength margin, that player immediately wins."
3. "At the end of the Scoring Phase of any Peace Turn, if the same player won all four regional awards and all three Global Demand awards, that player immediately wins."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 1.1 | **WRONG** | `GameState.check_auto_victory` (`game_state.gd:81`) | Only checks VP ≥ 30 / ≤ 0. The "all four awards + all three GD" sweep condition is **not implemented**. Britain sweeping a Peace Turn never ends the game. |
| 1.2 | **MISSING** | `WarManager.resolve_full_war` (`war_manager.gd:422`) and `GameManager.resolve_war_and_continue` (`game_manager.gd:500`) | After-war "max-margin in every theater" check is missing. `GameManager.resolve_war_and_continue` only calls `state.check_auto_victory()` (VP-only). Need to track per-theater max-margin spoils row and verify same player won every theater at that row. |
| 1.3 | (covered by 1.1) | `_score_regional_awards` / `_score_global_demand` | Need a tally that's checked at end of Scoring Phase before Victory Check (see §4.1.12). |

**Fix:** in `_victory_check_phase`, before VP check, examine results of the just-completed Scoring Phase: if `award_winner[region] == X` for all 4 regions AND `gd_winner[c] == X` for all 3 commodities, end game with X. In `WarManager.resolve_full_war`, capture each theater's spoils row index and the max-margin row index from `theater.spoils_table`; if every winner matches and every winner hit max margin, emit auto-victory.

---

## 2. §4.1.5 Reset Phase — what gets reset?

Rule quote (p.9): "Remove all Exhausted markers from Advantage tiles and Ministry cards. Move all Investment tiles, including any that no one took, from the Available Investment Tiles display to the Used Investment Tiles box."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 2.1 | **WRONG** | `_reset_phase` (`game_manager.gd:252`) | Calls `reset_for_new_turn()`, `MinistryEffects.reset_exhaustion_for_turn()`, `AdvantageManager.reset_exhaustion()` — but does NOT explicitly move the unused investment tiles to a "used" box. They are simply re-shuffled in `_deal_cards_phase` because `state.available_investment_tiles.clear()` discards them before reshuffling the full pool. Functionally close, but **leftover Investment tiles are not preserved as "used"** — the entire `investment_tile_pool` is reshuffled every turn, which violates the rule (used tiles must cycle through "Used Investment Tiles box" first). |
| 2.2 | **MISSING** | `_reset_phase` | Per playbook step list: should also reset per-AR advantage usage counters here. AdvantageManager has `reset_round()` but it's never called (see §8). At minimum the code is fine here since the rule is per-turn, but `gained_this_round` flag also needs clearing on Reset (it never gets set right now anyway, see §8). |

**Fix:** track `used_investment_tiles` as a separate array; only reshuffle `investment_tile_pool` when the available stack runs out. Reset Phase moves the remaining `available_investment_tiles` into `used_investment_tiles`.

---

## 3. §4.1.10 Reduce Treaty Points — cap of 4

Rule quote (p.9 §4.1.10): "Each player now loses all Treaty Points that each has in excess of four."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 3.1 | **OK** | `_reduce_treaty_points_phase` (`game_manager.gd:370`) → `PlayerState.reduce_excess_treaty_points` (`player_state.gd:62`) | Excess is correctly trimmed: `excess = max(0, treaty_points - 4)`. |

---

## 4. §4.1.12 Scoring Phase — three sub-phases

Rule quote (p.9): "REGIONAL SCORING ... PRESTIGE SCORING ... GLOBAL DEMAND SCORING ... in the order they appear on the Global Demand Table (starting at the top)."

Conflict-marker rule (§3.8): "Spaces containing Conflict markers cannot be used for ... Award, Prestige, or Global Demand eligibility."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 4.1 | **OK** | `_score_regional_awards`, `_score_prestige`, `_score_global_demand` (`game_manager.gd:395-427`) | All three sub-phases run in order. |
| 4.2 | **OK** | `_count_flags_in_region` (line 521) and `_count_commodity_markets` (line 531) | Both filter `if not ss.has_conflict_marker`. |
| 4.3 | **WRONG** | `_score_prestige` (line 403) | Excludes Conflict-marker spaces (good) and restricts to `region == EUROPE` (good per rule). **MISSING:** Turn 6 special case — "After the AWI, if there is at least one USA flag on the map, then the USA spaces count for this calculation even though they are not physically in the Europe Region." (§4.1.12 PRESTIGE). USA flags / USA Political spaces are never counted here. |
| 4.4 | **WRONG** | `_score_global_demand` (line 420) | Iterates `state.current_global_demand` directly — the rule mandates the order matches the Global Demand Table top-to-bottom. The order is preserved by insertion, but the Global Demand Table also pays *different* rewards per location (Debt, TRP, etc.). Code only awards 1 VP regardless of position; the table-position-specific rewards (Debt change, TRP gain, etc.) are not modeled. |
| 4.5 | **MISSING** | `_score_regional_awards` | Award tile may grant TRP — `AwardManager.score_region` does handle TRP (`award_manager.gd:57`). OK — but the "set Award tile aside until next reshuffle" on tie (rule p.9-10) is not implemented; ties just emit no winner and the tile remains in the assignment until era reshuffle. |

**Fix:** Add `_score_global_demand` reward variants from a Global Demand Table data file. In `_score_prestige`, after AWI when any space has `has_usa_flag`, iterate USA spaces and count toward FR side (USA Flags count as friendly to French per §10.0). Auto-victory sweep (§2.5 condition 3) should be checked here.

---

## 5. §5.2 Event Play — five sub-rules

Rule quotes (pp.10-11):
1. "First, check the Bonus Condition. If satisfied, ... bonus effect ... Otherwise only standard."
2. "Must take standard before bonus, fully resolve all effects."
3. "AP from Event ... own separate Major Action OR combined with matching Major Action ... can be added to a Minor Action but become subject to Minor restrictions."
4. "AP subject to all the same restrictions (e.g., connection requirements). Effects without AP do not need to obey connection."
5. "After play, remove from game."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 5.1 | **WRONG** | `ActionController.play_event` (line 62) | Event removal: card is `event_discard_pile.append(card)`. Rule 5.2.5: "remove from the game" — Imperial Struggle never recycles played Events. The discard-pile path is then re-shuffled into the draw pile in `_deal_cards_phase` (line 274). Played Events therefore reappear later. **This is a fundamental rule violation.** |
| 5.2 | **WRONG** | `EventEffects.apply_event` (line 14) | Bonus condition is taken purely from caller (`use_bonus`). No automatic verification that the Bonus Condition is actually met (5.2.1: "the Bonus Condition must be satisfied at the moment the Event is first played" — design note explicitly forbids using the standard effect to satisfy the condition). The UI lets the player toggle "use bonus" freely. |
| 5.3 | **WRONG** | `ActionController.play_event` / `_grant_event_ap` | AP from event is granted to a single bucket (`event_ap_remaining/event_ap_type`). The rule allows player to choose to attach event AP to Major OR Minor (rule §5.2.3). Code automatically merges with Major-action pool (`ap_for_current` line 117 only adds event AP when in Major, never Minor). Player can never legally attach event AP to a Minor Action. |
| 5.4 | **OK (partial)** | `attempt_shift` uses `can_shift_space` which enforces connection — applies regardless of AP source. |
| 5.5 | **WRONG** | (event removal — same as 5.1) | "Remove from game" must literally remove, not discard. Need a `removed_from_game` array (or just drop). |

**Fix:** drop played event cards entirely (`event_discard_pile` reserved only for hand-discards 4.1.6.b). For 5.2.2 add an `EventCard.is_bonus_condition_met(side, state)` predicate per card. For 5.2.3 store event AP separately and let the player attach it to either Major or Minor pool when spending.

---

## 6. §5.3.2 Minor Action — restrictions

Rule quote (p.11): "AP from a Minor Action for only one expenditure (to shift a single space, purchase a single Bonus War tile, remove a single Conflict marker, etc.). Minor Actions may not be used to remove opposing flags or Squadrons, unless the space has a Conflict marker."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 6.1 | **OK** | `can_shift_space` (line 198-202) | Single-expense flag (`minor_action_used_first_expense`) checked, opp-flag block w/ conflict-marker exception present. |
| 6.2 | **WRONG** | `can_shift_space` | Squadron displacement (Naval space with opposing Squadron) is not blocked under Minor. Naval spaces can never have Conflict markers (`SpaceState.place_conflict_marker` returns false for Naval) — so the rule says Squadrons on the map are entirely safe vs Minor Military Actions. Currently the Naval-shift via Minor is allowed because the space "has no conflict marker but isn't your-flagged" — check `if space_state.controlled_by == _opponent_of(...)` blocks unflag. **However:** there is no separate squadron-deploy action wired up at all — see §13. |
| 6.3 | **WRONG** | `can_shift_space` | Removing a Conflict marker via Minor should be a *legal expense* (rule explicitly says "remove a single Conflict marker"). The code has NO conflict-marker-removal action path (see §12). |
| 6.4 | **WRONG** | `can_shift_space` | "Bonus War Tile purchase" via Minor — limit is one purchase per Minor Action. Currently `war_tile_purchase.gd:88` only checks `state == SPENDING_MAJOR` so Bonus tile purchases via Minor are silently blocked even though the rule allows ONE such purchase per Minor. |

**Fix:** Allow `_can_afford` to include `SPENDING_MINOR` for war-tile purchase; ensure single-expenditure flag is set after one purchase.

---

## 7. §5.3.4 Region-switching cost

Rule quote (p.11-12): "If a player chooses to make purchases in more than one Region (not sub-Region) with [Economic] or [Diplomatic] in a single Action Round, 1 additional Action Point of the appropriate type must be paid for each Region beyond the first."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 7.1 | **WRONG** | `calculate_shift_cost` (line 162) | Region-switch cost is applied **regardless of action type**. Rule explicitly limits this surcharge to Economic and Diplomatic. The example in §5.6.6 (Jane spending Military APs across regions) explicitly states "she does not pay an extra MP for switching Regions". Military Action Points should NEVER pay the +1 region-switch surcharge. |
| 7.2 | **OK** | regions tracked separately for Major vs Minor (`regions_used_major` vs `regions_used_minor`). Rule is "in a single Action Round" — a major+minor mix could be argued to share the counter, but the rule wording "with E/D AP in a single Action Round" is generally read as per-action-type. Acceptable. |

**Fix:** in `calculate_shift_cost`, gate the region-switch +1 with `if action_type in [ECONOMIC, DIPLOMATIC]`.

---

## 8. §5.4.1 Market Connection / Isolation

Rule quote (p.12): "In order to shift a Market, that Market must be connected to a Territory, Fort, or Naval space the player controls, or be connected to another Market the player controls that does not contain a Conflict marker, **is not Isolated, and did not change control during the current Action Round**."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 8.1 | **WRONG** | `_market_has_connection` (line 322) | Allows shift via friendly Market connection only checking `not has_conflict_marker`. **MISSING checks:** (a) the connecting Market is not Isolated; (b) the connecting Market did not change control this Action Round. The "no daisy-chain in same AR" rule is entirely absent. |
| 8.2 | **MISSING** | (no isolation tracking) | `SpaceState.is_isolated` doesn't exist. Isolation is computed nowhere. Per rule, isolation is evaluated at the *start* of any Action Round (so it must be cached at AR start). |
| 8.3 | **WRONG** | `_market_has_connection` line 333-334 | Fallback "if connections empty allow shift" makes Market shifting permissive when topology data is missing, masking bugs. |
| 8.4 | **OK** | Damaged Forts: `space_state.is_protected` rejects damaged Forts as protectors but the connection check only looks for `space_type == FORT` regardless of damage. Rule says damaged Forts still prevent isolation (control still applies for connection purposes). Treating damaged Fort as a valid endpoint is correct here. |

**Fix:** add `_compute_isolated_markets()` called at start of every Action Round; a Market is Isolated if it has a friendly flag but no chain through (non-conflict, non-changed-this-AR) friendly Markets to a friendly-controlled Territory/Fort/Naval. Track `markets_changed_this_ar` set and clear at AR start. Use these in `_market_has_connection`.

---

## 9. §5.4.2 Market shift cost

Rule quote (p.12): "Shifting a Market costs equal to the Market's Economic Cost. Isolated → 1; Conflict marker → 1. Protected → +1. Apply cost reductions, including those from Advantages, before cost increases. Cost can never be less than 1."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 9.1 | **WRONG** | `space_state.get_effective_cost` (line 79) | Sets cost = 1 only when Conflict marker present. Does NOT also set cost = 1 when the Market is Isolated. (See §8 — isolation isn't tracked at all.) |
| 9.2 | **OK** | `calculate_shift_cost` adds +1 for Protected, +1 for region switch, +1 for marked-conflict marker, then `maxi(1, cost)`. Order is conflict-cost-first, then increases — fine. |
| 9.3 | **MISSING** | `calculate_shift_cost` | Advantage-based cost reductions (e.g. Rum, Wheat, Tobacco) are not applied. Rule §8.0 "Some Advantages allow the player to pay fewer AP for a purchase" → no hook in `calculate_shift_cost` to query an active Advantage's reduction. |

**Fix:** `get_effective_cost` should consider isolation. Add `AdvantageManager.get_cost_reduction(side, space) -> int` and subtract before applying increases (Protected, region, conflict-extra).

---

## 10. §5.5.2 Political shift cost

Rule quote (p.12): "Shifting a Political space costs equal to its Political Cost. If Conflict marker → 1. No connection req. Cost reductions before increases. Min 1."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 10.1 | **OK** | `calculate_shift_cost` reuses `get_effective_cost` (conflict→1) and skips the Market connection check; Political space has no Protection (only Markets are Protected). |
| 10.2 | **WRONG** | `is_protected` (`space_state.gd:86`) | Doesn't restrict by space type — applies to any controlled space whose connection has a friendly Fort/Naval. **In practice this means Political spaces could be considered Protected**, adding +1 to political shift cost incorrectly. Per rule, only Markets can be Protected. |

**Fix:** add `if data.space_type != MARKET: return false` at top of `is_protected`.

---

## 11. §5.6.1 Bonus War Tile purchase

Rule quote (p.13): "The cost to buy a Bonus War Tile is 2 [MP]. A maximum of two Bonus War tiles may be bought per Action Round. ... Each Theater has a limit of two Bonus War Tiles per player."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 11.1 | **OK** | per-theater limit 2: `purchase_bonus_war_tile` line 62 (`>= 2`). |
| 11.2 | **WRONG** | `WarManager.purchase_bonus_war_tile` / `war_tile_purchase.gd:_on_buy` | "Max 2 per Action Round" is **not enforced**. There is no AR-level counter on bonus tile purchases. A player could buy 3+ in one AR (with enough MP). |
| 11.3 | **WRONG** | rule mid-paragraph: "If a player draws a Bonus War Tile and wishes to place it in a theater that already has two Bonus War Tiles, one of the incumbent tiles must be moved to a different theater." | `purchase_bonus_war_tile` rejects with `return false` when drawing into a full theater. The relocation/displacement option is not implemented (it's also a corner case mostly visible at edge of game). |
| 11.4 | **OK** | cost 2 MP enforced in UI `_on_buy` via `ActionController.spend_ap(2)`. |

**Fix:** add `bonus_tile_purchases_this_ar` counter incremented on success, reset in `ActionController.begin_action_round`.

---

## 12. §5.6.2 Conflict Marker removal

Rule quote (p.13): "The cost to remove a standard Conflict marker is 2 [MP], or 1 [MP] if the Conflict marker is in a protected space. This cost is increased by 1 if the Conflict marker so indicates."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 12.1 | **MISSING** | `ActionController` has no method like `remove_conflict_marker_at(space_id)`. There is `SpaceState.remove_conflict_marker()` but it's only called by `flag/unflag/take_control`. **The player cannot spend MP to remove a Conflict marker as a deliberate action.** |
| 12.2 | (consequence) | This means the rule example "Jane spends 2 MP to clear out two pesky Conflict markers" is unsupported by the code. |

**Fix:** add `ActionController.remove_conflict_marker(space_id)` requiring SPENDING_MAJOR or SPENDING_MINOR with Military current type, cost = 1 if `is_protected_for_owner(space)` else 2, +1 if `conflict_marker_extra_cost`. Then call `space.remove_conflict_marker()`. Treat as one expense for Minor (the single-expenditure rule).

---

## 13. §5.6.3 – §5.6.6 Forts / Squadrons

Rule quotes (pp.13-14):
- 5.6.3 Build Fort: cost = printed Fort space value; must control connected Market/Naval/Territory at start of AR.
- 5.6.4 Repair friendly Fort: Fort# - 1; Repair opposing damaged Fort: Fort# + 1, must control connected Squadron or Market.
- 5.6.5 Construct Squadron: 4 MP, goes to Navy Box; cap 8 squadrons total.
- 5.6.6 Deploy Squadron: empty Naval = 1 MP; opposing Squadron present: 3 MP if from Navy Box, 2 MP if from map. Squadron deploys at most once per AR.

| # | Verdict | Where | Issue |
|---|---|---|---|
| 13.1 | **OK (partial)** | `_fort_build_has_connection` (line 230) checks Market/Naval/Territory connection. Cost = `space.data.base_cost` via `get_effective_cost` ✓. |
| 13.2 | **WRONG** | `_fort_build_has_connection` | Rule says control must be in place "at the start of the Action Round". Code only checks current state — a player who flags a connection earlier in the same AR could still build (allowed in code, disallowed by rule). |
| 13.3 | **MISSING** | (Repair friendly Fort) | There is no path to spend MP on a friendly damaged Fort. `can_shift_space` for FORT only handles `controlled_by == NONE` (build) or `controlled_by == opponent` (capture damaged). When the Fort is friendly + damaged, `allowed = true` but the actual effect would be "shift" (a no-op since `shift` only flags empty / unflags opposing). **Friendly Fort repair is silently impossible**, and even if attempted will fail to remove the damage marker. Cost calc also wrong (rule = #-1, code uses raw #). |
| 13.4 | **WRONG** | `attempt_shift` for opposing damaged Fort | `space.shift(current_side)` calls `unflag` (sets to NONE), but rule §5.6.4: "the player who repaired the Fort takes control" (i.e., flag flips to repairer). Currently the Fort just becomes empty + still damaged. **Damage marker is never cleared** either. |
| 13.5 | **MISSING** | (Construct Squadron) | No action path to spend 4 MP to add to `squadrons_in_navy_box`. The rule "Except for the ones in the opening setup, Squadrons must be constructed before they can be deployed" is unsupported. `navy_panel.gd` only displays counts. |
| 13.6 | **MISSING** | (Deploy Squadron) | No path to deploy a squadron from Navy Box / map to a Naval space at 1/2/3 MP. `can_shift_space` allows MILITARY on Naval but `attempt_shift` calls `space.shift` which only flips a flag — squadron tokens & navy box counters are not touched. Deploy cost (1 vs 2 vs 3) never computed. |
| 13.7 | **MISSING** | "Squadron deploys at most once per AR" — no per-squadron tracking exists. |

**Fix:** create `ActionController.attempt_construct_squadron(side)` (4 MP, cap 8). Replace Naval handling in `attempt_shift` with `attempt_deploy_squadron(target_naval, source: "navy_box"|space_id)` computing 1/2/3 MP, decrementing source counter, returning displaced squadron to Navy Box. For Forts: `attempt_repair_fort(space_id)` for friendly (cost=#-1, require damaged) and capture (cost=#+1, require damaged + connected Sq/Market) that flips control AND clears `is_fort_damaged`.

---

## 14. §7.1 War Resolution order

Rule quote (pp.14-15):
1. "First, each player reveals War tiles ... adds the strength point values. This total is each player's Army Strength."
2. "Second, each player applies any other effects from their War tiles, **starting with the player closer to an automatic victory** (if VP is at 15, then the player who went first in the preceding Peace Turn resolves these effects first as well)."
3. "Third, each player consults the Bonus Strength list ... adds one for each flagged element. ... Adding the Army Strength and Bonus Strength together will yield each player's total Theater Strength."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 14.1 | **WRONG** | `WarManager.resolve_theater` (line 274) | Calls `calculate_theater_strength` (Army + Bonus) FIRST, then `_apply_tile_effects`. **Order is reversed**: tile effects (Debt/Damage/Unflag) are supposed to apply between Army and Bonus, and they affect Bonus Strength (e.g., Unflag of Conflict-marker space removes that strength contribution; Damage Fort removes Fort's bonus strength contribution). Current code computes Bonus Strength on pre-effect board, then applies effects, so Bonus values don't reflect tile effects. |
| 14.2 | **WRONG** | `_apply_tile_effects` (line 293) | Iterates `[BRITAIN, FRANCE]` blindly. Rule: "starting with the player closer to an automatic victory". For VP > 15, France is closer to 30 → France first; for VP < 15, Britain is closer to 0 → Britain first; tie → preceding-first-player goes first. Code: always Britain first. |
| 14.3 | **WRONG** | `_apply_single_tile_effect` UNFLAG (line 319) | Picks first opponent-controlled Market without conflict marker. Rule §7.1.2: tile owner may unflag a Market OR Political space; must be in the theater's Region; must NOT cause other Markets to become Isolated (if avoidable); for Political must be in theater's Region. Current code: ignores Political spaces entirely, ignores Region constraint, ignores Isolation constraint. |
| 14.4 | **WRONG** | `_apply_single_tile_effect` DAMAGE_FORT_OR_REMOVE_SQUADRON | Iterates ALL spaces (any region) for the first opponent fort. Per rule, the effect targets the THEATER (and theater Region for forts/squadrons). Current code can damage a Fort in India when the war tile is in a North America theater. |
| 14.5 | **OK** | DEBT effect: opponent takes 1 Debt — matches rule. |

**Fix:** in `resolve_theater`, compute Army-only strength → apply tile effects (in correct player order based on VP vs 15) → THEN compute Bonus Strength → THEN sum and decide winner.

---

## 15. §7.1.2 Tile effects detail

Already covered under §14. The crossed-flag (UNFLAG) sub-rules:
- §7.1.2.i: Market choice "must choose one that does not cause other Markets to become Isolated, if possible."
- §7.1.2.ii: Political choice "must choose one located in the theater's Region."

**Verdict: WRONG** (see 14.3, 14.4). UNFLAG as currently coded ignores Region constraint, ignores Isolation-avoidance constraint, and never targets Political spaces.

---

## 16. §7.1.3 Bonus Strength

Rule quote (p.14-15):
- Each Alliance space (matching country on Bonus Strength list) → +1 to its controller.
- Each Ministry keyword on the list → +1 (if the player has it revealed).
- Each Conflict marker in a flagged space (when listed) → +1 to **the opponent of the flagged space** (i.e., the player whose flag is NOT there).
- Squadrons: +1 each (region-listed; multi-region theaters sum across listed regions).
- Each undamaged Fort → +1 to its controller.

| # | Verdict | Where | Issue |
|---|---|---|---|
| 16.1 | **WRONG** | `_calculate_bonus_strength` "alliance_europe" (line 235) | Only handles Europe-region Alliance spaces. Rule: each country on the Bonus Strength list contributes for its Alliance spaces (which can include Local Alliances). The bonus_strength_keys system is too coarse — there's no per-country Alliance-counting (e.g., "Alliance: Bavaria" should grant +1 only to whoever controls Bavaria's Alliance space). |
| 16.2 | **WRONG** | `_calculate_bonus_strength` conflict_marker (line 257-259) | Code: bonus to `side` if `controlled_by == opponent and region == theater.region`. Rule says: a Conflict marker in a flagged space grants strength to the **opposite** of the flag-owner. So if a French-flagged space has a Conflict marker, BRITAIN gets +1. Code is **almost right**: when computing British bonus, looks for `controlled_by == FRANCE` — that's correct directionally. But Conflict markers on opposing-flagged Markets only apply when the bonus_strength list says "ConflictMarker" applies to the relevant region; the code only checks `region == theater.region` which may be too narrow (theaters often list multiple regions for conflict markers, e.g., "Conflict markers in Europe and Caribbean"). |
| 16.3 | **WRONG** | (Alliance dot-matching) | Rule §3.2.1: each Alliance space has a dot count indicating which Wars it contributes in. Code does not check `data.alliance_war_dots` (or equivalent) against current war. So an "Alliance" space with one dot (WSS only) can wrongly grant strength in the AWI, etc. |
| 16.4 | **OK** | Forts: undamaged-only check ✓; Squadrons by region ✓. |
| 16.5 | **WRONG** | Conflict markers in flagged spaces — code requires `data.region == theater.region` strictly; per playbook, the Bonus Strength list can specify multi-region conflict-marker contributions (e.g., a theater list "Conflict markers in Europe & Caribbean"). Need to consult `theater.bonus_strength_keys` for an explicit `conflict_marker_<region>` key with optional region arg. |

**Fix:** drive bonus strength entirely from data: each war/theater specifies a list of typed contributions (`{type: "alliance", country: "spain"}`, `{type: "fort", region: "north_america"}`, etc.). Match per-space against the list and sum.

---

## 17. §7.2.1 Conquest Points

Rule quote (p.15): "Only Forts, Markets, Naval spaces, and Territories can be taken with CP (for 1 CP apiece, unless modified). To take a Fort, Market, or Naval space with CP, it must be physically in the theater. To take a Territory with CP, it must be located in the Region listed for the current Theater on the War Display, OR listed on the War Display in the current Theater's 'Additional Territories' box."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 17.1 | **WRONG** | `_auto_spend_cp` (line 438) | Only spends CP on **Territories**. Forts, Markets, Naval spaces are valid CP targets and are entirely skipped. |
| 17.2 | **WRONG** | `_auto_spend_cp` | Picks any opponent Territory anywhere on the board, regardless of theater Region or Additional Territories list. Rule strictly limits Territory targets per theater. |
| 17.3 | **WRONG** | Naval-space capture: rule requires the player "must also have a Squadron in the Navy Box or elsewhere in the Theater, and place it in the desired Naval space." Code path doesn't exist. |
| 17.4 | **OK** | Conquest Line check `_has_conquest_line_to` does verify a connected friendly Fort/Naval/Territory. But it accepts ANY connected friendly space, not strictly Fort/Naval/Territory — checking `controlled_by == side` only. (A Market connected by a Conquest Line shouldn't qualify; rule §7.2.1.2 says "control at least one Fort, Naval space, or other Territory connected with a Conquest Line".) |
| 17.5 | **MISSING** | "auto_spend" logic should be replaced with player-prompted choice; CP must be spent immediately before resolving the next theater. |

**Fix:** replace `_auto_spend_cp` with a per-theater CP spending pass that runs immediately after `_apply_spoils`, before `theater_resolved.emit`. Filter eligible targets by theater Region + Additional Territories. Honor target type constraints (Fort/Market/Naval must be physically in the theater). For Conquest Line check, require connected space be Fort/Naval/Territory (not Market).

---

## 18. §7.2.2 Territory Refusal

Rule quote (p.16): "Twice per War, each player may refuse to cede a Territory ... costs 3 VP the first time it is used in a War, and 5 VP the second time."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 18.1 | **MISSING** | `WarManager` has `territory_refusals` dict (line 21) and resets it in `setup_war` (line 183), but **nothing reads or writes it**. There is no `refuse_territory(side, territory_id)` method, no UI prompt, and `_auto_spend_cp` simply takes Territories without offering a refusal. |
| 18.2 | **MISSING** | "USA Flags ... a player may not concede VP to refuse placement of a USA Flag" (§7.3) — also unimplemented. |

**Fix:** during CP spending, if a Territory is targeted, raise a prompt to the defender; if accepted, charge 3 VP (first) or 5 VP (second) and revert the take, mark Territory off-limits to CP this War. Block USA Flags from refusal.

---

## 19. §7.5 War Reset

Rule quote (p.16): "The players remove all of their War tiles in play and return them to their player mats, separated by type and randomized. Players also remove all Conflict markers that granted strength in the just-resolved War from the map."

PLAY NOTE: "Skip this phase at the end of the American War of Independence."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 19.1 | **WRONG** | `WarManager.resolve_full_war` / `_cleanup_conflict_markers` (line 479) | Removes ALL conflict markers from the entire map. Rule: only those that contributed strength in the just-resolved war (i.e., those that were in regions/types matching the war's bonus_strength list and were "granting strength"). |
| 19.2 | **WRONG (critical)** | `setup_war` (line 176) | `basic_tile_in_theater.clear()` discards the basic tiles WITHOUT returning them to `basic_war_tiles[side]`. The Basic War Tile pool is permanently depleted of one tile per theater per war. Over 4 wars × ~5 theaters this leaks ~20 tiles. After WSS the pool can underflow — `setup_war` line 191 does `if pool.size() > 0` but rule §3.7 mandates each player has a fixed Basic Tile set used for every War. |
| 19.3 | **WRONG** | `bonus_war_tiles_in_theater` is also cleared without returning bonus tiles anywhere. Rule §3.7: "the players should remove all of the Bonus War Tiles matching that War from the game" — i.e., played bonus tiles from this war's set are GONE. But the next war's set must be placed on the playmat (i.e., a fresh set of 8 bonus tiles for the next War). Code doesn't track which war set the bonus pool corresponds to and doesn't roll over to the next war's set. |
| 19.4 | **WRONG** | `resolve_war_and_continue` calls `WarManager.setup_war(next_war)` but does NOT skip after AWI — actually it gates with `if next_war != ""` and `get_war_for_after_turn(state.current_turn)` returns "" for current_turn ≥ 6, so behaviorally OK. The skip is implicit. |
| 19.5 | **MISSING** | "If the next war is the Seven Years' War, each player receives Bonus War Tile draws equal to the number of Bonus War Tiles that player had in the War of the Austrian Succession (but not more than 3) at the start of their first AR in the ensuing Peace Turn." — `setup_war` does no carry-over. |

**Fix:** in `resolve_full_war`, before clearing, return Basic tiles to `basic_war_tiles[side]`; remove this war's Bonus Tile set entirely; load the next war's bonus tile set into `bonus_tile_pool`. Track conflict markers that were in regions on the resolved war's strength list and only remove those.

---

## 20. §8.0 Advantages

Rule quote (p.16): "Once per Game Turn ... Advantage tile may not be used on the same Action Round it was taken. A player may activate a maximum of two Advantages per Action Round, and no more than one per Region. ... An Advantage cannot be used if any of its connected spaces contain Conflict markers, but is not returned to the map unless the holder's flag is actually removed."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 20.1 | **WRONG** | `AdvantageManager.can_activate` (line 53) | Per-AR counters `_advantages_used_this_round` and `_regions_used_this_round` are checked, but `reset_round()` is **never called** anywhere. They monotonically increase across the entire game, so after 2 advantage uses ever, `can_activate` returns false forever. |
| 20.2 | **WRONG** | `Advantage.gained_this_round` flag is reset to false (line 23) but **never set to true** when a player gains the advantage. The rule "may not be used on the same Action Round it was taken" is unenforced. |
| 20.3 | **WRONG (severe)** | `AdvantageManager.recompute_control` (line 31) is a stub (`pass`). Advantage control is never automatically computed from the board state. Current code only sets `controlled_by` for the two starting advantages (Wheat→BR, Algonquin Raids→FR). All other advantages can never be gained or lost. |
| 20.4 | **WRONG** | `can_use(any_connected_has_conflict)` (advantage.gd:30) accepts a parameter that's hardcoded to `false` in `AdvantageManager.can_activate` line 74. Conflict-marker-on-connected-space disables nothing currently. |
| 20.5 | **MISSING** | "Returns to the map only when the flag is actually removed" — no explicit handling for flag removal triggering advantage return. |

**Fix:** populate `Advantage.connected_space_ids` from data, write `recompute_control()` properly, hook flag changes to call recompute. Set `gained_this_round = true` on take. Call `AdvantageManager.reset_round()` at the start of every Action Round (`begin_action_round`). Pass the actual conflict-marker check to `can_use`.

---

## 21. §9.0 Treaty Points

Rule quote (p.17): "Treaty Points may be used as an Action Point of any type, but must match the player's current Major or Minor Action (just like Debt). All Treaty Points in excess of four are lost during the Reduce Treaty Points Phase in each Peace Turn."

| # | Verdict | Where | Issue |
|---|---|---|---|
| 21.1 | **OK (cap)** | `reduce_excess_treaty_points` (`player_state.gd:62`) — cap of 4 enforced. |
| 21.2 | **MISSING** | `ActionController` has `take_debt_for_ap` but NO equivalent `spend_treaty_points_for_ap`. Players cannot use Treaty Points as wild AP during their AR through the controller. `PlayerState.spend_treaty_points` exists but no bridge to `major_ap_remaining`/`minor_ap_remaining`. |
| 21.3 | (related) | Same restriction "must match current action type" — needs the same plumbing as `take_debt_for_ap`. |

**Fix:** add `ActionController.spend_treaty_points_for_ap(amount)` mirroring `take_debt_for_ap`.

---

## 22. §11.0 Final Scoring

Rule quote (p.17):
- More total Prestige spaces (incl. United States Political spaces if any USA flags): **2 VP**
- More Available Debt: **1 VP per 2 Debt of difference, max 4 VP**
- Each commodity with more controlled Markets than opponent: **1 VP**
- Each friendly flag in a Territory controlled by other player at Setup: **2 VP**

| # | Verdict | Where | Issue |
|---|---|---|---|
| 22.1 | **MISSING** | `_final_scoring` (`game_manager.gd:445`) | Only awards Available Debt VP. **No Prestige VP, no commodity-control VP, no enemy-starting-Territory-flag VP.** All four Final Scoring categories should run; only one is implemented. |
| 22.2 | **WRONG** | The Available Debt rule: "1 VP for every 2 Debt of difference, max 4 VP" — code does `mini(diff / 2, 4)`. With `diff = 1`, code gives 0 VP. Rule wording "every 2 Debt of difference" — int division is fine. **OK** numerically. |
| 22.3 | **MISSING** | Commodity control: each of 6 commodities — whoever controls more Markets of that commodity gets 1 VP per commodity (not per turn this time, all 6). |
| 22.4 | **MISSING** | "Each friendly flag in a Territory controlled by the other player at Setup: 2 VP" — requires retaining a snapshot of starting-Territory-control. No `setup_starting_control` on SpaceData/SpaceState is referenced for final scoring. |
| 22.5 | **MISSING** | Prestige scoring at game end (separate from per-turn Prestige in §4.1.12). Need to count Prestige spaces (and USA Political spaces if USA flags exist) — same kind of count as in `_score_prestige` but unconditionally on Turn 6 final scoring. |

**Fix:** rewrite `_final_scoring` to apply all four bullets; record `space.starting_control` (already on SpaceData) for the Setup-Territory check.

---

## Summary table — most impactful issues to fix

| Severity | # | Description |
|---|---|---|
| Critical | 19.2 | Basic War tile pool depletes irreversibly each war (game-breaking after WSS). |
| Critical | 5.1 | Played Event cards go to discard, then re-shuffle into draw pile — Events recycle. |
| Critical | 22.1 | Final Scoring is missing 3 of 4 categories. |
| Critical | 1.1 / 1.2 | Two of three auto-victory conditions never check. |
| High | 17 | CP spending only takes Territories, ignores Forts/Markets/Naval and theater Region constraints. |
| High | 14.1 | War tile effects applied AFTER bonus strength computation (wrong order). |
| High | 13.5 / 13.6 / 12 | No squadron construct/deploy actions, no Conflict-marker removal action. |
| High | 20.1 / 20.2 / 20.3 | Advantages: per-AR counters never reset, gained-this-round never flagged, control not recomputed from board. |
| Medium | 7.1 | Region-switch +1 cost wrongly applied to Military actions. |
| Medium | 8.1 / 9.1 | Market Isolation not tracked; daisy-chain prevention missing; isolated→cost-1 missing. |
| Medium | 18 | Territory refusal mechanic completely absent. |
| Medium | 16.1 / 16.3 | Alliance space bonus strength uses generic region match, ignores per-country and per-war dot pattern. |
| Medium | 21.2 | Treaty Points cannot be spent as wild AP at runtime. |
| Low | 2.1 | Investment-tile recycling skips the "Used Investment Tiles" stage. |
| Low | 10.2 | `is_protected` doesn't restrict to Markets — Political spaces can falsely cost +1. |
| Low | 11.2 | Bonus War tile per-AR limit (max 2) not enforced. |
| Low | 13.4 | Capturing damaged opposing Fort doesn't flip control or clear damage marker. |

End of audit.
