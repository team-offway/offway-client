import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offway/core/router/app_router.dart';
import 'package:offway/core/theme/app_theme.dart';
import 'package:offway/core/widgets/app_back_button.dart';
import 'package:offway/features/course/presentation/saved_course_screen.dart';
import 'package:offway/features/course_wizard/presentation/origin_screen.dart';
import 'package:offway/features/course/application/course_providers.dart';

/// 위젯·공유 링크로 **바로 들어온** 화면의 뒤로가기 (#304 후속).
///
/// 딥링크는 스택을 갈아치우므로(`go`) 그 화면이 유일한 경로다. 그대로
/// `context.pop()` 을 부르면 `GoError: There is nothing to pop` 이 난다 —
/// 돌아갈 곳이 없으면 제자리를 정해 보내야 한다.
void main() {
  Widget wrap(GoRouter router) => ProviderScope(
    overrides: [
      savedCourseDetailProvider('1').overrideWith(
        (ref) async => (
          saved: {
            'id': '1',
            'regionName': '정선군',
            'travelDate': '2026-09-23',
            'startDate': '2026-09-23',
            'endDate': '2026-09-23',
            'leaveDeducted': false,
          },
          course: {
            'regionName': '정선군',
            'durationDays': 1,
            'travelDate': '2026-09-23',
            'days': [
              {
                'day': 1,
                'date': '2026-09-23',
                'dayOfWeek': '수',
                'places': <Map<String, dynamic>>[],
              },
            ],
          },
        ),
      ),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );

  testWidgets('코스 상세로 바로 들어와 뒤로가기를 눌러도 튕기지 않는다', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      // 딥링크가 go 로 들어온 상태 — 이 화면이 유일한 경로다
      initialLocation: AppRoutes.savedCoursePath('1'),
      routes: [
        GoRoute(
          path: AppRoutes.myCourses,
          builder: (_, _) => const Scaffold(body: Text('내 코스 목록')),
        ),
        GoRoute(
          path: AppRoutes.savedCourse,
          builder: (_, s) =>
              SavedCourseScreen(savedId: s.pathParameters['savedId']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(wrap(router));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/my-courses/1',
    );

    await tester.tap(find.byType(AppBackButton).first);
    await tester.pumpAndSettle();

    // 예외 없이 목록으로 — 예전에는 GoError 가 났다
    expect(tester.takeException(), isNull);
    expect(find.text('내 코스 목록'), findsOneWidget);
  });

  testWidgets('코스 만들기로 바로 들어와 뒤로가기를 눌러도 튕기지 않는다', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: AppRoutes.wizardOrigin,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('홈')),
        ),
        GoRoute(
          path: AppRoutes.wizardOrigin,
          builder: (_, _) => const OriginScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(wrap(router));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppBackButton).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('홈'), findsOneWidget);
  });
}
