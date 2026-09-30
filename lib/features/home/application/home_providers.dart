import 'dart:async';
// 홈 화면의 데이터·규칙 — 화면 파일 밖에 두어 다른 기능이 화면을 import 하지 않게 한다(#366).

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/home_repository.dart';
import '../../../core/network/image_cache.dart';

/// 홈 API 한 번으로 사용자·추천지역을 함께 받는다.
/// 온보딩에서 연차를 저장한 뒤에는 invalidate로 다시 불러온다.
final homeSnapshotProvider = FutureProvider<HomeSnapshot>(
  (ref) => ref.watch(homeRepositoryProvider).fetch(),
);

/// 다른 화면(마이·기간스타일)도 읽는 사용자 정보 — 이름을 유지해 결합을 끊지 않는다
final homeUserProvider = FutureProvider<Map<String, dynamic>>(
  (ref) async => (await ref.watch(homeSnapshotProvider.future)).user,
);

/// '이번 연차엔 여기 어때요?' — 지역 카드
final homeRegionsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async => (await ref.watch(homeSnapshotProvider.future)).regions,
);

/// '이번달 추천 여행지' — 장소 카드 (core #305).
/// 배치가 채우기 전에는 비어 온다 — 그때는 섹션을 통째로 접는다
final homePlacesProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async => (await ref.watch(homeSnapshotProvider.future)).places,
);

/// 잔여 연차가 없어 온보딩(연차 입력)으로 보내야 하는가.
///
/// **다 읽힌 값에서만 판단한다.** 재조회(invalidate) 중에는 Riverpod이
/// 이전 값을 `.value`에 남겨두는데, 로그아웃 직후에는 그 자리에 게스트
/// (연차 null)가 있다 — 그걸 보고 보내면 재로그인한 회원이 이미 등록한
/// 연차를 두고도 온보딩으로 끌려간다 (#132).
///
/// 못 읽었거나 실패한 것도 '연차가 없다'와 다르다 — 홈은 그대로 두고
/// 다음 조회를 기다린다.
bool leaveOnboardingNeeded(AsyncValue<Map<String, dynamic>> user) {
  if (user.isLoading) return false;
  final data = user.value;
  return data != null && data['remainingLeaveDays'] == null;
}

/// '전체'에서 앞자리 수 — 이만큼은 관광지(`SIGHT`)·체험(`EXPERIENCE`)을
/// 번갈아 채우고 그 뒤부터는 원래 순서다.
///
/// 첫 화면에 숙소·식당이 먼저 깔리면 "어디 가 볼까"의 답이 안 된다. 갈 곳을
/// 먼저 보여주고 묵을 곳·먹을 곳은 뒤로 보낸다. 서버 종류 키로 가른다 —
/// 한글 라벨은 서버가 바꿀 수 있다
const homeFeaturedCount = 8;

/// 홈 '이번달 추천 여행지'에 보여줄 장소 카드.
///
/// 칩으로 거른 뒤, **'전체'일 때는 한 줄 소개가 있는 장소만** 남긴다 —
/// 첫 화면에서 소개 없는 카드가 섞이면 줄이 들쭉날쭉해 성기게 보인다.
/// 카테고리를 고르면 그 갈래는 소개가 없어도 전부 보여준다(고른 사람은
/// 그 갈래를 다 보고 싶은 것이고, 숙박·음식은 소개가 늦게 채워진다).
///
/// '전체'는 그 위에 **앞 [homeFeaturedCount]장을 관광지·체험으로** 번갈아
/// 세운다. 각 갈래 안의 차례는 그대로고, 나머지는 원래 차례대로 뒤에 둔다.
///
/// 그 앞에 두 규칙이 더 걸린다 — 혜택이 붙은 장소를 앞세우고([_hasBenefit]),
/// [homePinnedPlaceNames]에 적은 곳은 무조건 맨 앞으로 끌어온다
List<Map<String, dynamic>> homePlacesForChip(
  List<Map<String, dynamic>> places,
  Map<String, dynamic>? selected,
) {
  final isAll = selected == null || selected['key'] == 'ALL';
  if (!isAll) {
    return places.where((p) {
      final counts = p['categoryCounts'] as Map<String, dynamic>?;
      return (counts?[selected['label']] as int? ?? 0) > 0;
    }).toList();
  }
  final described = places
      .where((p) => (p['description'] as String?)?.isNotEmpty ?? false)
      .toList();
  // 혜택이 붙은 장소를 앞세운다 — 뱃지가 있는 카드가 먼저 보여야 '연차 내고
  // 갈 만한 곳'으로 읽힌다. 각 무리 안의 차례는 그대로다(서버 추천 순)
  final withBenefit = described.where(_hasBenefit).toList();
  final withoutBenefit = described.where((p) => !_hasBenefit(p)).toList();
  final ordered = [...withBenefit, ...withoutBenefit];

  final sights = ordered.where((p) => p['kind'] == 'SIGHT').toList();
  final experiences = ordered.where((p) => p['kind'] == 'EXPERIENCE').toList();
  final featured = <Map<String, dynamic>>[];
  for (var i = 0; featured.length < homeFeaturedCount; i++) {
    final s = i < sights.length ? sights[i] : null;
    final e = i < experiences.length ? experiences[i] : null;
    if (s == null && e == null) break;
    if (s != null) featured.add(s);
    if (e != null && featured.length < homeFeaturedCount) featured.add(e);
  }
  if (featured.isEmpty) return _pinnedFirst(described);
  final rest = ordered.where((p) => !featured.contains(p)).toList();
  return _pinnedFirst([...featured, ...rest]);
}

