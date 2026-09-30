import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offway/core/network/image_cache.dart';
import 'package:offway/core/theme/app_theme.dart';
import 'package:offway/core/widgets/curated_link_section.dart';
import 'package:offway/features/auth/application/current_user_provider.dart';
import 'package:offway/features/course/application/pending_trip_provider.dart';
import 'package:offway/features/home/application/home_providers.dart';
import 'package:offway/features/home/data/home_repository.dart';
import 'package:offway/features/home/presentation/home_screen.dart';
import 'package:offway/features/region/presentation/widgets/region_card.dart';

/// 홈 '이번달 추천 여행지' — **처음 보이는 사진부터** 받고, 끝나면 전부 받는다.
///
/// 카드 50여 장을 한꺼번에 만들어 사진도 한꺼번에 받았다. 보이는 3~4장이
/// 화면 밖 사진과 대역폭을 나눠 쓰느라 늦게 떴다.
void main() {
  List<Map<String, dynamic>> regions(int n) => [
    for (var i = 1; i <= n; i++)
      {
        'id': '$i',
        'name': '지역$i',
        'sido': '도',
        'imageUrl': 'https://example.com/$i.jpg',
        'categoryCounts': const {},
      },
  ];

  testWidgets('보이는 사진을 먼저 받고, 끝나면 나머지도 전부 받는다', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 첫 사진 받기를 붙잡아 둔다 — 풀기 전과 후를 본다
    final gate = Completer<void>();
    final prefetched = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) async => {'nickname': '영찬', 'remainingLeaveDays': 12.0},
          ),
          homeSnapshotProvider.overrideWith(
            (ref) async => HomeSnapshot(
              user: const {'remainingLeaveDays': 12.0},
              regions: regions(30),
            ),
          ),
          pendingTripProvider.overrideWith((ref) async => null),
          imagePrefetcherProvider.overrideWithValue((url) async {
            prefetched.add(url);
            await gate.future;
          }),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    List<RegionCard> cards() => tester
        .widgetList<RegionCard>(find.byType(RegionCard))
        .where((c) => c.style == RegionCardStyle.boxed)
        .toList();
    int loading() => cards().where((c) => c.loadImage).length;

    // 카드는 전부 만든다 — 줄 높이가 가장 긴 카드에 맞춰진다
    expect(cards().length, greaterThanOrEqualTo(30));
    // 처음에는 보이는 카드(402폭에 2~3장)와 그 뒤 두 장만
    final first = loading();
    expect(first, inInclusiveRange(3, 5));
    expect(prefetched, hasLength(first));

    // 첫 사진이 다 받아지면 나머지도 예전처럼 전부 받는다
    gate.complete();
    await tester.pumpAndSettle();
    expect(loading(), cards().length);
  });

  testWidgets('첫 사진이 오래 걸려도 3초 뒤에는 나머지를 푼다', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final never = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) async => {'nickname': '영찬', 'remainingLeaveDays': 12.0},
          ),
          homeSnapshotProvider.overrideWith(
            (ref) async => HomeSnapshot(
              user: const {'remainingLeaveDays': 12.0},
              regions: regions(30),
            ),
          ),
          pendingTripProvider.overrideWith((ref) async => null),
          // 큰 원본처럼 끝나지 않는다
          imagePrefetcherProvider.overrideWithValue((url) => never.future),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    int loading() => tester
        .widgetList<RegionCard>(find.byType(RegionCard))
        .where((c) => c.style == RegionCardStyle.boxed && c.loadImage)
        .length;
    expect(loading(), lessThanOrEqualTo(5));

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(loading(), greaterThanOrEqualTo(30));
  });

  test('처음 보일 사진 주소 — 추천 여행지 줄의 앞 몇 장', () {
    final snapshot = HomeSnapshot(user: const {}, regions: regions(8));
    expect(homeFirstImageUrls(snapshot, count: 5), [
      for (var i = 1; i <= 5; i++) 'https://example.com/$i.jpg',
    ]);
  });

  testWidgets('홈 데이터가 오면 첫 화면 사진을 받는다 — 스플래시·로그인 직후 공통', (tester) async {
    final prefetched = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeSnapshotProvider.overrideWith(
            (ref) async => HomeSnapshot(user: const {}, regions: regions(8)),
          ),
          imagePrefetcherProvider.overrideWithValue((url) async {
            prefetched.add(url);
          }),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return TextButton(
                onPressed: () => prefetchHomeFirstImages(ref),
                child: const Text('로그인'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('로그인'));
    await tester.pump();
    await tester.pump();

    // 첫 화면 5장, 그다음 '이번 연차엔' 지역 카드 중 아직 안 받은 6·7
    expect(prefetched, [
      for (var i = 1; i <= 7; i++) 'https://example.com/$i.jpg',
    ]);
  });

  testWidgets('로그인 전에는 사진만 받고, 홈 데이터 상태에는 남기지 않는다', (tester) async {
    // 처음 쓰는 사람은 로그인·연차 입력을 거쳐 홈에 온다 — 그 사이에 받는다
    final prefetched = <String>[];
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(
          _GuestHomeRepository(regions(8)),
        ),
        imagePrefetcherProvider.overrideWithValue((url) async {
          prefetched.add(url);
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => prefetchHomeImagesBeforeLogin(ref),
              child: const Text('시작'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump();

    expect(prefetched, hasLength(7)); // 첫 화면 5 + 아래 섹션 2
    // 게스트 값이 홈 데이터로 남지 않는다 — 로그인하면 제 계정으로 새로 받는다
    expect(container.exists(homeSnapshotProvider), isFalse);
  });

  testWidgets('로그인 화면이 먼저 닫혀도 첫 화면 사진을 받는다', (tester) async {
    // 로그인 직후 홈(또는 연차 입력)으로 넘어가며 로그인 화면이 닫힌다. 홈
    // 데이터가 그보다 늦게 오면 닫힌 화면의 ref 로 읽다 미리 받기가 빠졌다
    final home = Completer<HomeSnapshot>();
    final prefetched = <String>[];
    final container = ProviderContainer(
      overrides: [
        homeSnapshotProvider.overrideWith((ref) => home.future),
        imagePrefetcherProvider.overrideWithValue((url) async {
          prefetched.add(url);
        }),
      ],
    );
    addTearDown(container.dispose);

    var show = true;
    late StateSetter setOuter;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              if (!show) return const SizedBox();
              return Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => prefetchHomeFirstImages(ref),
                  child: const Text('로그인'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('로그인'));
    // 로그인 화면이 닫힌다
    setOuter(() => show = false);
    await tester.pump();

    // 그 뒤에 홈 데이터가 온다
    home.complete(HomeSnapshot(user: const {}, regions: regions(8)));
    await tester.pump();
    await tester.pump();

    expect(prefetched, hasLength(7)); // 첫 화면 5 + 아래 섹션 2
    expect(tester.takeException(), isNull);
  });

  group('첫 화면 아래 섹션 사진', () {
    // 처음 쓰는 사람이 스크롤을 내리면 '이번 연차엔 여기 어때요?' 와
    // '연차 쓰기 전, 확인해보세요' 사진이 비어 있다가 떴다
    final snapshot = HomeSnapshot(
      user: const {},
      regions: regions(9),
      places: [
        for (var i = 1; i <= 6; i++)
          {
            'id': 'p$i',
            'name': '장소$i',
            'kind': 'SIGHT',
            // 첫 화면 줄은 한 줄 소개가 있는 장소만 올린다
            'description': '소개',
            'imageUrl': 'https://example.com/p$i.jpg',
          },
      ],
      curatedLinks: const [
        CuratedLink(
          title: '링크1',
          chipText: '칩',
          linkUrl: 'https://example.com/a',
          thumbnailUrl: 'https://example.com/l1.jpg',
        ),
        // 사진 없는 링크는 건너뛴다
        CuratedLink(
          title: '링크2',
          chipText: '칩',
          linkUrl: 'https://example.com/b',
        ),
      ],
    );

    test('지역 카드는 화면에 놓는 만큼(7장)만, 링크 카드는 사진 있는 것만', () {
      expect(homeBelowFoldImageUrls(snapshot), [
        for (var i = 1; i <= homeLeavePickMax; i++)
          'https://example.com/$i.jpg',
        'https://example.com/l1.jpg',
      ]);
    });

    testWidgets('첫 화면 사진을 다 받은 **뒤에** 받는다 — 대역폭을 나누지 않게', (tester) async {
      final gate = Completer<void>();
      final prefetched = <String>[];
      final container = ProviderContainer(
        overrides: [
          homeSnapshotProvider.overrideWith((ref) async => snapshot),
          imagePrefetcherProvider.overrideWithValue((url) {
            prefetched.add(url);
            // 첫 화면(장소) 사진만 붙잡는다
            return url.contains('/p') ? gate.future : Future.value();
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => prefetchHomeFirstImages(ref),
                child: const Text('시작'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('시작'));
      await tester.pump();
      await tester.pump();

      // 첫 화면 사진을 받는 동안에는 아래 섹션을 부르지 않는다
      expect(prefetched, [
        for (var i = 1; i <= 5; i++) 'https://example.com/p$i.jpg',
      ]);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(prefetched.skip(5), homeBelowFoldImageUrls(snapshot));
    });
  });
}

class _GuestHomeRepository implements HomeRepository {
  _GuestHomeRepository(this.regions);

  final List<Map<String, dynamic>> regions;

  @override
  Future<HomeSnapshot> fetch({bool beforeLogin = false}) async =>
      HomeSnapshot(user: const {}, regions: regions);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
