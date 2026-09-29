# Offway

> **연차로 떠나는 로컬 여행 플래너**

![Offway — 연차로 떠나는 특별한 로컬 여행](.github/readme/hero.webp)

[![App Store에서 다운로드](https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/ko-kr)](https://apps.apple.com/app/id6793610290)

🌐 [offway.cloud](https://offway.cloud) · [이용약관](https://offway.cloud/terms) · [개인정보처리방침](https://offway.cloud/privacy) · [고객지원](https://offway.cloud/support)

🏆 **2026 관광데이터 활용 공모전** 프로젝트

국내 여행 수요가 주요 도시로 쏠리는 동안, 행정안전부가 지정한 **89개 인구감소지역**은 생활인구 유입이 절실합니다.

정부와 지자체가 숙박세일페스타, 디지털관광주민증, KTX·SRT 할인 같은 지원책을 마련했지만, 정보가 부처와 지자체마다 흩어져 있어 여행자에게 잘 닿지 않습니다.

Offway 는 **남은 연차**에 맞춰 89개 지역의 여행 코스를 완성하고, 그 여정에서 받을 수 있는 교통·숙박 혜택을 함께 연결합니다.

이 레포는 Offway **iOS 앱**(Flutter)입니다. 서버는 [team-offway/core](https://github.com/team-offway/core)에서 제공합니다.

## 프로젝트 개요

| 구분 | 내용 |
|---|---|
| 프로젝트명 | Offway (오프웨이) |
| 프로젝트 형태 | 연차 기반 로컬 여행 코스 추천 iOS 앱 |
| 참가 분야 | 2026 관광데이터 활용 공모전 |
| 주요 사용자 | 남은 연차로 짧은 국내 여행을 계획하는 직장인 |
| 핵심 목표 | 남은 연차로 실제로 다녀올 수 있는 인구감소지역 여행을 추천해, 지역 방문과 혜택 이용으로 이어지게 한다 |
| 활용 데이터 | 한국관광공사 TourAPI · 행정안전부 인구감소지역 · 국토교통부 TAGO · 기상청 등 공공데이터 |
| 서비스 현황 | App Store 출시 (iOS) |

## 서비스 소개

**여행지를 고르는 기준을 바꿨습니다.**

대부분의 여행 서비스가 '어디로 갈지'를 먼저 정한다면, Offway 는 '이번 여행에 연차를 얼마나 쓸 수 있는지'부터 봅니다. 남은 연차와 출발지, 이동수단, 여행 스타일에 맞춰 실제로 다녀올 수 있는 지역과 코스를 추천합니다.

**여행 전후의 연차까지 함께 관리합니다.**

남은 연차를 기록하고 황금연휴처럼 연차를 쓰기 좋은 시기를 알려줍니다. 여행을 다녀오면 사용한 연차를 반영해 다음 여행 계획에 다시 씁니다.

**89개 인구감소지역을 중심으로 소개합니다.**

익숙한 인기 관광지보다 인구감소지역 89곳을 중심으로 새로운 여행지를 제안합니다. 모든 코스는 **최대 2박 3일**입니다 — 콘텐츠가 얇은 지역에서 그보다 길어지면 코스가 빈약해지기 때문입니다.

## 주요 화면

**1 · 연차 기반 맞춤 여행 코스 추천**

| 연차 입력 | 홈 | 기간 스타일 | 이동수단 |
|:---:|:---:|:---:|:---:|
| <img src=".github/readme/leave-input.webp" width="180" alt="연차 입력"> | <img src=".github/readme/home.webp" width="180" alt="홈"> | <img src=".github/readme/period-style.webp" width="180" alt="기간 스타일"> | <img src=".github/readme/transport.webp" width="180" alt="이동수단"> |

**2 · 조건에 맞는 지역·코스 추천**

| 추천 계산 | 후보 지역 | 코스 추천 | 혜택 확인·저장 |
|:---:|:---:|:---:|:---:|
| <img src=".github/readme/loading.webp" width="180" alt="추천 계산"> | <img src=".github/readme/candidates.webp" width="180" alt="후보 지역"> | <img src=".github/readme/course-map.webp" width="180" alt="코스 추천"> | <img src=".github/readme/region-benefits.webp" width="180" alt="혜택 확인·저장"> |

**3 · 저장한 여행 관리·상세 정보**

| 내 코스 | 코스 상세 | 운영 정보 | 장소 상세 |
|:---:|:---:|:---:|:---:|
| <img src=".github/readme/my-courses.webp" width="180" alt="내 코스"> | <img src=".github/readme/course-detail.webp" width="180" alt="코스 상세"> | <img src=".github/readme/place-hours.webp" width="180" alt="운영 정보"> | <img src=".github/readme/place-detail.webp" width="180" alt="장소 상세"> |

**4 · 연차 사용 기록 및 관리**

| 여행 후 확인 | 내 연차 | 연차 사용 등록 | 연차 반영 |
|:---:|:---:|:---:|:---:|
| <img src=".github/readme/trip-outcome.webp" width="180" alt="여행 후 확인"> | <img src=".github/readme/my-leave.webp" width="180" alt="내 연차"> | <img src=".github/readme/leave-register.webp" width="180" alt="연차 사용 등록"> | <img src=".github/readme/leave-updated.webp" width="180" alt="연차 반영"> |

**5 · 여행 정보 탐색 및 일정 알림**

| 여행 혜택 | 지역 상세 | 관광지·혜택 | 위젯·다이나믹 아일랜드 |
|:---:|:---:|:---:|:---:|
| <img src=".github/readme/home-contents.webp" width="180" alt="여행 혜택"> | <img src=".github/readme/region-detail.webp" width="180" alt="지역 상세"> | <img src=".github/readme/region-place-benefits.webp" width="180" alt="관광지·혜택"> | <img src=".github/readme/lock-widget.webp" width="180" alt="위젯·다이나믹 아일랜드"> |

## 앱에서 신경 쓴 것

**앱을 열지 않아도 여행이 보입니다.**
홈 화면 위젯(소형·중형), 잠금화면 위젯 세 자리, 다이나믹 아일랜드에 여행까지 남은 날과 여행 중 며칠째인지가 뜹니다. 날짜가 바뀌면 앱을 켜지 않아도 알아서 넘어가고, 출발이 다가오면 서버가 잠금화면 카드를 직접 띄웁니다.

**앱이 없는 사람에게도 코스를 보여줍니다.**
코스를 카카오톡 카드·링크·이미지로 공유할 수 있습니다. 링크를 받은 사람은 앱 없이 브라우저([offway.cloud](https://offway.cloud))에서 코스를 봅니다.

**받을 수 있는 혜택을 코스 옆에 붙여 둡니다.**
숙박세일페스타·디지털관광주민증·KTX·SRT 할인처럼 부처와 지자체마다 흩어진 여행 혜택을 홈·지역·코스·장소 화면에 카드로 보여줍니다. 혜택마다 대상 지역이 정해져 있어 완도 코스와 가평 코스에 뜨는 혜택이 다르고, 카드를 누르면 신청 페이지로 바로 넘어갑니다.

**때맞춰 알려줍니다.**
여행 전날에는 내일 떠날 여행을, 여행이 끝나면 연차 차감을 확인하라고 알립니다. 알림을 누르면 그 여행으로 바로 갑니다.

**로그인은 가볍게.**
카카오·Apple·구글 계정으로 바로 시작합니다.

## 기술 스택

<img src=".github/readme/tech-stack.png" width="100%" alt="기술 스택" />

## 시스템 아키텍처

<img src=".github/readme/architecture.png" width="100%" alt="Offway iOS 앱 아키텍처" />

- **앱은 서버 하나만 봅니다.** 코스·연차·알림이 전부 [core](https://github.com/team-offway/core) API 에서 옵니다. 소셜 로그인 토큰은 서버에 넘겨 우리 JWT 로 바꿉니다.
- **위젯·잠금화면은 Swift 확장이 그립니다.** 앱은 지역과 날짜만 넘기고, 'D-3'·'내일 …'·'2일차' 같은 문구는 확장이 만듭니다. 앱을 켜지 않아도 서버가 APNs 로 잠금화면 카드를 띄우고 갱신합니다.
- **공유 링크는 앱 없이 열립니다.** 받은 사람은 브라우저에서 코스를 봅니다. 서버가 브라우저 직접 호출을 막아 두어, 웹이 같은 출처에서 서버를 대신 부릅니다.

## 데이터와 출처

코스에 들어가는 장소·이동·날씨 정보는 서버([core](https://github.com/team-offway/core))가 공공데이터를 모아 가공해 앱에 내려줍니다. 인구감소지역 **89곳 전부**에 대해 맛집·숙소·카페·관광명소·국가유산·야영장·축제 **126,873곳**을 미리 확보해 두었습니다.

| 분야 | 활용한 데이터 · API |
|---|---|
| 관광 정보 | 한국관광공사 국문 관광정보 · 연관 관광지 · 기초지자체 중심 관광지 · 관광사진 · 고캠핑 · 무장애 여행 · 반려동물 동반여행 · 관광지 집중률 예측 · 빅데이터 지역별 방문자수 |
| 장소 | 지방행정 인허가 데이터(음식점·카페·숙박업) · 국가유산청 국가유산 검색 · 전국문화축제표준데이터 |
| 이동 | 국토교통부 TAGO 열차·고속버스·시외버스·국내선박 · SK TMAP 경로·경유지 최적화 |
| 날씨 · 날짜 | 기상청 단기·중기예보 · 한국천문연구원 특일정보(공휴일) |
| 지역 | 행정안전부 인구감소지역 지정(89곳) |
| 혜택 | 정부·지자체 여행 지원 정책 — 운영진이 검증한 것만 노출 |

**출처 표기.** 앱은 화면마다 그 화면이 실제로 쓴 데이터의 기관명을 `출처: ⓒ한국관광공사 · ⓒ지방행정인허가데이터개방` 처럼 텍스트로 표기합니다. 쓰지 않은 출처가 붙지 않도록 기관명은 서버가 내려준 값만 씁니다.

전체 목록과 건수는 core 의 [데이터 풀](https://github.com/team-offway/core#데이터-풀)에 있습니다.

## 앱 구조

기능(도메인) 단위로 나눕니다. 각 기능은 `data`(API·repository) / `domain`(모델) / `application`(provider·상태) / `presentation`(화면) 층입니다. provider 는 화면 파일에 두지 않아, 기능끼리 화면을 서로 import 하지 않습니다. 모델은 코드 생성 없이 `Map<String, dynamic>` 기반입니다.

```text
lib/
├── main.dart                  # 엔트리포인트 (SDK 초기화 + ProviderScope)
├── app/app.dart               # 루트 위젯 (MaterialApp.router)
├── core/                      # 앱 전역 공통 모듈
│   ├── config/app_config.dart     # API base URL·공개 키 (--dart-define 주입)
│   ├── constants/                 # 여행 규칙 상수 (최대 2박3일 등)
│   ├── network/dio_client.dart    # Dio 프로바이더 + Auth 인터셉터
│   ├── router/app_router.dart     # GoRouter 라우트 정의
│   ├── storage/secure_storage.dart# JWT 토큰 Keychain 저장소
│   ├── theme/                     # Material 3 테마 + 디자인 토큰(tokens/)
│   ├── utils/                     # 날짜 표기·홈 인디케이터 높이 등 순수 함수
│   └── widgets/                   # 공통 위젯 (상단바·오류 화면·바텀시트·토스트 등)
├── mock/                      # 테스트 픽스처 로더 (앱 코드에서는 쓰지 않음)
└── features/                  # 기능(도메인) 단위 모듈
    ├── splash/                    # 스플래시 · 첫 화면 판정
    ├── auth/                      # 로그인 (카카오·Apple·구글)
    ├── onboarding/                # 잔여연차 입력
    ├── home/                      # 홈
    ├── region/                    # 지역 상세 · 추천 여행지 목록
    ├── course_wizard/             # 코스 추천 위저드
    ├── course/                    # 코스 확정·내 코스·공유
    ├── leave/                     # 내 연차·사용 내역
    ├── notification/              # 알림
    ├── trip_activity/             # 잠금화면·다이나믹 아일랜드 여행 D-day
    ├── update/                    # 앱 업데이트 안내
    ├── policy/                    # 여행 혜택(정부·지자체 정책)
    └── my/                        # 마이

ios/TripActivity/              # Live Activity 확장 (Swift) — 카드 그리기·문구 조립
docs/live-activity-setup.md    # Live Activity 설정 기록 · 겪은 함정
```

잠금화면·위젯은 Swift 확장(`ios/TripActivity/`)이 그립니다. Flutter 는 재료(지역·날짜)만 넘기고, **'D-3'·'내일 …'·'2일차' 같은 문구는 네이티브 한 곳**에서 만듭니다.

## 팀 소개

<table>
  <thead>
    <tr>
      <th align="center" width="33%">Client</th>
      <th align="center" width="33%">Backend</th>
      <th align="center" width="33%">Design</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center"><img src=".github/readme/team/ychany.png" width="120" /></td>
      <td align="center"><img src=".github/readme/team/sevineleven.png" width="120" /></td>
      <td align="center"><img src=".github/readme/team/yebin.png" width="120" /></td>
    </tr>
    <tr>
      <td align="center"><b>조영찬</b></td>
      <td align="center"><b>박세빈</b></td>
      <td align="center"><b>이예빈</b></td>
    </tr>
    <tr>
      <td align="center"><a href="https://github.com/ychany">@ychany</a></td>
      <td align="center"><a href="https://github.com/sevineleven">@sevineleven</a></td>
      <td align="center"><a href="https://www.behance.net/bad7ac99">Behance</a></td>
    </tr>
  </tbody>
</table>

## 개발 환경

<details>
<summary>실행 · 테스트 · 배포 · 주의사항</summary>

### 실행

**Flutter 3.38.4 (stable)** 기준입니다. CI 도 같은 버전으로 검사합니다.

배포 서버가 임시 Basic 게이트 뒤에 있어 계정 없이 부르면 전부 401이 납니다. 먼저 `env.json.example`을 복사해 `env.json`을 만들고 백엔드에게 받은 계정을 넣습니다. **gitignore 대상이라 커밋하지 않습니다.**

```bash
# 배포 서버 접속 (기본)
flutter run --dart-define-from-file=env.json

# 주소만 따로 지정할 때 (로컬 백엔드 등)
flutter run --dart-define=API_BASE_URL=http://localhost:8080

# 특정 화면부터 시작 (개발용)
flutter run --dart-define=INITIAL_ROUTE=/wizard/calendar
```

실기기에 **설치해서 단독으로 켤** 때는 `flutter build ios --profile` 로 빌드합니다. `--debug` 는 Dart 코드를 Mac 의 Flutter 툴에서 받아오므로 `flutter run` 이나 Xcode 없이 홈 화면에서 열면 곧바로 죽습니다.

### 웹 (offway.cloud)

공유 링크를 받은 사람이 **앱 없이 브라우저에서** 코스를 보는 페이지와, 심사에 필요한 법적 문서를 함께 배포합니다. Vercel 프로젝트의 Root Directory는 `web/share`입니다.

| 주소 | 내용 |
|---|---|
| `/` | 서비스 소개 랜딩 |
| `/r/{token}` | 추천코스 공유 — 담기 전 코스를 공유한 링크 |
| `/m/{token}` | 내 코스 공유 — 담아둔 코스 (여행 날짜·사용 연차·D-DAY) |
| `/privacy` · `/terms` | 개인정보처리방침 · 이용약관 (한국어·영문) |
| `/support` | 고객지원 — 자주 묻는 질문 · 문의 메일 |

백엔드(`https://api.offway.cloud`)가 브라우저 직접 호출에 CORS를 열어 주지 않으므로, `web/share/api/*.js`가 같은 출처에서 받아 대신 부릅니다.

### 테스트 / 린트

```bash
flutter test        # 위젯·단위 테스트
flutter analyze
dart format .

# 네이티브(Swift) — 잠금화면 문구 규칙 · 서버 content-state 계약
# (먼저 flutter build ios --simulator 로 Flutter 프레임워크를 만들어 둔다)
cd ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RunnerTests
```

PR마다 GitHub Actions가 포맷·분석·테스트를 검사하며, 통과해야 머지할 수 있습니다. `main` 직접 푸시는 브랜치 보호로 차단되어 있습니다.

### 비고

- 번들 ID: `com.nth.offway` · App Store 등록명: **[Offway - 연차로 떠나는 로컬 여행](https://apps.apple.com/app/id6793610290)**
- iOS 최소 버전은 **15.0**, Live Activity 확장만 **16.1** 입니다. 15.x 기기는 앱은 정상이고 잠금화면 카드만 없습니다 — 그 기기들은 다이나믹 아일랜드 하드웨어가 없어 앱 버전을 올려도 얻는 것이 없습니다. 확장 설정과 겪은 함정은 `docs/live-activity-setup.md`
- Xcode 작업 시 `ios/Runner.xcworkspace`를 엽니다 (`.xcodeproj` 아님)
- **실기기 ↔ 시뮬레이터를 오가거나 `flutter build ipa` 전에는 `flutter clean`** 을 먼저 합니다. Flutter 3.38 이 `objective_c.framework`(Dart 네이티브 에셋)를 마지막에 빌드한 플랫폼용으로 남겨, IPA 업로드가 거절되거나 사진 캐시가 죽습니다. `build/native_assets` 만 지우면 프레임워크가 빠진 채 빌드되니 반드시 `clean` 으로 합니다
- 실기기 설치가 `0xe8008014`(objective_c.framework 서명 불일치)로 실패하는 것도 같은 Flutter 3.38 버그입니다. Runner 타깃 마지막의 **Sign Native Asset Frameworks** 단계가 ad-hoc 프레임워크를 앱 서명으로 다시 서명해 우회하니 지우지 않습니다. Flutter 가 고쳐지면 아무것도 하지 않고 지나갑니다
- 카카오 앱 키를 바꿀 때는 `ios/Flutter/AppKeys.xcconfig`(URL scheme)와 `AppConfig`(SDK 초기화) **두 곳을 함께** 수정해야 합니다. 한쪽만 바꾸면 카카오톡에서 앱으로 복귀하지 못합니다
- 레포가 **public**이므로 시크릿은 어떤 형태로도 커밋하지 않습니다 (카카오 REST API 키·Admin 키·클라이언트 시크릿, Apple `.p8`·APNs 키, 네이버 지도 Client Secret 등 — 서버가 쓰는 값은 백엔드 환경변수로만 관리)
- 예외적으로 **제공자가 공개 식별자로 명시했고 콘솔에서 번들 ID(`com.nth.offway`) 제한이 걸린 값**만 포함되어 있습니다: 네이버 지도 Client ID, 카카오 네이티브 앱 키, 구글 `REVERSED_CLIENT_ID`. 그 외 값은 `--dart-define`으로 주입합니다

### 출시

App Store 정식 출시 2026-08-27 (v1.0.0). 사전 배포와 검증은 TestFlight 로 합니다.

</details>