/// 혜택 뱃지가 붙는가.
///
/// 서버는 장소마다 혜택을 **객체 하나**로 준다(`{text, policyType, …}`) —
/// 배열이 아니라 개수를 셀 것이 없다. 붙었는지만 본다. 나중에 여러 개를
/// 주게 되면 여기서 길이로 견주면 된다
bool _hasBenefit(Map<String, dynamic> place) => place['benefit'] != null;

/// '전체'에서 무조건 맨 앞에 세우는 장소 — 손으로 고른 값이다.
///
/// 사진이 좋아 첫 화면에 어울리는 곳들이다. 서버는 이걸 가릴 분류를 주지
/// 않는다(`kind` 넷뿐이고 `contentTypeId`는 홈 응답에 없다). 자연을 가려낼
/// 코드가 생기면 통째로 걷어낸다.
///
/// **이름으로 맞춘다** — 장소 id(`poiContentId`)는 수집을 다시 돌리면
/// 바뀔 수 있지만 이름은 화면에 그대로 뜨는 값이라 눈으로 확인된다.
/// 서버 목록에서 사라지면 그 줄만 조용히 힘을 잃는다.
///
/// **매달 바뀌는 값이라 다음 달에도 확인이 필요하다.** '이번달 추천
/// 여행지'는 이름 그대로 달마다 갈린다 — 여기 적힌 세 곳이 다음 달
/// 목록에 없으면 아무 일도 일어나지 않고([_pinnedFirst]가 건너뛴다),
/// 그러면 첫 화면은 다시 서버 차례대로 깔린다. 홈을 눈으로 보고 이
/// 목록을 손보는 일이 매달 한 번 필요하다
const homePinnedPlaceNames = ['송도 구름산책로', '연미산 자연미술공원', '부산 중앙공원'];

/// [homePinnedPlaceNames]에 있는 장소를 적은 순서대로 맨 앞으로 끌어온다.
///
/// 목록에 없는 이름은 건너뛰고, 나머지는 들어온 차례 그대로 뒤에 붙는다 —
/// 셋 다 없으면 입력이 그대로 나간다
List<Map<String, dynamic>> _pinnedFirst(List<Map<String, dynamic>> places) {
  final pinned = <Map<String, dynamic>>[];
  for (final name in homePinnedPlaceNames) {
    final found = places.where((p) => p['placeName'] == name).firstOrNull;
    if (found != null) pinned.add(found);
  }
  if (pinned.isEmpty) return places;
  final rest = places.where((p) => !pinned.contains(p)).toList();
  return [...pinned, ...rest];
}

/// 당겨서 새로고침한 뒤 카드 순서를 섞는다.
///
/// 서버는 같은 순서로 답하므로 다시 읽어도 첫 화면이 그대로다 — 당겼는데
/// 아무것도 안 바뀌면 새로고침이 된 건지 알 수 없다. 순서만 섞고 내용은
/// 그대로 둔다. [seed]가 null이면(아직 안 당겼으면) 서버 순서 그대로다.
/// 씨앗을 받는 이유는 같은 씨앗이면 같은 순서라 테스트가 재현되기 때문이다.
List<Map<String, dynamic>> shuffledForRefresh(
  List<Map<String, dynamic>> cards,
  int? seed,
) {
  if (seed == null) return cards;
  return List.of(cards)..shuffle(Random(seed));
}

/// 홈 '이번달 추천 여행지' 줄에서 **처음 보일** 카드의 사진 주소 — 앞 [count]장.
///
/// 스플래시 동안 홈 데이터를 받자마자 이 사진부터 디스크 캐시에 받아 둔다
/// (`OffwayApp`). 홈이 그려질 때 첫 화면 사진이 이미 와 있거나 받는 중이다.
/// 화면과 같은 규칙으로 고른다 — 장소 카드가 있으면 '전체' 기준
/// [homePlacesForChip], 없으면(배치 전) 지역 카드다
List<String> homeFirstImageUrls(HomeSnapshot snapshot, {int count = 5}) {
  final cards = snapshot.places.isNotEmpty
      ? homePlacesForChip(snapshot.places, null)
      : snapshot.regions;
  return [
    for (final card in cards.take(count))
      if (card['imageUrl'] case final String url when url.isNotEmpty) url,
  ];
}

