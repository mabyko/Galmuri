> 한국어 기획 참고본 · 2026-10-23. 최신 기준은 [영문 문서](../technical-validation.md)입니다. 새 요구 사항은 영문 기준 문서에 먼저 반영합니다.

# SwiftUI 구성과 기술 검증 계획

2026-10-23 · 구현 전 제안. 이 기획 작업에서는 실제 사용자 Chrome 데이터를 읽거나 변경하지 않았다.

## 기술 방향

사용자 결정에 따라 **SwiftUI 네이티브 macOS 앱**을 만든다. 기존 HTML/CSS는 디자인 참고로 사용한다. 웹 UI를 앱에 넣거나 Electron·WKWebView 셸을 만드는 계획은 채택하지 않는다.

| 영역 | 제안 | 이유와 확인할 점 |
| --- | --- | --- |
| 화면 | SwiftUI 사이드바·표·선택 항목 편집·시트·도구 막대 | 기존 정보 구조를 네이티브 UI로 재구성. 다중 선택·열 정렬·키보드·VoiceOver 확인 |
| 파일 접근 | Foundation + 필요 시 AppKit의 폴더 선택창 | 사용자가 고른 디렉터리와 지속 접근 권한을 네이티브에서 관리 |
| 작업본 | 앱 Application Support에 버전 있는 로컬 문서 저장 | Base, 작업본, 식별자 매핑, 변경 내역, 반영 상태를 원자적으로 저장. 우선 별도 DB 의존성 없이 시작하는 안 |
| 병합 | UI와 분리된 순수 Swift 로직 | fixture로 결정적 결과와 충돌을 검증. 파싱/파일 교체와 분리 |
| Chrome 어댑터 | 형식별 지원 조건이 명시된 Swift 코드 | 읽기 가능과 쓰기 검증 완료를 분리. 앱 모델을 그대로 Chrome JSON으로 직렬화하지 않음 |
| 테스트 | Swift Testing 또는 XCTest, 합성 파일 fixture | Xcode/최소 OS 선정 때 확정. 실제 네이티브 구현 시 적용 |

최소 macOS는 미정이다. SwiftUI 표·사이드바·inspector의 API 가용성, 지원 사용자 환경을 확인한 뒤 정한다. AppKit은 파일 선택과 필요한 OS 통합에 한정해 보완한다. 과도한 서비스 계층이나 플러그인 시스템은 만들지 않는다.

이번 HTML 시안에는 데모 흐름만 있고 이 표의 Swift 코드는 없다. 시안 동작 검사는 네이티브 검증과 별개다.

## 현재 근거와 한계

2026-10-23에 Apple 문서와 Chromium HEAD 소스를 확인했다. HEAD는 설치된 사용자 Chrome 버전과 같지 않다. 지원 검증 때에는 Chrome 버전·빌드·채널·해당 소스 리비전·관찰한 저장 파일을 고정해 기록한다.

