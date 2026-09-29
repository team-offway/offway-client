import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/place_thumbnail.dart';
import '../../region/presentation/widgets/region_card.dart';
import '../application/home_providers.dart';
import '../data/home_repository.dart';

/// 홈 첫 화면에 보이는 추천 여행지 사진 수 — 폭 402 기준 두 장 반이 보인다
const _visibleCards = 3;

/// 홈으로 넘어가기 **직전에** 첫 화면 사진을 메모리에 풀어 둔다.
///
/// 처음 쓰는 사람은 로그인·연차 입력 동안 사진을 디스크에 받아 둔다
/// ([prefetchHomeImagesBeforeLogin] · [prefetchHomeFirstImages]). 그래도 홈이
/// 뜨는 순간 파일을 읽어 푸는 한두 프레임은 카드가 비어 보였다. 카드가 그릴
/// 때와 **같은 키**로 풀어 두면 홈의 첫 프레임부터 사진이 있다.
///
/// [timeout] 을 넘기면 기다리지 않는다 — 아직 받는 중인 사진 때문에 홈으로
/// 못 넘어가면 그게 더 느리다. 넘긴 뒤에도 풀기는 이어져 곧 뜬다
Future<void> decodeHomeFirstImages(
  BuildContext context,
  WidgetRef ref,
  HomeSnapshot snapshot, {
  Duration timeout = const Duration(milliseconds: 400),
}) {
  final precache = ref.read(placeThumbnailPrecacheProvider);
  return Future.wait([
    for (final url in homeFirstImageUrls(snapshot, count: _visibleCards))
      precache(context, url, RegionCard.boxedImageWidth),
  ]).then<void>((_) {}).timeout(timeout, onTimeout: () {});
}