/// 홈 '이번 연차엔 여기 어때요?' 에 놓는 지역 카드 수의 상한 — 서버가 더
/// 많이 줘도 앞에서 이만큼만 쓴다(시안: 3~7장)
const homeLeavePickMax = 7;

/// 첫 화면 **아래** 섹션의 사진 주소 — '이번 연차엔 여기 어때요?' 지역 카드와
/// '연차 쓰기 전, 확인해보세요' 링크 카드.
///
/// 처음 쓰는 사람이 스크롤을 내리면 이 사진들이 비어 있다가 떴다 — 그때 위
/// 줄의 나머지 사진도 받는 중이라 더 늦었다. 몇 장 안 돼(지역 7 + 링크 몇 장)
/// 첫 화면 사진과 함께 미리 받아 둔다
List<String> homeBelowFoldImageUrls(HomeSnapshot snapshot) => [
  for (final region in snapshot.regions.take(homeLeavePickMax))
    if (region['imageUrl'] case final String url when url.isNotEmpty) url,
  for (final link in snapshot.curatedLinks)
    if (link.thumbnailUrl case final String url when url.isNotEmpty) url,
];

/// 첫 화면 사진을 받고, **다 받은 뒤에** 아래 섹션 사진을 받는다.
///
/// 한꺼번에 넣지 않는다 — 사진 캐시는 동시에 10장까지 받아, 섞어 넣으면 첫
/// 화면 사진이 아래 섹션과 대역폭을 나눠 늦게 뜬다. 첫 화면 사진이 끝나지
/// 않으면(실패는 끝난 것으로 친다) 아래 섹션은 홈에서 스크롤할 때 받는다
Future<void> _prefetchHomeImages(
  Future<void> Function(String url) prefetch,
  HomeSnapshot snapshot,
) async {
  final first = homeFirstImageUrls(snapshot);
  await Future.wait(first.map(prefetch));
  for (final url in homeBelowFoldImageUrls(snapshot)) {
    if (!first.contains(url)) unawaited(prefetch(url));
  }
}

/// 홈 데이터를 받는 대로 **첫 화면 사진**부터 받아 둔다 — 홈이 그려지기 전에.
/// 그다음 아래 섹션 사진([homeBelowFoldImageUrls])도 받는다.
///
/// 로그인한 채 앱을 켜면 스플래시 동안(`OffwayApp`), 방금 로그인해 홈으로
/// 가면 로그인 직후(`LoginScreen`) 부른다. 홈 데이터도 이때 요청이 나간다 —
/// 홈이 그려질 때 부르면 그만큼 늦다. 홈이 그려진 뒤 카드가 같은 사진을
/// 요청하면 이미 받았거나 받는 중인 것을 이어받는다. 실패해도 카드가 다시 받는다
void prefetchHomeFirstImages(WidgetRef ref) {
  // **기다리기 전에 쥐어 둔다.** 로그인 화면에서 부르면 홈으로 넘어가며 그
  // 화면이 닫히고, 닫힌 뒤에는 `ref` 를 쓸 수 없다 — 홈 데이터가 늦게 오면
  // 미리 받기가 통째로 빠졌다
  final prefetch = ref.read(imagePrefetcherProvider);
  unawaited(
    ref
        .read(homeSnapshotProvider.future)
        .then((snapshot) => _prefetchHomeImages(prefetch, snapshot))
        .catchError((_) {}),
  );
}

/// **로그인 전에** 홈 첫 화면 사진을 받아 둔다 — 처음 쓰는 사람을 위해.
/// 그다음 아래 섹션 사진([homeBelowFoldImageUrls])도 받는다.
///
/// 처음 설치한 사람은 스플래시 → 온보딩 소개 → 소셜 로그인 → 연차 입력을
/// 거쳐 홈에 온다. 추천 여행지 사진은 누구에게나 같아 그 사이에 받아 둘 수
/// 있다. 로그인 전 요청은 임시 Basic 계정으로 읽기만 된다(`AuthInterceptor`).
///
/// 홈 데이터는 **사진 주소를 고르는 데만** 쓴다 — 리포지토리를 직접 불러
/// [homeSnapshotProvider] 에 게스트 값을 남기지 않는다. 로그인하면 홈은
/// 제 계정으로 새로 받고, 사진은 디스크 캐시에서 바로 나온다. 실패하면 조용히
/// 넘어간다 — 홈에 와서 받으면 된다
void prefetchHomeImagesBeforeLogin(WidgetRef ref) {
  final prefetch = ref.read(imagePrefetcherProvider);
  unawaited(
    ref
        .read(homeRepositoryProvider)
        .fetch(beforeLogin: true)
        .then((snapshot) => _prefetchHomeImages(prefetch, snapshot))
        .catchError((_) {}),
  );
}
