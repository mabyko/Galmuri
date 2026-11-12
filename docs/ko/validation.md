> 한국어 기획 참고본 · 2026-10-23. 최신 기준은 [영문 문서](../validation.md)입니다. 새 요구 사항은 영문 기준 문서에 먼저 반영합니다.

# 기획·시안 검증 기록

2026-10-23 · 이 기록은 HTML 화면 시안에 한정한다.

## 통과

- `node --test design/prototype.test.mjs`: **8개 통과**. 프로필별 변경 분리, 동일 URL 복수 항목, 미해결 충돌과 승인 전 진행 차단, 원본 변경 시 선택·승인 무효화, 되돌리기, 추가 항목 검토, 이름·URL 동시 수정 표시.
- T3 `html_preview`: 1280px·728px·320px 편집 화면과 728px·320px 충돌 화면 렌더링 검토. 콘솔 메시지 없음. desktop은 앱 창 안에서 스크롤, 좁은 폭은 세로 재배치.
- 공유 Chrome for Testing의 **이 대화에서 만든 탭**으로 검색 결과 2개, 이름·URL 편집, 두 항목 폴더 이동을 UI 조작으로 확인.
- Chrome에서 종료 확인 예시 → 충돌 3개 선택 → 최종 검토 → 승인 → 반영 결과 → 복원 검토 → 복원 시연을 확인. 초기 충돌 미선택과 승인 전 버튼 비활성, 선택값 전달 확인.
- Chrome의 320 CSS px emulation에서 편집·종료 확인·충돌·최종 검토·백업 화면 모두 문서 가로 넘침 없음. 1280px 화면도 넘침 없음.
- 제목 포커스 이동, 폼 이름, radio/checkbox 접근성 트리, 다이얼로그의 제목·초기 포커스 확인. reduced-motion 조건에서 검사.
- 공개 시안 URL은 `example.com`·`example.org`·`example.net`과 SVG namespace뿐임을 검사. 외부 리소스 요청·스토리지 의존 없음. 실제 개인/업무 URL은 복사하지 않음.

대표적인 본문·보조 글자·주 버튼·변경 표시의 5개 명도 대비 쌍은 5.43:1 이상이었다. 전체 WCAG 감사 결과는 아니다.

공개 페이지에서 발견한 편집창 취소의 기본 submit 문제는 일반 버튼의 type을 명시해 고쳤고, 수정한 이름이 취소 후 보관되지 않는 것을 다시 확인했다.

## 도구 제한과 전환

T3 `preview_status` → `preview_open` → 로컬 시안 탐색 후 snapshot이 두 번 `Preview automation snapshot timed out after 15000ms`로 실패했다. 지침에 따라 공유 Chrome for Testing을 준비하고 Chrome DevTools MCP로 클릭·입력 검증을 계속했다. T3 `html_preview` 렌더링은 정상 동작했다.

Chrome MCP의 `/tmp` 스크린샷 저장은 workspace root 제한으로 거부됐다. 화면은 도구가 반환한 이미지로 검토했으며 파일 접근 설정을 변경하지 않았다.

## 범위 밖·남은 검증

- SwiftUI 앱·Xcode 프로젝트는 아직 없음. 네이티브 빌드·SwiftUI Preview·VoiceOver·200% 텍스트 확대·실제 창 크기 검증 전.
- 시안은 항목 단위의 고정된 충돌 예시를 생성한다. 실제 필드별/트리 순서 3-way merge 구현·fixture 검증은 하지 않았다.
- 새로고침하면 작업 초기화. 실제 파일 접근·Chrome 프로세스 감지·작업본 영속화·원본 백업·원자적 저장·복원·재시작·계정 동기화 검증 전.
- 폴더 구조 편집, 드래그앤드롭, HTML/JSON 입출력은 시안 구현 범위 밖이다. 화면 안에서 제품 예정 동작으로 표시했다.
- [공개 Orca 시안](https://share.onorca.dev/a/GmqENO9HJVQb)의 편집 시트, 수정 후 취소 시 무변경·되돌리기 비활성 유지, 종료 확인→충돌 화면 전환을 확인했다. 공개 페이지의 error/warn 콘솔 메시지 없음. 저장소를 사용하지 않으며 새로고침 시 초기화한다. 링크는 2026-11-22 만료 예정이며 로컬 HTML을 보존했다.

제품 완료 기준과 검증 단계 A–E는 [제품 기획서](product-plan.md)와 [기술 검증 계획](technical-validation.md)에 있다.
