# Validation snapshot / 검증 기록

Checked on September 8, 2026, on Windows with Godot 4.7.2. These results describe the tested implementation; they are not a proof of every possible card interaction or AI strength.

2026년 9월 8일 Windows·Godot 4.7.2에서 확인했다. 아래 결과가 모든 카드 조합의 정확성이나 AI의 전략적 강도를 전수 증명하는 것은 아니다.

| Suite / 검사 | Result / 결과 |
|---|---|
| Rules / 규칙 | 53 passed |
| Cards / 카드 | 97 passed |
| Edge cases / 경계 조건 | 42 passed |
| Ministry reveal / 내각 공개 | 39 passed |
| Diplomatic event draw / 외교 카드 뽑기 | 33 passed |
| Localization / 언어 | 20 passed |
| Total individual checks / 개별 검사 합계 | 284 passed |
| Full campaigns / 캠페인 | 12 completed; 6 reached Turn 6 |
| Live game scene with AI / 실제 게임 장면·AI | Korean and English passed |
| Rendered UI and resume / 실제 화면·저장 재개 | Korean and English passed |

Visual checks cover the hand shown during Ministry selection, optional Ministry reveal, the Used Cards detail overlay, event-card purchases with Diplomatic points, saved decisions, war choices, and the dashboard. The Navy Box checks use actual construction and deployment commands to confirm that the central panel and map show the same changing counts. Explicit display fixtures also cover zero and eight waiting squadrons, returning squadrons, four Global Demand commodities, and map zoom.

시각 검수는 내각 선택 중 손패 보기, 선택적 내각 공개, 사용된 카드 상세의 표시 순서, 외교 점수로 카드 뽑기, 저장된 선택 재개, 전쟁 선택과 대시보드를 포함한다. 해군 상자는 실제 건조·배치 명령으로 중앙 정보창과 지도의 수량 갱신을 확인했다. 0척·8척, 귀환 예정 함대, 세계 수요 4종과 지도 확대는 별도로 준비한 표시 상태에서도 확인했다.

Run the suites from PowerShell at the repository root:

```powershell
.\VERIFY.ps1 -GodotExe 'C:\Tools\Godot\Godot.exe'
```

The runner isolates each suite's user data and writes reports to `output/validation/`. Temporary profiles, reports, and game saves are excluded from Git. The selected README screenshots are stored in `docs/images/`.

검사마다 사용자 데이터 경로를 분리하고 `output/validation/`에 결과를 기록한다. 임시 검사 상태·보고서·실제 저장 파일은 Git에서 제외하며, README에 사용하는 화면만 `docs/images/`에 보관한다.
