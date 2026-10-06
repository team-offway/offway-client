# 코스 공유 웹페이지

앱에서 공유한 링크를 열면 보이는 **보기 전용** 페이지입니다.
어디서 공유했는지에 따라 화면이 갈립니다 — 추천코스는 `/r/{token}`,
내 코스는 `/m/{token}`.
계정이 없는 사람도 코스를 볼 수 있어야 해서, 인증 없는 공개 API만 씁니다.

빌드 도구도, 의존성도 없습니다.

| 파일 | 하는 일 |
|---|---|
| `index.html` | 서비스 소개 랜딩 |
| `recommend.html` | 추천코스 공유 화면 (`/r/{token}`) |
| `mycourse.html` | 내 코스 공유 화면 (`/m/{token}`) — 날짜·연차가 붙는다 |
| `privacy.html` · `terms.html` · `support.html` | 개인정보처리방침 · 이용약관 · 고객지원 (한국어·영문) |
| `api/page.js` | `/r/`·`/m/` 주소를 받아 **og:title 에 지역 이름을 채운** HTML 을 낸다 — 카톡 미리보기용 |
| `api/course.js` | 코스를 읽어 오는 통로 (아래 참고) |
| `api/leave.js` | 사용 연차를 계산해 오는 통로 |
| `api/curated.js` | 랜딩 캐러셀이 홈의 큐레이션 링크를 받아 오는 통로 |
| `vercel.json` | 주소를 각 페이지로 넘긴다 |

## 왜 API를 직접 안 부르나

백엔드(`https://api.offway.cloud`)가 이 도메인의 브라우저 직접 호출에 CORS 를
열어 주지 않아, 페이지가 직접 부르면 막힌다. 같은 출처의 서버리스 함수
`api/course.js`·`api/leave.js`·`api/curated.js` 가 대신 받아 넘기고, 응답 캐싱도 얹는다.

- `GET /api/v1/public/courses/{shareToken}` 은 **인증 불필요** (Basic 게이트 예외)
- 연차 계산·홈 API 는 게이트 뒤라 `api/leave.js`·`api/curated.js` 가 Vercel 환경변수의 자격을 붙여 부른다
- 서버 주소를 바꿔야 하면 Vercel 환경변수 `API_ORIGIN` 을 쓴다

## 미리보기(og) 에 지역 이름이 들어가는 이유

카톡·슬랙은 JS 를 안 돌리고 HTML 만 읽는다. 그래서 `/r/{token}`·`/m/{token}` 은
정적 파일이 아니라 `api/page.js` 가 받는다 — 코스를 읽어 `og:title` 을
"Offway 정선 추천코스" 로 바꾼 HTML 을 내려주고, 화면의 나머지는 지금처럼
브라우저가 `/api/course` 로 채운다. 코스를 못 읽으면 지역 없이 그대로 낸다.
`vercel.json` 의 `includeFiles` 가 있어야 함수가 HTML 파일을 읽을 수 있다.

## 배포 방법

별도 레포를 만들 필요는 없다 — Vercel이 모노레포의 하위 폴더를 루트로 지정해 배포한다.

1. [vercel.com](https://vercel.com) → **Add New Project** → `offway-client` 선택 (2026-10 에 `offway-frontend` 에서 이름을 바꿨다)
2. **Root Directory**: `web/share`
3. **Framework Preset**: Other (빌드 명령 없음)
4. **Project Name**: 원하는 이름 (현재 `offway-frontend` — 레포 이름을 바꿔도 Vercel 프로젝트 이름은 그대로다)
5. 도메인은 Settings → Domains 에서 붙인다 — 현재 `offway.cloud`
6. Deploy

Flutter 코드만 바꿔도 재배포가 도는 게 신경 쓰이면,
Settings → Git → **Ignored Build Step** 에 아래를 넣는다.

```bash
git diff --quiet HEAD^ HEAD -- .
```

## 앱이 만드는 링크 주소

앱의 공유 링크 기본값은 이미 `https://offway.cloud` 다(`lib/core/config/app_config.dart` 의 `shareBaseUrl`). 다른 주소로 시험할 때만 `--dart-define=SHARE_BASE_URL=<주소>` 로 바꾼다.

## 알아둘 점

- 응답에 코스 이름이 없어 **첫 장소의 `regionName`** 으로 제목을 만든다
