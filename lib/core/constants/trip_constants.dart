/// 여행 코스 관련 전역 정책 상수.
///
/// 콘텐츠가 얇은 인구감소지역에서 4일 이상 코스는 빈약해지므로
/// 모든 코스는 최대 2박3일로 제한한다 (= 가는날~오는날 간격 최대 2일).
const int kMaxTripSpanDays = 2;

/// 후보지역 추천의 편도 도달 한계(분) — **폴백 값이다.**
///
/// 평소에는 가용시간 계산(서버)이 일정 길이로 한계를 정해 준다 — 당일치기
/// 2시간 · 1박2일 3시간 · 2박3일 4시간, 반차로 떠나면 첫날은 더 짧다
/// (core `AvailableTime`, #290). 그 계산이 실패했을 때만 이 값을 보낸다.
/// 서버 등급의 최대(4시간)보다 넓어, 폴백일 때는 거리로 거의 거르지 않는다
const int kMaxReachMinutes = 420;

/// 두 날짜의 달력상 일수 차이.
///
/// `DateTime.difference().inDays`는 경과 시간을 24로 나누므로, 서머타임이 있는
/// 지역에서는 자정끼리도 23·25시간 차가 나 3일 차이가 2일로 계산될 수 있다.
/// 연·월·일만 UTC로 옮겨 비교해 그런 어긋남을 없앤다.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// [from]~[to] 사이에서 연차를 써야 하는 날 수 (양 끝 포함).
///
/// 주말은 원래 쉬는 날이라 연차가 깎이지 않으므로 평일만 센다.
/// [holidays]를 주면 공휴일(자정 기준 날짜 집합, `GET /holidays` — core #322)도
/// 함께 거른다 — 광복절·추석이 낀 주를 주말만 빼고 세면 차감일이 실제보다
/// 많아진다. 못 받아 비워 두면 예전처럼 주말만 거른 근사값이 된다.
int leaveDaysBetween(
  DateTime from,
  DateTime to, {
  Set<DateTime> holidays = const {},
}) {
  var count = 0;
  for (var d = 0; d <= calendarDaysBetween(from, to); d++) {
    final day = DateTime(from.year, from.month, from.day + d);
    if (day.weekday != DateTime.saturday &&
        day.weekday != DateTime.sunday &&
        !holidays.contains(day)) {
      count++;
    }
  }
  return count;
}

/// 캘린더 날짜 탭을 가는날/오는날 범위로 해석한다.
/// 시작일 없음 → 시작일 지정 / 시작일만 있음 → 범위 확정([kMaxTripSpanDays]박 이내) 또는 재시작.
/// 위저드와 저장한 코스 일정 지정이 같은 규칙을 쓰도록 한 곳에 둔다.
({DateTime? start, DateTime? end}) resolveTripDateTap({
  required DateTime day,
  required DateTime? start,
  required DateTime? end,
}) {
  if (start == null || end != null) {
    // 새 선택 시작 (기존 범위가 있으면 리셋)
    return (start: day, end: null);
  }
  final diff = calendarDaysBetween(start, day);
  if (diff < 0 || diff > kMaxTripSpanDays) {
    // 시작일 이전이거나 상한 초과 → 해당 날짜로 다시 시작
    return (start: day, end: null);
  }
  // 범위 확정 (같은 날 = 당일치기)
  return (start: start, end: day);
}
