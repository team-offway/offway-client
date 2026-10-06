import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offway/core/theme/app_theme.dart';
import 'package:offway/features/policy/presentation/benefit_badge.dart';
import 'package:offway/features/policy/presentation/region_benefit_card.dart';
import 'package:offway/features/region/domain/region_visit_metrics.dart';
import 'package:offway/features/region/presentation/region_detail_screen.dart';
import 'package:offway/features/policy/data/region_policies_provider.dart';
import 'package:offway/features/policy/domain/region_benefit.dart';
import 'package:offway/features/region/application/region_detail_provider.dart';

/// 지역 상세 — 시안(코스_상세)의 순서와 접힘 규칙을 고정한다.
void main() {
  /// 3줄을 확실히 넘기는 소개글
  const longStory =
      '한때 검은 석탄을 캐내던 삼탄아트마인은 이제 빛과 색으로 가득한 복합문화공간으로 다시 태어났다. '
      '화암동굴의 신비로운 종유석 사이를 걷고 아리랑시장 좌판에서 곤드레밥 한 그릇을 비우면 '
      '하루가 저문다. 정선은 그렇게 느리게 흐르는 시간을 품고 있다. '
      '가을이면 능선마다 단풍이 번지고 겨울에는 눈꽃이 마을을 덮는다.';

  Future<void> pump(
    WidgetTester tester, {
    String? story = longStory,
    List<Map<String, dynamic>> spots = const [],
    Object? visitMetrics,
    RegionPolicyIndex policyIndex = const {},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 혜택 색인은 서버를 부른다 — 여기서는 준 값만 쓴다
          regionPoliciesProvider.overrideWith((ref) async => policyIndex),
          regionDetailProvider('정선').overrideWith(
            (ref) async => {
              'id': '정선',
              // 서버가 시군구·시도를 합쳐 준다 (core #307)
              'name': '정선 · 강원',
              'headline': '🏔️ 폐광촌에서 예술마을로',
              'story': ?story,
              'benefit': {'text': '숙박 할인', 'policyId': 3},
              'photos': const <String>[],
              'highlightSpots': spots,
              'visitMetrics': RegionVisitMetrics.parse(visitMetrics),
            },
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RegionDetailScreen(regionId: '정선'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('화면 구성', () {
    testWidgets('제목과 혜택 뱃지를 보여준다', (tester) async {
      await pump(tester);

      expect(find.text('정선 · 강원'), findsOneWidget);
      // 지역명 아래 뱃지와 혜택 카드 안 뱃지 — 같은 문구가 두 자리에 온다
      expect(find.text('숙박 할인'), findsNWidgets(2));
      expect(find.byType(BenefitBadge), findsOneWidget);
      expect(find.byType(RegionBenefitCard), findsOneWidget);
    });

    testWidgets('우측 상단에 공유 버튼이 없다', (tester) async {
      // 시안에 없는 버튼이었다. 누르면 아무 일도 일어나지 않아 고장난
      // 것처럼 보였다
      await pump(tester);
      expect(find.byIcon(Icons.ios_share), findsNothing);
    });

    testWidgets('한 줄 제목은 그리지 않는다', (tester) async {
      // 시안에 headline 자리가 없다 — 제목·뱃지 바로 아래가 본문이다
      await pump(tester);
      expect(find.text('🏔️ 폐광촌에서 예술마을로'), findsNothing);
    });

    testWidgets("'기본 정보' 대신 인구감소지역 안내로 끝맺는다", (tester) async {
      await pump(tester);

      expect(find.text('기본 정보'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('아직 발견할 매력이 많은 지역이에요'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // 추세를 모르는 지역이라 '안 뜨는 곳' 문구다(시안 18860:76344) —
      // 없는 근거로 "발길이 늘고 있다"고 말하지 않는다
      expect(find.textContaining('잘 알려지지 않은 곳에서'), findsOneWidget);
    });

    testWidgets('소개글이 없으면 그 칸을 접는다', (tester) async {
      // 서버 89곳은 소개글이 없다 — 빈 칸이 남으면 안 된다
      await pump(tester, story: null);

      expect(find.textContaining('삼탄아트마인'), findsNothing);
      expect(find.text('정선 · 강원'), findsOneWidget);
    });
  });

  group('소개글 접기', () {
    /// 소개 본문 위젯을 찾는다
    Text storyText(WidgetTester tester) => tester.widget<Text>(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('삼탄아트마인') ?? false),
      ),
    );

    testWidgets('처음에는 3줄까지만 보여준다', (tester) async {
      // 다 펼쳐 두면 긴 지역에서 사진·매력 포인트가 화면 밖으로 밀린다
      await pump(tester);

      expect(storyText(tester).maxLines, 3);
      expect(storyText(tester).overflow, TextOverflow.ellipsis);
    });

    testWidgets('쉐브론을 누르면 펼쳐진다', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('expandable-description-toggle')));
      await tester.pumpAndSettle();

      expect(storyText(tester).maxLines, isNull);
    });

    testWidgets('펼친 뒤 다시 누르면 접힌다', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('expandable-description-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expandable-description-toggle')));
      await tester.pumpAndSettle();

      expect(storyText(tester).maxLines, 3);
    });

    testWidgets('짧은 소개글에는 쉐브론을 두지 않는다', (tester) async {
      // 눌러도 변화가 없는 버튼은 없느니만 못하다
      await pump(tester, story: '삼탄아트마인이 있는 고장.');

      expect(
        find.byKey(const Key('expandable-description-toggle')),
        findsNothing,
      );
    });
  });

  group('매력 포인트 장소', () {
    testWidgets('장소가 있으면 지역명을 붙여 제목을 만든다', (tester) async {
      await pump(
        tester,
        spots: [
          {'name': '삼탄아트마인', 'caption': '관광'},
        ],
      );

      await tester.scrollUntilVisible(
        find.text('정선 매력 포인트 장소'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // 사진이 없는 장소에는 이름을 얹지 않는다(QA-3) — 가이드가 그 자리를
      // 스켈레톤과 아이콘으로만 둔다. 섹션 제목이 떴으면 카드도 그려진 것이다
      expect(find.text('삼탄아트마인'), findsNothing);
    });

    testWidgets('장소가 없으면 그 칸을 통째로 접는다', (tester) async {
      await pump(tester);
      expect(find.text('정선 매력 포인트 장소'), findsNothing);
    });
  });

  group('마무리 안내 — 인기 상승 여부로 갈린다 (core #438)', () {
    // 같은 지역을 두고도 할 말이 다르다. 발길이 느는 곳은 "지금 뜨는 곳"이라
    // 권하고, 그렇지 않은 곳은 "아직 안 알려진 곳"이라 권한다
    Future<void> scrollToNote(WidgetTester tester, String title) =>
        tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('발길이 느는 지역이면 그렇게 말한다', (tester) async {
      await pump(
        tester,
        visitMetrics: const {
          'trend': {'percent': 40, 'rising': true},
        },
      );

      await scrollToNote(tester, '요즘 발길이 늘고 있는 지역이에요');
      expect(find.textContaining('익숙한 여행지에서 조금 벗어나'), findsOneWidget);
    });

    testWidgets("발길이 느는 지역이면 지역명 아래 '최근 인기 상승' 칩도 붙는다", (tester) async {
      // 시안(18860:76194): 혜택 칩 옆에 나란히. 마무리 안내와 같은 값을 본다
      await pump(
        tester,
        visitMetrics: const {
          'trend': {'percent': 3, 'rising': true},
        },
      );

      expect(find.text('최근 인기 상승'), findsOneWidget);
      expect(find.byType(BenefitBadge), findsOneWidget);
    });

    testWidgets('안 느는 지역이면 칩이 없다', (tester) async {
      await pump(
        tester,
        visitMetrics: const {
          'trend': {'percent': -5, 'rising': false},
        },
      );

      expect(find.text('최근 인기 상승'), findsNothing);
    });

    testWidgets('안 느는 지역이면 숨은 매력으로 권한다', (tester) async {
      // 이쪽을 "주목받는 곳"이라 부르면 사실과 다르다
      await pump(
        tester,
        visitMetrics: const {
          'trend': {'percent': -5, 'rising': false},
        },
      );

      await scrollToNote(tester, '아직 발견할 매력이 많은 지역이에요');
      expect(find.textContaining('잘 알려지지 않은 곳에서'), findsOneWidget);
    });

    testWidgets('추세를 모르면 안 뜨는 쪽으로 본다', (tester) async {
      // 재료가 모자라 서버가 값을 비웠을 뿐인데 "발길이 늘고 있다"고 하면
      // 없는 근거를 지어내는 것이다
      await pump(tester, visitMetrics: null);

      await scrollToNote(tester, '아직 발견할 매력이 많은 지역이에요');
      expect(find.text('요즘 발길이 늘고 있는 지역이에요'), findsNothing);
    });
  });

  testWidgets('하단 "누릴 수 있는 혜택"에는 그 지역 혜택을 전부 쌓는다', (tester) async {
    // 예전에는 대표 하나만 그려, 나머지는 위 뱃지의 '+N' 시트를 열어야 보였다
    await pump(
      tester,
      policyIndex: const {
        '정선': [
          RegionBenefit(text: '숙박 할인', policyId: 3),
          RegionBenefit(text: '여행경비 50% 환급', policyId: 1),
          RegionBenefit(text: '근로자 휴가비', policyId: 4),
        ],
      },
    );
    await tester.pumpAndSettle();

    expect(find.byType(RegionBenefitCard), findsNWidgets(3));
    // 순서는 색인 그대로 — 대표가 맨 앞이다
    final cards = tester
        .widgetList<RegionBenefitCard>(find.byType(RegionBenefitCard))
        .map((c) => c.benefit.text)
        .toList();
    expect(cards, ['숙박 할인', '여행경비 50% 환급', '근로자 휴가비']);
  });

  testWidgets('혜택이 여럿이면 뱃지 옆에 +1이 붙고, 누르면 고르는 시트가 뜬다', (tester) async {
    // 서버는 대표 하나만 주고, 나머지는 앱이 정책 상세를 모은 색인에서 온다
    await pump(
      tester,
      policyIndex: const {
        '정선': [
          RegionBenefit(text: '숙박 할인', policyId: 3),
          RegionBenefit(
            text: '여행경비 50% 환급',
            policyId: 1,
            policyName: '지역사랑 휴가지원(반값여행)',
          ),
        ],
      },
    );
    await tester.pumpAndSettle();

    // 뱃지와 아래 혜택 카드가 같은 문구를 쓴다 — 대표는 서버 값 그대로다
    expect(find.text('숙박 할인'), findsNWidgets(2));
    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();

    expect(find.text('정선 · 강원 혜택'), findsOneWidget);
    // 시트 안 한 번 + 화면 아래 혜택 카드 한 번 — 하단은 혜택을 전부 쌓는다
    expect(find.text('지역사랑 휴가지원(반값여행)'), findsNWidgets(2));
  });
}
