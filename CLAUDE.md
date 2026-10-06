# offway-client

**Offway** — 남은 연차로 갈 수 있는 인구감소지역 여행 코스를 추천하는 iOS 앱 (Flutter).

## 서비스 개요

- **문제**: 연차는 남았는데 어디로 갈지 정하기 어렵다. 인구감소지역은 좋은 콘텐츠가 있어도 잘 알려지지 않는다.
- **해법**: 남은 연차·이동수단·일정 취향을 입력하면 **도달 가능한 인구감소지역**과 **날짜별 코스**를 추천한다.
- **핵심 플로우**: 로그인 → 잔여연차 입력 → 홈 → 코스 위저드(날짜/기간스타일 → 이동수단 → 일정밀도) → 로딩 → 후보지역 → 코스 확정
- **핵심 정책**: 모든 코스는 **최대 2박3일** (`kMaxTripSpanDays`). 콘텐츠가 얇은 지역에서 4일 이상 코스는 빈약해지기 때문
- **데이터 출처**: 한국관광공사 TourAPI(KorService2 + 연관관광지), 행안부 인구감소지역 89곳

## 연동 대상

| 대상 | 내용 |
|---|---|
| **백엔드** | [github.com/team-offway/core](https://github.com/team-offway/core) — Java Spring, 기본 브랜치 **`dev`**. 로컬 기본 주소 `http://localhost:8080` |
| **인증** | 소셜 로그인(카카오·Apple·구글) 액세스 토큰을 **JSON 바디**로 `POST /api/v1/auth/callback/{provider}` 전달 → 서버가 우리 JWT 발급 |
| **응답 규격** | 모든 API가 공통 래퍼 `{status, data, detail, code}` 로 감싸짐 — `data`를 꺼내 사용 |
| **지도** | 네이버 지도 SDK (Dynamic Map). 키 취급은 아래 [주의사항](#주의사항) 참고 |

## 개발 명령어

```bash
flutter run                                          # 실행 (기기 선택: -d <device-id>)
flutter run --dart-define-from-file=env.json         # 배포 서버 접속 (권장)
# env.json은 env.json.example을 복사해 만든다 (Basic 계정 포함, gitignore 대상 — 커밋 금지)
# 서버는 임시 Basic 게이트(#122) 뒤에 있어 계정 없이 부르면 전부 401이 뜬다
flutter run --dart-define=API_BASE_URL=<url>         # 주소만 따로 지정할 때 (로컬 백엔드 등)
flutter run --dart-define=INITIAL_ROUTE=/wizard/calendar  # 특정 화면부터 시작 (개발용)
flutter analyze                                      # 정적 분석
flutter test                                         # 테스트
dart format .                                        # 포맷
```

## 구조

```text
lib/
├── main.dart                  # 엔트리포인트 (SDK 초기화 + ProviderScope)
├── app/app.dart               # 루트 위젯 (MaterialApp.router)
├── core/                      # 전역 공통 모듈
│   ├── config/app_config.dart     # API base URL·공개 키 (--dart-define 주입)
│   ├── constants/                 # 여행 규칙 상수 (kMaxTripSpanDays 등)
│   ├── network/                   # Dio 프로바이더·JWT Auth 인터셉터·ApiEnvelope(guard)·자동 재시도 규칙
│   ├── router/app_router.dart     # GoRouter 라우트 정의
│   ├── storage/secure_storage.dart# 토큰 Keychain 저장소
│   ├── theme/                     # Material 3 테마 + 디자인 토큰(tokens/)
│   ├── utils/                     # 날짜 표기(date_format)·로그(logDebug) 등 순수 함수
│   └── widgets/                   # 공통 위젯 — 아래 표 참고
├── mock/mock_data_source.dart # 테스트 픽스처 로더 (assets/mock/*.json) — 앱 코드는 안 씀
└── features/
    ├── splash/                # 스플래시 · 첫 화면 판정
    ├── auth/                  # O-01 로그인 (카카오·Apple·구글)
    ├── onboarding/            # O-02 잔여연차 입력
    ├── home/                  # O-03 홈
    ├── region/                # 지역 상세 · 추천 여행지 목록
    ├── course_wizard/         # O-04~O-08 코스 추천 위저드 (출발지·랜덤 지역 포함)
    ├── course/                # O-09 코스 확정 (네이버 지도) · 내 코스 · 공유
    ├── leave/                 # 내 연차 · 사용 내역 · 연차 쓰기 좋은 날
    ├── policy/                # 여행 혜택(정부·지자체 정책) 뱃지·카드·시트
    ├── notification/          # 알림 목록 · 푸시
    ├── trip_activity/         # 잠금화면·위젯·다이나믹 아일랜드 연동
    ├── update/                # 앱 업데이트 안내
    └── my/                    # 마이 · 회원탈퇴
```

- 상태관리: flutter_riverpod 3 / 라우팅: go_router / HTTP: dio
- 새 기능은 `features/<기능명>/` 아래 `data`(API·repository) · `domain`(모델) · `application`(provider·상태) · `presentation`(화면) 구조로 추가
  - **provider 는 화면 파일에 두지 않는다** — `application/`(또는 `data/`)에 둔다. 다른 기능이 화면 파일을 import 하게 되고 순환이 생긴다(#366)
  - repository 메서드는 `ApiEnvelope.guard(() async { … })` 로 감싸 Dio 예외를 `ApiException` 으로 바꾼다
- **위저드 상태**: `course_wizard/application/course_wizard_provider.dart`의 `CourseWizardDraft` 하나에 단계별 조건(날짜·기간스타일·이동수단·밀도)을 누적한다

## 작업 방식

### Figma MCP로 화면 구현

와이어프레임·디자인은 Figma MCP로 읽어서 구현한다.

- 사용자가 Figma 노드 URL을 주면 `get_design_context`(상세) 또는 `get_screenshot`(변형·상태 확인)으로 읽는다
- 반환되는 React+Tailwind 코드는 **참고용** — Flutter 위젯으로 변환하고 프로젝트 컨벤션을 따른다
- **에셋(SVG·이미지)은 URL이 7일 후 만료**되므로 즉시 `assets/`로 다운로드해 커밋한다
- 색상은 화면 내 상수로 두고 `TODO(디자인시스템)` 주석을 남긴다 — 디자인 확정 시 일괄 교체
- **뒤로가기·닫기·스텝 인디케이터 등 당연한 내비게이션은 지시 없이 알아서 연결**한다. 아직 없는 화면으로의 이동만 TODO로 남긴다
- 구현 후 시뮬레이터로 실행해 디자인과 대조한다

### 디자인 QA 고칠 때 (중요)

**공통 컴포넌트를 고치기 전에, 그 화면이 정말 그걸 쓰는지 먼저 확인한다.**

`lib/core/widgets/`에 공통 위젯이 있어도 화면이 Material 기본 위젯을 직접 쓰는 경우가 많다. 공통 파일만 고치고 "반영됐다"고 하면 화면은 그대로다 — 실기기 리로드 문제로 오해하며 시간을 버린다.

```bash
# ① 그 화면의 실제 호출부를 먼저 읽는다 (grep 으로 사용처 목록만 보고 단정하지 말 것)
grep -n "showDialog\|AlertDialog\|showModalBottomSheet" lib/features/<기능>/presentation/<화면>.dart

# ② 공통 위젯을 안 쓰고 있으면, 공통으로 옮기는 것부터 한다
```

의심되면 임시로 진단 코드(빨간 글씨 등)를 심어 **그 코드가 실행되는 경로인지** 먼저 확인한다. 화면에 안 보이면 엉뚱한 파일을 고치고 있는 것이다.

현재 공통으로 묶인 것 — 새로 만들지 말고 이걸 쓴다:

| 대상 | 공통 API | 금지 |
|---|---|---|
| 확인 모달 | `showAppConfirmDialog` | `AlertDialog` 직접 생성 |
| 바텀시트 | `showAppBottomSheet` | `showModalBottomSheet` 직접 호출 |
| 시트 제목 바 | `AppSheetTitleBar` | `height: 56` + `Stack` 직접 조립 |
| 닫기 버튼 | `AppIconButton.close` | `Icons.close` 직접 사용 |
| 화면 상단바(가운데 제목+뒤로가기) | `AppTitleBar` | `SizedBox(44)` + `Stack` + `Positioned(AppBackButton)` 직접 조립 |
| 상단바 SVG 아이콘 버튼 | `AppSvgIconButton` | 44×44 `GestureDetector` + `SvgPicture` 직접 조립 |
| 화면을 못 그릴 때 오류 | `AppErrorView` (+ `whenRetryable`·`retryFailureToast`) | 재시도 없는 `Center(Text(e.detail))` |
| 카테고리 칩 줄 | `CategoryChipRow` (`features/region/presentation/widgets/category_chip.dart`) | `CategoryChip` 을 `Row` 로 직접 나열 |

### 시안 치수 실측

- **Figma 좌표(`get_metadata`)를 우선**한다. 스크린샷 픽셀 측정은 잉크 기준이라 텍스트 박스·여백과 어긋난다
- Figma의 `gap`이 눈에 보이는 간격과 다를 수 있다 — 자식이 `inset` 음수로 밖으로 넘치거나 `flex-wrap`의 `gap-y`인 경우
- **시안 서체는 Pretendard JP, 앱은 Pretendard**로 글자 폭이 다르다. 폭을 고정값으로 박으면 글자가 잘리거나 부푼다 (`취소` 27.8 / `삭제하기` 55.7 / `탈퇴할게요` 69.6)
- 위젯 테스트는 기본 서체가 **Ahem**(모든 글자 1em 정사각형)이다. 폭·줄바꿈을 재려면 `test/flutter_test_config.dart`가 실은 Pretendard가 필요하고, **`MaterialApp(theme: AppTheme.light)`를 함께 줘야** 적용된다 (타이포 토큰은 `fontFamily`를 비워두고 테마에서 지정하므로)

### 개발일지

`devlog/_template.html` 템플릿을 복사해 `devlog/offway-devlog-MMDD.html` 로 작성한다 (한 화면 가로형 HTML, 팀에 파일째 공유). `devlog/`는 gitignore 대상 — 커밋하지 않는다.

- 구성: 헤더(워드마크+한줄요약+날짜) → 스탯 4개 → **오늘 한 일** 카드 3~4개 → **다음 예상 할 일** 4칸
- 시간순 나열 대신 **주제별**로. 팀원(백엔드·디자이너)이 읽으므로 구현 용어보다 결과·판단 근거 위주
- 상대가 알아야 할 제약은 `<strong>` 강조

## 워크플로우 (필수 준수)

- **main 직접 푸시 금지** — 브랜치 보호로 차단되어 있음. 항상 브랜치에서 작업
- **커밋·PR 생성·머지 모두 사용자가 명시적으로 요청할 때만** — 파일 수정까지만 알아서 하고, git 조작은 지시를 기다릴 것
- **머지는 사용자 확인 후에만**
- **커밋 메시지·PR 본문에 Claude 관련 문구(Co-Authored-By 등) 절대 금지**
- 커밋 메시지는 한국어, conventional commit 접두어 사용 (feat/fix/chore/ci 등)
- CI(GitHub Actions)가 PR마다 포맷·분석·테스트 검사, 통과해야 머지 가능

## 주의사항

- **코드 생성(freezed·json_serializable·build_runner)은 쓰지 않는다** — 모델이 전부 `Map<String, dynamic>` 기반이라 2026-08-25에 의존성째 걷어냈다. 다시 들이려면 리포지토리 계층부터 모델로 바꾸는 결정이 먼저다. `riverpod_lint`는 미도입(예전엔 freezed 3.x와 충돌해 못 넣었고, 지금은 그 제약이 없다)
- 번들 ID: `com.nth.offway`, 서명 팀: `AWV8LRP46J` (유료 Apple Developer)
- Xcode 작업 시 `ios/Runner.xcworkspace`를 열 것 (`.xcodeproj` 아님)
- 레포가 **public**이므로 시크릿·인증서·키스토어 등 민감 파일 커밋 금지
  - **원칙**: 비밀값은 어떤 형태로도 커밋하지 않는다. 서버가 쓰는 값은 백엔드 환경변수로만 관리한다
  - **금지**: 카카오 REST API 키·Admin 키·클라이언트 시크릿, Apple `.p8`·APNs 키, 네이버 지도 Client Secret
  - **예외** — 아래 두 조건을 **모두** 만족하는 값만 커밋한다. 하나라도 불확실하면 커밋하지 않고 `--dart-define`으로 주입한다
    1. 제공자가 **클라이언트에 내장되는 공개 식별자**로 문서에 명시한 값일 것 (앱 바이너리에서 추출 가능하므로 은닉이 성립하지 않는 값)
    2. 제공자 콘솔에서 **번들 ID(`com.nth.offway`) 제한이 걸려 있어** 타 앱에서 재사용할 수 없을 것
  - 현재 예외로 커밋된 값: 네이버 지도 Client ID, 카카오 **네이티브** 앱 키, 구글 `REVERSED_CLIENT_ID`(`ios/Flutter/AppKeys.xcconfig`) (모두 위 조건 충족 확인)
- **카카오 앱 키를 바꿀 때**는 `ios/Flutter/AppKeys.xcconfig`(URL scheme)와 `AppConfig`(SDK 초기화) **두 곳을 함께** 수정해야 한다. 한쪽만 바꾸면 카카오톡에서 앱으로 복귀하지 못한다
- 위젯 테스트는 실제 SDK를 호출하지 않는다 — 로그인은 `googleAuthServiceProvider` 를 가짜 서비스로 바꿔 끼워(`test/widget_test.dart` 의 `_FakeGoogleAuthService`) 구글 버튼으로 플로우에 진입한다
