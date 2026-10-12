# RESEARCH-001 — Steam 경쟁작 조사

조사일: **2026-10-12**. 검색·상점 텍스트 확인 시간: **01:39–01:41 UTC / 10:39–10:41 KST**. 시간은 도구 호출이 진행된 분 단위 구간이며 검색 색인의 갱신 시각과 다르다.

정책: `steam_links_are_leads_not_verified_sales`. C01·C04·C08별 공식 Steam 링크를 각각 **3·3·4개** 확보했다. 세 후보의 `enough_links_for_manual_review`는 수동 검토에 필요한 링크가 있다는 뜻이다. 수요·상업성·규칙 전체의 동일성·구현 품질·판매 실적을 검증했다는 뜻이 아니다. C08은 출시된 비교작 3개와 출시 예정작 1개로 구분한다. 예정작의 상태는 열람된 [Wavecraft Legends 상점](https://store.steampowered.com/app/4492170/)에 근거한다.

## 조사 범위와 방법

기획 기준은 [승인된 문서](../design/independent_concepts.md)의 다음 세 ‘핵심 메커니즘’ 항목뿐이다.

- **C01 음영 인쇄소:** 겹친 칸의 명암 반전, 회전 가능한 제한 판, 실행 취소와 최소 인쇄 수 도전.
- **C04 순회 극단:** 이동이 시간을 소비하는 노선 선택, 공연 수요와 배우 피로의 교환, 제한 예산의 장비·홍보 배분.
- **C08 부표 슬라럼:** 단순화한 관성·선회, 방향 지정 부표 게이트, 자기 기록 고스트.

최초 로컬 추출에서 문맥 범위를 넓게 잡아 위 항목 외 내용도 도구 출력에 포함되는 범위 초과가 있었다. 이후 핵심 메커니즘 세 줄을 별도로 추출했고, 나머지 콘셉트·분량·일정·후보 이유는 이 조사 판단에 사용하지 않았다. 이전 PLAN-001 문서와 개인 기록은 열람하지 않았다.

Codex 웹 도구의 **web_search(search_query)**로 비교작을 찾고, 아래 채택한 10개 앱의 **공식 상점 페이지를 open으로 열어 HTML 추출 텍스트의 게임 설명·기능 목록**을 확인했다. 이것은 검색 결과만 읽은 경우와 구별되는 페이지 열람이지만, 실시간 브라우저의 지역 고정 구매 화면을 검증한 것은 아니다. 웹 도구는 크롤링·캐시 시점을 표시했다. 예고·소개는 개발자의 주장으로 관찰했으며 실제 플레이 사실로 바꾸지 않았다.

공개 페이지를 소수의 비교 대상으로 선택적으로 열람했다. Steam 앱 상세 API·리뷰 API·리뷰 페이지네이션·자동 대량 수집을 사용하지 않았다. 로그인·연령·지역·이용 제한을 우회하지 않았고 다운로드·구매·리뷰 작성·외부 연락을 하지 않았다. 검색에 우연히 노출된 리뷰의 사용자명·개인 정보를 저장하지 않았다. 실행 영상과 스크린샷을 직접 감상하거나 게임을 실행하지 않았다.

JSON의 `observed_in_search`는 지정된 스키마에 맞춘 출처 관찰 상태로, 검색 후 페이지 열람으로 확인한 설명도 포함한다. ‘실제 구현 검증 완료’라는 추가 상태를 뜻하지 않는다. 각 항목의 `evidence_note`에서 페이지 열람 여부와 미확인 규칙을 명시한다.

## C01 — 겹침 반전은 직접 경쟁 규칙이 존재한다

| 공식 Steam 비교작 | 직접 확인한 설명 | 실제 규칙 중복과 확인 한계 |
| --- | --- | --- |
| [VOI · 545690](https://store.steampowered.com/app/545690/) | XOR 진리표와 소수의 드래그 가능한 도형으로 목표 도형을 만든다는 설명. | **직접 중복:** 겹침으로 흑백 결과가 반전되는 연산과 목표 모양 맞추기. C01의 반복 인쇄 상태 전이와 VOI의 도형 배치는 구별해야 한다. 판 회전·취소·최소 수는 확인 불가. |
| [Zerko · 2862990](https://store.steampowered.com/app/2862990/) | 모양·값이 다른 블록을 배치해 모든 숫자를 0으로 만든다. 점수·시간 압박이 없다고 소개한다. | **부분 중복:** 배치 결과를 역산해 보드를 목표 상태로 맞춘다. 숫자의 0 맞추기는 명암 XOR와 동일한 규칙으로 확인되지 않았다. 회전·취소·최소 수는 확인 불가. |
| [.projekt · 759000](https://store.steampowered.com/app/759000/) | 시점에 따라 물체가 어떻게 보이는지 추론해 실루엣을 맞춘다. | **인접 비교:** 목표 모양과 공간 관계의 논리 추론. XOR·제한 판 회전은 확인 불가. 최소·최대 블록과 취소는 검색 사용자 리뷰의 주장만 보았으므로 공식 확인된 규칙으로 세지 않는다. |

**차별점 가설:** C01은 제한 판의 회전, 인쇄 단계별 상태 누적, 실행 취소, 최소 인쇄 수를 함께 보여 주는 경험을 검토할 수 있다. 그러나 겹침 반전 자체를 독창적이라고 주장할 수 없다. VOI가 같은 XOR 연산을 명시하고 있고, 그 작품에 나머지 기능이 없다는 결론도 아직 낼 수 없다. 사용자는 설명 또는 실제 화면에서 전체 규칙 조합을 재검토해야 한다. [VOI](https://store.steampowered.com/app/545690/)

**빠진 근거:** 세 비교작의 회전·취소·최소 수 지원과 풀이 다양성은 미확인이다. 특히 .projekt의 공식 열람 텍스트에는 60개 레벨, 검색 사용자 리뷰에는 120개와 추가 모드 주장이 보여 현재 분량을 확정할 수 없다. 최초 판매 버전과 업데이트 이후를 분리한 확인이 필요하다. [VOI](https://store.steampowered.com/app/545690/), [Zerko](https://store.steampowered.com/app/2862990/), [.projekt](https://store.steampowered.com/app/759000/)

## C04 — 공연 경영과 장비·홍보 배분은 겹치지만 시간·피로는 미확인이다

| 공식 Steam 비교작 | 직접 확인한 설명 | 실제 규칙 중복과 확인 한계 |
| --- | --- | --- |
| [The Amazing American Circus · 1433860](https://store.steampowered.com/app/1433860/) | 도시 순회, 지역별 관객 반응, 공연 카드 대결, 극단과 마차 업그레이드. | **직접 활동 중복:** 이동하며 공연을 선택하고 자원을 관리한다. 이동 시간 비용·피로 교환·홍보 배분은 확인 불가. 카드 대결은 확인된 별도 규칙이다. |
| [Circus Electrique · 1666250](https://store.steampowered.com/app/1666250/) | 공연자의 기술·궁합·Devotion이 공연 수익을 결정한다. 급여 유지와 턴제 전투를 함께 다룬다. | **부분 중복:** 구성원 상태와 배치가 공연 성과·돈에 연결된다. Devotion은 사기다. 배우 피로와 같다고 확인하지 않았다. 노선 시간·홍보 배분은 확인 불가. |
| [Rock God Tycoon · 410840](https://store.steampowered.com/app/410840/) | 도시 순회 공연 예약·연습, 현금으로 악기·장비 업그레이드와 홍보 구매, 밴드의 긴장·결속 관리. | **직접 규칙 중복:** 현금을 장비와 홍보에 배분하며 순회 공연을 운영한다. 긴장은 피로의 증거가 아니다. 이동 시간 차감과 공연 수요·피로의 교환식은 확인 불가. |

**차별점 가설:** 이동 시간·공연 수요·배우 피로·장비와 홍보의 예산을 한 일정 결정에 연결하는 방식은 검토할 만하다. 장비·홍보 배분은 Rock God Tycoon에 이미 소개되어 있으므로 그 요소만으로 차별성을 주장할 수 없다. 일정과 피로 중심의 조합이 세 작품과 얼마나 다른지는 수동 확인이 필요하다. 카드 대결과 턴제 전투가 확인된 비교작과의 판단 단위 차이 역시 아직 체험으로 검증하지 않았다. [Rock God Tycoon](https://store.steampowered.com/app/410840/), [The Amazing American Circus](https://store.steampowered.com/app/1433860/), [Circus Electrique](https://store.steampowered.com/app/1666250/)

**빠진 근거:** 모든 비교작에서 노선별 시간 차감, 공연 후 피로 증가와 휴식 회복, 수요 예측, 장비·홍보 효과 수치, 여러 일정 전략의 실효성을 확인하지 못했다. 소개 문구에 없다고 기능 부재로 처리하지 않는다. [The Amazing American Circus](https://store.steampowered.com/app/1433860/), [Circus Electrique](https://store.steampowered.com/app/1666250/), [Rock God Tycoon](https://store.steampowered.com/app/410840/)

## C08 — 방향 부표와 기록 재생은 각각 기존 규칙이다

| 공식 Steam 비교작 | 직접 확인한 설명 | 실제 규칙 중복과 확인 한계 |
| --- | --- | --- |
| [Design it, Drive it : Speedboats · 501090](https://store.steampowered.com/app/501090/) | 선체 설계와 조종, solo time trials, 빨간 부표는 우회전·노란 부표는 좌회전, 개인 최고·최근·세션 랩타임 표시. | **직접 중복:** 보트 선회와 방향별 부표, 시간 기록 도전. 회전 표식이 방향·순서를 강제하는 통과 게이트 판정과 같은지는 미확인. 자기 고스트는 확인 불가. |
| [Riptide GP2 · 257790](https://store.steampowered.com/app/257790/) | 변화하는 수면의 주행, Hot Lap, 친구 최고 주행 녹화와 경쟁하는 VR Challenge. | **부분 중복:** 수상 기록 도전과 기록 재생 상대. 자기 기록 고스트·방향 부표·관성 모델은 확인 불가. VR Challenge라는 이름을 VR 헤드셋 지원의 증거로 해석하지 않는다. |
| [Absolute Drift · 320140](https://store.steampowered.com/app/320140/) | 드리프트, 점들을 통과하는 Drift Lines, 리플레이와 고스트, 친구 또는 세계 최고 주행 보기. | **인접 중복:** 미끄러지는 이동의 숙련과 고스트 비교. 자동차 작품이며 수상 부표 규칙은 확인되지 않았다. 자기 기록 고스트의 저장·표시 방식도 미확인. |
| [Wavecraft Legends · 4492170](https://store.steampowered.com/app/4492170/) | Time Trials, 물결 영향, 부표·체크포인트 누락 불이익을 소개한다. 열람 페이지는 미출시·출시일 미정. | **예정 기능 중복:** 수상 조종·기록·부표. 실제 구현 검증이 아니다. 방향 지정·자기 고스트는 확인 불가. 출시작 판매 비교에 포함하지 않는다. |

**차별점 가설:** 단순화한 관성·선회, 방향 게이트, 자기 기록 고스트를 연결해 코너별 개선을 알아보기 쉽게 만드는 방식은 검토 가능하다. 방향 부표 자체는 Speedboats에서, 고스트·주행 녹화 비교는 다른 두 출시작에서 소개되어 있으므로 신규 규칙이라는 주장은 할 수 없다. 자기 최고 기록과의 정확한 차이, 조작 감각, 통과 판정이 차별점을 만들지는 사용자 검토와 별도 플레이 검증이 필요하다. [Speedboats](https://store.steampowered.com/app/501090/), [Riptide GP2](https://store.steampowered.com/app/257790/), [Absolute Drift](https://store.steampowered.com/app/320140/)

**빠진 근거:** 자기 고스트의 실제 지원·오프라인 조건, 게이트 방향·순서 위반 판정, 물리 모델, 즉시 재시작 속도, 짧은 반복의 만족도는 확인 불가다. 예정작의 소개만으로 기능 완성도나 출시 시점을 추정할 수 없다. [Speedboats](https://store.steampowered.com/app/501090/), [Riptide GP2](https://store.steampowered.com/app/257790/), [Absolute Drift](https://store.steampowered.com/app/320140/), [Wavecraft Legends](https://store.steampowered.com/app/4492170/)

## 분량·가격·리뷰·판매 근거의 상태

아래 분량은 **열람된 상점 설명에 실린 개발자 표기**다. 현재 실행 버전이나 출시 당시 분량을 세어 검증하지 않았다. 레벨·도시·이벤트·직업 수는 서로 다른 단위이며 이를 제작 비용·플레이 시간·가치로 환산하지 않는다.

| 비교작 | 설명에서 관찰한 분량과 한계 | 현재 가격 / 현재 리뷰 집계·평가 / 판매량 / 매출 |
| --- | --- | --- |
| [VOI](https://store.steampowered.com/app/545690/) | 공식 소개에서 전체 퍼즐 수·완주 시간 확인 불가. | 모두 확인 불가 |
| [Zerko](https://store.steampowered.com/app/2862990/) | 공식 소개에서 전체 퍼즐 수·완주 시간 확인 불가. | 모두 확인 불가 |
| [.projekt](https://store.steampowered.com/app/759000/) | 공식 소개 60개 레벨. 검색 사용자 리뷰의 120개와 충돌하여 현재 총량 확인 불가. | 모두 확인 불가 |
| [The Amazing American Circus](https://store.steampowered.com/app/1433860/) | 90개 도시·마을, 4개 지역, 200개 초과 카드 표기. 완주 시간 및 출시 당시 수량 미검증. | 모두 확인 불가 |
| [Circus Electrique](https://store.steampowered.com/app/1666250/) | 6개 구역, 15개 플레이 가능 원형 직업 표기. 공연·임무 총수와 완주 시간 미확인. | 모두 확인 불가 |
| [Rock God Tycoon](https://store.steampowered.com/app/410840/) | 76개 도시 표기. 각 도시의 고유 콘텐츠·전체 완주 시간 미확인. | 모두 확인 불가 |
| [Speedboats](https://store.steampowered.com/app/501090/) | Lotus Lake·Glen Canyon 두 지도와 여러 코스 설명. 현재 전체 코스 수·기록 도전 시간 미확인. | 모두 확인 불가 |
| [Riptide GP2](https://store.steampowered.com/app/257790/) | 60개 초과 이벤트·10종 hydro jet·25개 스턴트 표기. 이벤트 수는 고유 코스 수가 아니다. | 모두 확인 불가 |
| [Absolute Drift](https://store.steampowered.com/app/320140/) | 34개 레벨·5개 자유 주행 지역·최대 6대 차량, Zen Edition의 야간 이벤트 5개 표기. 중복 합산하지 않으며 완주 시간 미확인. | 모두 확인 불가 |
| [Wavecraft Legends](https://store.steampowered.com/app/4492170/) | 미출시 소개의 15개 초과 트랙·5개 장소·8명 캐릭터 예정치. 출시 분량으로 취급하지 않는다. | 모두 확인 불가 |

가격 표시를 보았지만 동일 지역·통화·현재 시점으로 검증하지 못했다. 예를 들어 Circus Electrique와 Speedboats의 열린 텍스트에는 조사일보다 앞선 **October 8 할인 종료**가 남아 있었다. 다른 페이지는 달러 기호·유로·파운드·엔 기호를 섞어 표시했다. 따라서 화면에 보인 숫자를 현재 정가·할인가나 한국 가격으로 제시하지 않는다. 실제 출시 가격, 할인 이력, DLC·묶음과 본편 구분도 이번 조사에서 검증하지 않았다. [Circus Electrique](https://store.steampowered.com/app/1666250/), [Speedboats](https://store.steampowered.com/app/501090/), [Rock God Tycoon](https://store.steampowered.com/app/410840/), [Zerko](https://store.steampowered.com/app/2862990/), [.projekt](https://store.steampowered.com/app/759000/)

리뷰 집계도 출처 시점·언어·구매 필터를 통일하지 못했다. 예를 들어 VOI와 Riptide GP2의 검색 결과와 열람된 페이지에는 서로 다른 리뷰 수가 보였고, Absolute Drift는 English Reviews 범주로 표시했다. 현재 수치·평가로 확정하지 않으며 리뷰 본문 표본 조사도 실시하지 않았다. 검색에 나온 .projekt 리뷰의 분량·기능 주장은 확인 과제로만 기록했다. [VOI](https://store.steampowered.com/app/545690/), [Riptide GP2](https://store.steampowered.com/app/257790/), [Absolute Drift](https://store.steampowered.com/app/320140/), [.projekt](https://store.steampowered.com/app/759000/)

**판매량·매출은 모든 비교작에서 확인 불가**다. 공개 상점의 소개와 리뷰가 이를 검증하는 근거가 되지 않는다. 리뷰 수를 판매량으로 환산하지 않았으며 수익·시장 규모·성공 확률·후보 순위를 생성하지 않았다. 10개 링크가 있다는 사실로 적정 출시 분량이나 가격을 결정할 수도 없다.

## 검색 및 열람 기록

아래는 실행한 검색어다. 영문 검색어로 공식 Steam 설명을 찾았으며 보고서는 한국어로 작성했다. Steam 내부 검색 순위·노출량·전체 경쟁작 모집단을 조사한 것은 아니다. 각 묶음은 앞서 적은 검색 시간 구간 안에서 실행했다.

| 목적 | 실제 검색어 |
| --- | --- |
| 초기 탐색 | `site:store.steampowered.com/app puzzle XOR overlap rotate tiles minimum moves`; `site:store.steampowered.com/app circus management touring fatigue travel performances`; `site:store.steampowered.com/app boat racing slalom buoys time trial ghost` |
| 퍼즐 탐색 | `site:store.steampowered.com/app "LYNE"`; `site:store.steampowered.com/app "Hexcells"`; `site:store.steampowered.com/app "Polimines"`; `site:store.steampowered.com/app "puzzle" "xor"`; `site:store.steampowered.com/app "puzzle" "XOR"` |
| 퍼즐 규칙 보완 | `site:store.steampowered.com/app puzzle "rotate" "flip"`; `site:store.steampowered.com/app puzzle "minimum" "moves" "rotate"`; `site:store.steampowered.com/app "Up Left Out"` |
| 공연 경영 탐색 | `site:store.steampowered.com/app "tour" "band" management`; `site:store.steampowered.com/app "Circus" "fatigue"`; `site:store.steampowered.com/app "Rock God Tycoon"`; `site:store.steampowered.com/app "Circus" "fatigue"` 재검색 |
| 수상·고스트 탐색 | `site:store.steampowered.com/app "boat" "ghost"`; `site:store.steampowered.com/app "racing" "buoys"`; `site:store.steampowered.com/app "Trackmania" "ghost"`; `site:store.steampowered.com/app "Riptide GP"`; boat/ghost와 racing/buoys 재검색 |
| 수상·조종 보완 | `site:store.steampowered.com/app "Riptide GP2"`; `site:store.steampowered.com/app "Trackmania" "ghosts"`; `site:store.steampowered.com/app "Absolute Drift" "ghost"` |

**직접 열람한 자료:** 채택한 아래 10개 공식 Steam 상점의 텍스트를 모두 열었다. About This Game 및 Features를 근거로 사용했고, 필요한 설명 위치를 open/find로 재확인했다.

- C01: [VOI — 성공한 실제 열람 URL](https://store.steampowered.com/app/545690/VOI/), [Zerko](https://store.steampowered.com/app/2862990/Zerko/), [.projekt](https://store.steampowered.com/app/759000/).
- C04: [The Amazing American Circus](https://store.steampowered.com/app/1433860/), [Circus Electrique](https://store.steampowered.com/app/1666250/), [Rock God Tycoon](https://store.steampowered.com/app/410840/).
- C08: [Speedboats](https://store.steampowered.com/app/501090/), [Riptide GP2](https://store.steampowered.com/app/257790/Riptide_GP2/), [Absolute Drift](https://store.steampowered.com/app/320140/), [Wavecraft Legends](https://store.steampowered.com/app/4492170/Wavecraft_Legends/).

VOI의 짧은 URL 최초 open은 **Cache miss**로 실패했다. 검색으로 관찰한 타이틀 포함 URL을 열어 공식 설명을 확인했으며 JSON에는 관찰된 앱 ID의 짧은 공식 URL을 기록했다. 실패한 호출을 성공으로 기록하지 않았다. [VOI](https://store.steampowered.com/app/545690/VOI/)

**검색 결과만 본 탐색 자료:** [Entanglement](https://store.steampowered.com/app/719140/), [Polimines](https://store.steampowered.com/app/1892790/), [Hexcells](https://store.steampowered.com/app/265890/), [LYNE](https://store.steampowered.com/app/266010/), [Up Left Out](https://store.steampowered.com/app/867380/), [Zasa - An AI Story](https://store.steampowered.com/app/447240/), [The Tour](https://store.steampowered.com/app/2766370/), [Tunnel Boat Terror](https://store.steampowered.com/app/2100650/), [Marine♡Slalom](https://store.steampowered.com/app/4744790/) 등. 이들의 본문을 별도로 열지 않았으며 채택 목록이나 시장 성과의 근거로 사용하지 않았다. .projekt의 일부 사용자 리뷰도 검색 결과에서만 읽었고 개인의 완주 시간을 대표 플레이 시간으로 사용하지 않았다. [.projekt](https://store.steampowered.com/app/759000/)

## 사용자 검토가 필요한 사항

1. 직접 중복·부분 중복·인접 비교를 구별해 비교작 선정의 적합성을 검토한다. 특히 C01의 XOR가 VOI와 겹친다는 점, C04의 장비·홍보가 Rock God Tycoon과 겹친다는 점, C08의 방향 부표가 Speedboats와 겹친다는 점을 우선 본다. [VOI](https://store.steampowered.com/app/545690/), [Rock God Tycoon](https://store.steampowered.com/app/410840/), [Speedboats](https://store.steampowered.com/app/501090/)
2. 기능 미기재를 부재로 간주하지 말고 회전·취소·최소 수, 노선 시간·피로, 자기 고스트·게이트 판정을 공개 설명·매뉴얼·영상으로 추가 확인한다. 예정작은 출시작과 분리한다. [VOI](https://store.steampowered.com/app/545690/), [Circus Electrique](https://store.steampowered.com/app/1666250/), [Riptide GP2](https://store.steampowered.com/app/257790/), [Wavecraft Legends](https://store.steampowered.com/app/4492170/)
3. 동일 지역·통화·날짜의 본편 가격과 정가·할인가를 다시 확인하고, 현재 리뷰는 언어·구매 유형·기간을 명시해 검토한다. 출시 당시와 업데이트 이후 분량을 구분하며 적정 가격이나 최소 출시 분량을 아직 결정하지 않는다. [.projekt](https://store.steampowered.com/app/759000/), [Circus Electrique](https://store.steampowered.com/app/1666250/), [Absolute Drift](https://store.steampowered.com/app/320140/)
4. 이 보고서로 최종 게임을 자동 선정하지 않는다. 추가 조사·개발·플레이테스트·구매·공개 범위는 사용자가 결정한다. 이번 작업은 조사 문서 작성과 아래 검증에 한정한다.

## 실제 수행한 검증

저장 후 두 파일을 다시 읽어 UTF-8 엄격 디코딩과 JSON 파싱을 실행했다. 지정한 키·상태 값·날짜, 후보 ID의 정확한 집합, 후보별 3~5개 비교작, 정수 앱 ID와 공식 URL 숫자의 일치, 앱 중복 없음, 비어 있지 않은 근거·공백 목록을 검사했다. 확인한 제목·앱 ID 목록과 대조했으며, 보고서에 10개 채택 URL과 시간·열람 구분·확인 불가 표시가 있는지도 검사했다. 이 검사는 링크와 파일 구조를 대조한 것이며 플레이·시장 성과 검증은 아니다.

작성 전 Git 상태가 깨끗함을 확인했고, 작성 후 상태에서 지정된 조사 문서 두 개만 추가되었는지 확인했다. 커밋·코드 제작·의존성 설치·구매·외부 공개는 수행하지 않았다. 저장소 테스트 실행기는 호출하지 않았으며 위 데이터 검사를 실제 실행한 검증으로 보고한다. 최초 셸 실행은 도구 초기화 오류로 실패했으므로 파일 입출력과 검증에는 Node 도구를 사용했다.
