import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offway/core/widgets/place_thumbnail.dart';
import 'package:offway/features/region/presentation/widgets/region_card.dart';

/// 홈 첫 사진을 미리 풀어 두는 키가 카드가 그릴 때 찾는 키와 **같아야** 한다.
///
/// 폭이나 감싸는 방식이 하나라도 다르면 미리 푼 사진을 못 찾고 다시 풀어,
/// 미리 풀기가 헛일이 된다 — 눈으로는 "여전히 한 박자 늦게 뜬다" 로만 보인다
void main() {
  const url =
      'https://tong.visitkorea.or.kr/cms/resource/00/1234500_image2_1.jpg';

  testWidgets('홈 카드 폭(152)으로 미리 푼 키 = 카드가 그리는 키', (tester) async {
    tester.view
      ..physicalSize = const Size(402 * 3, 874 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          // 홈 카드와 같은 자리 — 폭 152 안에서 폭을 꽉 채운다
          child: SizedBox(
            width: RegionCard.boxedWidth,
            height: 114,
            child: PlaceThumbnail(
              imageUrl: url,
              width: double.infinity,
              height: double.infinity,
              radius: 0,
            ),
          ),
        ),
      ),
    );

    final drawn = tester.widget<Image>(find.byType(Image)).image;
    final context = tester.element(find.byType(PlaceThumbnail));
    final warmed = PlaceThumbnail.providerFor(
      context,
      url,
      RegionCard.boxedWidth,
    );

    expect(warmed, drawn);
    // 폭이 어긋나면 다른 키다 — 위 비교가 우연히 통과하지 않는지
    expect(PlaceThumbnail.providerFor(context, url, 150), isNot(drawn));
  });
}