- Chromium의 [user_data_dir.md](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)는 프로필별 하위 디렉터리와 macOS 기본 경로, 사용자 지정 경로를 설명한다. 기본 경로만으로 모든 설치를 발견했다고 판단하지 않는다.
- [bookmark_storage.cc](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/browser/bookmark_storage.cc)는 로컬/계정 노드 직렬화, sync metadata, 지연 저장과 종료 시 쓰기, 평문/암호문 저장 분기를 포함한다. 디스크 파일 재조회만으로 실행 중 메모리와 동기화를 해결할 수 없다는 근거다.
- [bookmark_features.cc](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/common/bookmark_features.cc)는 평문·암호문 병행 쓰기와 우선 읽기 단계들을 구분한다. 평문 파일 존재만으로 authoritative 원본이라고 판단하지 않는다.
- [bookmark_node.h](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/browser/bookmark_node.h)의 ID/UUID 설명과 [bookmark_codec.cc](https://chromium.googlesource.com/chromium/src/+/HEAD/components/bookmarks/browser/bookmark_codec.cc)의 복구 처리를 확인했다. ID/GUID를 무조건 영구 불변으로 간주하지 않는다.
- [Apple 파일 접근 문서](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)는 사용자 선택 폴더·security-scoped URL bookmark를 통한 지속 접근을 설명하며, Sandbox 밖의 다른 접근 제한도 남을 수 있음을 명시한다. 실제 폴더 접근 가능성은 앱에서 검증해야 한다.
- [Chrome 북마크 가져오기/내보내기](https://support.google.com/chrome/answer/96816?hl=en)는 호환 HTML 경로의 근거다. 직접 저장 지원을 보증하는 문서는 아니다.

Apple 파일 접근 문서는 Context7에서 라이브러리 `/websites/developer_apple_de`를 resolve한 뒤 조회했으며 공식 원문도 확인했다. SwiftUI도 `/websites/developer_apple_swiftui`를 resolve한 뒤 조회했다. [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)의 분할 탐색과 [Table](https://developer.apple.com/documentation/swiftui/table)의 다중 선택 지원을 확인했다. 구체적인 API 가용성은 구현 때 최소 OS에 맞춰 재확인한다.

## 권한과 프로필 발견

1. 사용자가 Chrome 데이터 루트 또는 개별 프로필 폴더를 선택한다. 폴더를 선택했어도 앱이 인증 쿠키·비밀번호·기록을 읽는 기능은 제공하지 않는다.
2. `Local State`의 프로필 정보와 실제 폴더를 필요한 범위에서 대조하는 안을 검증한다. 이 구조도 버전별 어댑터 대상으로 다룬다. 이름·아바타는 표시용이며 프로필 키가 아니다.
3. 연결 키는 앱이 부여한 profile UUID와 승인된 루트·프로필의 파일 식별 정보로 관리한다. 경로만 바뀌거나 같은 경로에 새 프로필이 생기는 경우를 구별한다.
4. 앱 재실행 때 security-scoped URL bookmark를 해석하고 stale 여부·접근 결과를 검사한다. 접근 시작/종료를 짝지어 처리하고 실패 시 재선택한다. 여기서 URL bookmark는 웹 북마크와 다른 OS 권한 데이터다.
5. 루트 안 경로를 정규화하고 심볼릭 링크·경로 변경·권한 철회를 검사한다. 승인한 폴더 밖을 임의 탐색하지 않는다.

초기 PermissionError의 원인이 TCC, Sandbox, 파일 권한 중 무엇인지는 아직 확인되지 않았다. 폴더 선택, 서명된 실제 앱, 재실행, 권한 철회 조합을 먼저 검증한다. 전체 디스크 접근을 무조건 해결책으로 제시하거나 설정을 자동 변경하지 않는다.

## 저장 형식과 식별자

앱의 편집 모델은 북마크의 의미와 원본 payload를 함께 유지한다. 원본은 알 수 없는 필드를 포함해 보관하고, 검증된 필드만 변경한다. 문자열 형태의 ID·Chrome 시간값을 JavaScript 숫자나 부동소수점으로 왕복하지 않는다.

- Chrome numeric ID는 모델에서 로컬·계정 저장소를 가로질러 유일하며 세션 간 저장된다. codec는 잘못되거나 중복된 ID를 다시 할당할 수 있다.
- UUID는 개별 저장소 안에서 유일하다. 로컬과 계정 전체를 합쳐서는 유일성을 보장하지 않는다. 저장소 간 이동의 충돌이나 손상 복구 등에서 변경될 수 있다.
- 따라서 연결 키를 `(profileKey, storageKind, GUID)`로 잡는 안을 검증한다. numeric ID·원본 트리 위치를 보조 증거로 보관하되 URL로 동일성을 결정하지 않는다.
- GUID 누락·중복·재생성, storage 간 이동 등 매핑을 확신할 수 없는 경우에는 자동 연결하지 않는다. 재연결/충돌로 올리고 원본 쓰기를 중단한다. 앱에서 새로 만든 항목은 임시 UUID를 쓰며 실제 ID 할당·checksum 갱신은 검증된 codec 규칙을 따른다.
- 프로필 간 복사는 새 항목이다. 서로 다른 프로필의 Chrome ID가 같아도 동일 항목으로 취급하지 않는다. 앱 내부 ID, Chrome ID, Aside 출처 라벨은 별개다.

순서 배열, 영구 루트 노드, 날짜, `meta_info`, `sync_metadata`, checksum 및 SHA256 관련 필드, 알려지지 않은 필드는 각각 보존·갱신 정책을 검증한다. 메타데이터를 그대로 복사했다는 이유만으로 의미가 유효하다고 판단하지 않는다. 특히 동기화가 외부 변경을 인지하는지는 실제 재시작·동기화 테스트가 필요하다.

| 조합 | 읽기 계획 | 쓰기 허용 조건 |
| --- | --- | --- |
| 검증된 평문 로컬 저장소 | 먼저 구현·검증 | 무변경 보존, 편집, 재시작·복원 검사 통과 |
| 평문 로컬 + 계정 저장소 | 각각 식별·표시 검증 | 전역 ID/저장소별 GUID, 복수 파일과 동기화 검증 통과 |
| 암호문 우선 또는 병행 저장 | 감지부터 검증 | 정식 접근 경로와 모든 관련 원본의 일관성을 증명하기 전 금지 |
| 관리·정책 북마크 | 발견·읽기 가능성 확인 | 초기에는 읽기 전용. 관리 출처를 보존 |
| 알 수 없는 버전·손상·식별 불명 | 오류와 작업본 보존 | 추측 쓰기 금지 |
| Ego | 직접 접근 미정 | 별도 저장 형식·버전·권한·재시작 검증 전 금지 |

검증표에는 macOS/Chrome 버전, 앱 서명·Sandbox, 프로필 경로 유형, 계정 상태, primary/secondary 파일, feature stage, 결과·증거를 남긴다. 지원 UI는 ‘읽기 가능 / 쓰기 검증됨 / 미지원’으로 구분한다.

## 3-way merge 규칙

Base는 최초 확정 원본, Ours는 사용자가 편집한 작업본, Theirs는 종료 뒤 다시 읽은 원본이다. 세 자료는 검토 중 불변으로 유지한다. 병합 결과는 별도로 생성하며 충돌 선택을 적용한 뒤 트리 불변식을 다시 검증한다.

| 상황 | 처리 제안 |
| --- | --- |
| Ours가 Base와 같음 | Theirs 유지 |
| Theirs가 Base와 같음 | Ours 반영 |
| 양쪽이 같은 필드를 같은 값으로 변경 | 한 번 반영 |
| 서로 다른 항목의 독립 변경 | 두 변경 보존 |
| 한 항목의 이름 변경과 독립적인 URL 변경 | 필드별 합성 후 유효성 검사 |
| 동일 필드의 다른 값 변경 | 충돌: 원래 값·앱 값·Chrome 값과 최종 선택 |
| 삭제 대 수정/이동, 폴더 삭제 대 하위 변경 | 충돌: 삭제 영향 범위를 명시 |
| 동일 항목을 서로 다른 부모로 이동 | 충돌. 한쪽 이동+다른 쪽 이름 변경은 가능한 경우 합성 |
| 형제 순서 변경 | index 숫자 덮어쓰기 금지. 상대 순서 제약을 병합하고 모순 시 충돌 |
| 같은 위치의 독립 추가 | 둘 다 보존. 상대 순서를 확정할 수 없으면 순서 선택 요청 |
| 부모 삭제·매핑 불명·루트/관리 노드 변경 | 임의 보정 금지. 차단 또는 명시적 해결 |

마지막 검사: 순환·고아 노드 없음, 루트 불변, ID/GUID 유효성·유일성 범위 유지, 동일 URL 복수 항목 보존, 형제 순서 결정, 지원되지 않는 저장소 이동 없음. 중복 보기와 항목 동일성은 별개의 기능이다.

## 저장·복구 경계

`편집 → 종료 대기 → 최신 읽기 → 병합 → 충돌 해결 → 검토 → 백업 → 재확인 → 교체 → 파일 검증 → 재시작/동기화 검증`

검토와 백업에 사용하는 Theirs의 raw hash, 파일 식별 정보, 지원 형식과 브라우저 프로세스 상태를 묶어 기록한다. 파일 크기·mtime만 비교하지 않는다. 저장 직전 다시 달라지면 검토 결과를 버리고 병합부터 반복한다. 외부 변경을 단순 알림으로 넘기고 덮어쓰지 않는다.

같은 디렉터리에 임시 파일을 만들고 검증한 뒤 원자적 교체하는 안을 검증한다. 권한·소유권·필요한 파일 속성도 보존한다. 백업·저널·임시 파일의 내구성, 단계별 중단과 복구를 테스트한다. 복수 파일은 rename 하나로 원자적이지 않으므로 복구 저널과 지원 조합 검증이 준비되기 전 쓰기를 허용하지 않는다.

**외부 앱인 Chrome과 OS 수준의 상호 배타적 쓰기 합의가 보장된 것은 아니다.** 체크 직후 재실행되는 race는 해시 재검사만으로 완전히 막을 수 없다. 재실행 감시·쓰기 중단·교체 뒤 재조회·백업 복구를 검증하고, 원본 안전성을 보장할 수 없으면 직접 저장을 출시하지 않는다. `NSFileCoordinator`나 Chrome의 lock 파일 하나가 상호 배제를 보장한다고 가정하지 않는다.

파일 반영 성공과 Chrome이 채택한 결과, 서버 동기화 채택은 별도 상태다. 동기화 되돌아감이 발견되면 반복 덮어쓰기하지 않고 진단과 복원 경로를 제공한다. 원본 백업·저널과 작업본은 개인 URL을 포함할 수 있으므로 외부 전송·콘솔 출력·공개 fixture에 넣지 않는다.

## 단계별 검증 제안

이 순서는 구현 제안이며 완료된 검증 목록이 아니다. 단계 통과 전 다음 단계의 실제 원본 쓰기로 넘어가지 않는다.

| 단계 | 대상과 검사 | 통과 증거 |
| --- | --- | --- |
| A. 발견·읽기 | 합성 디렉터리 → 승인된 복사본 → 격리 Chrome 프로필. 거부·취소·철회·동명 프로필·사용자 지정 경로 | 대상과 실제 트리 일치, 최소 파일 접근, 권한 거부 시 무변경 |
| B. 무변경 round-trip | 날짜/큰 ID/Unicode/동일 URL/빈 폴더/unknown metadata/checksum/계정·로컬/손상 fixture | 무변경이면 byte 그대로 유지. 파서·직렬화가 필요한 편집 경로는 의미 보존 비교와 Chrome 재읽기 확인 |
| C. 병합 fixtures | 위 규칙 각각, 양쪽 추가, 삭제·이동, 폴더 하위 변경, 반대 정렬, ID/GUID 재생성, 반복 병합 | 기대 트리/충돌 목록과 일치. 입력 불변, 순환·고아·의도치 않은 손실 없음 |
| D. 격리 Chrome 재시작 | 합성 북마크를 넣은 전용 테스트 프로필. 생성·이름·URL·이동·정렬·삭제 뒤 종료/반영/재시작 | Chrome이 표시한 의미·ID·메타데이터 비교. 재차 종료/읽기 뒤에도 유지 |
| E. 동기화·장애·복원 | 허가된 별도 테스트 계정/기기. offline→online, 서버 변경, 재실행 race, disk full, 권한 철회, 단계별 crash | 지원 조합에서 재수렴·복원 확인. 실패는 차단/복구. 실제 사용자 원본 무변경 |

동기화 테스트용 계정·기기·정상 로그인이 없으면 E는 미완료로 기록한다. 사용자의 실제 로그인 세션을 초기화하거나 사용자 프로필을 테스트 계정으로 바꾸지 않는다. UI QA의 공유 Chrome for Testing 프로필에도 북마크 저장 실험을 하지 않는다. 별도 저장소 실험은 사용자 브라우저 운영 규칙과 전용 테스트 프로필 준비를 따른다.

이번에 추가하는 `prototype.test.mjs`는 시안의 단계 제한과 선택 결과를 검사할 뿐, 위 A–E나 실제 3-way merge를 검증하지 않는다.
