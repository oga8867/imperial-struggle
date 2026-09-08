extends "res://scripts/card_regression.gd"

# 언어 선택은 게임 규칙의 입력이 아니다. 표시와 저장 상태를 함께 대조한다.
func _ready() -> void:
	await get_tree().process_frame
	LocaleManager.set_locale("en")
	check("영어 번역표 읽기",LocaleManager.ui_english.size()>=317)
	var format = RegEx.new()
	format.compile("%[+0-9.\\-]*[sdf]")
	var valid=true
	for source in LocaleManager.ui_english:
		var target=LocaleManager.ui_english[source]
		var left=format.search_all(source).map(func(m):return m.get_string())
		var right=format.search_all(target).map(func(m):return m.get_string())
		if left!=right or target.is_empty() or LocaleManager._has_korean(target): valid=false
	check("전체 번역의 포맷 인자·영문 누락 검사",valid)
	check("주요 외교 전체 이름",LocaleManager.tx("주요 ")+LocaleManager.action(Enums.ActionType.DIPLOMATIC)=="Major Diplomatic")
	check("외교 버튼 전체 이름",LocaleManager.tx("이벤트 카드 1장 뽑기 · 외교 3점")=="Draw 1 event card · 3 diplomatic points")
	check("지역 보상 전체 이름",LocaleManager.tx("조약점수 %d") % 2=="2 Treaty Points")
	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	check("기존 한국어 로그의 숫자 보존",LocaleManager.message("부채 2 증가 → 행동점수 +3")=="Debt +2 → action points +3")
	check("기존 한국어 조건부 공개 안내 번역",not LocaleManager._has_korean(LocaleManager.message("내각을 비공개로 유지하여 이 이벤트는 사용하지 않았습니다.")))
	check("전쟁 선택 비용의 숫자 보존",LocaleManager.message("양도 거부 · 상대에게 5 VP")=="Refuse cession · opponent gains 5 victory points")
	check("지명은 원작 영문 데이터 사용",LocaleManager.message(GameManager.state.spaces.ireland_alliance.data.name_ko)==GameManager.state.spaces.ireland_alliance.data.display_name)
	check("영어 공간 비용 설명",not LocaleManager._has_korean(ActionController.explain_space("ireland_alliance")))
	var card=GameData.ministries[0]
	check("내각 이름·능력은 영문 원문 사용",card.disp_title()==card.title and card.disp_abilities()==card.abilities)
	var payload=JSON.stringify(SaveLoad._serialize())
	LocaleManager.set_locale("ko")
	check("한국어 복귀",LocaleManager.tx("조약점수")=="조약점수" and LocaleManager.action(Enums.ActionType.DIPLOMATIC)=="외교")
	check("한국어 내각 번역 복귀",card.disp_title()==card.title_ko and card.disp_abilities()==card.abilities_ko)
	check("언어 전환이 저장 모델을 변경하지 않음",JSON.stringify(SaveLoad._serialize())==payload)
	LocaleManager.set_locale("en")
	check("영어에서도 외교 3점으로 카드 획득",ActionController.draw_event_card() and ActionController.major_ap_remaining==1)
	var ids=GameManager.state.france.hand.map(func(c):return c.id)
	var saved=SaveLoad._serialize()
	check("영어에서 저장 왕복",SaveLoad._deserialize(JSON.parse_string(JSON.stringify(saved))))
	check("영어 저장 복원 후 손패·사용 점수 유지",GameManager.state.france.hand.map(func(c):return c.id)==ids and ActionController.major_ap_remaining==1)
	var settings=ConfigFile.new()
	check("언어 설정을 별도 환경 설정에 보존",settings.load("user://settings.cfg")==OK and settings.get_value("interface","language")=="en")
	LocaleManager.set_locale("invalid")
	check("지원하지 않는 언어 변경 거절",LocaleManager.current_locale=="en")
	check("번역 요청 누락 없음",LocaleManager.missing_translations.is_empty())
	LocaleManager.set_locale("ko")
	print("LOCALE REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed==0 else 1)
