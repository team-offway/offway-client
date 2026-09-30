import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offway/features/notification/application/notification_provider.dart';
import 'package:offway/features/notification/data/notification_repository.dart';
import 'package:offway/features/notification/domain/app_notification.dart';

/// "다녀오셨나요?" 에 답하면 **그 여행의** 알림이 읽음으로 바뀐다.
///
/// 알림을 누르지 않고 홈에서 저절로 뜬 모달로 답하면 알림이 안 읽음으로
/// 남아, 이미 답한 여행인데 종에 점이 계속 떠 있었다
void main() {
  AppNotification item(
    int id,
    NotificationType type, {
    required int courseId,
    bool read = false,
  }) => AppNotification(
    id: id,
    type: type,
    read: read,
    courseId: courseId,
    createdAt: DateTime(2026, 9, 30),
  );

  Future<void> run(WidgetTester tester, _FakeRepository repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          hasUnreadNotificationsProvider.overrideWith(_StubBadge.new),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => markTripAfterNotificationsRead(ref, 7),
              child: const Text('답함'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('답함'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('그 여행의 안 읽은 "다녀오셨나요?" 만 읽는다', (tester) async {
    final repo = _FakeRepository([
      item(1, NotificationType.tripAfter, courseId: 7), // 이것만
      item(2, NotificationType.tripAfter, courseId: 8), // 다른 여행
      item(3, NotificationType.tripTomorrow, courseId: 7), // 다른 종류
      item(4, NotificationType.tripAfter, courseId: 7, read: true), // 이미 읽음
    ], unreadAfter: 2);
    await run(tester, repo);

    expect(repo.marked, [1]);
    // 종 점은 서버가 센 남은 수로 맞춘다 — 다른 안 읽은 알림이 있어 켜져 있다
    expect(_StubBadge.lastCount, 2);
  });

  testWidgets('읽을 게 없으면 읽음 요청도 종 갱신도 하지 않는다', (tester) async {
    // 알림을 눌러 들어왔으면 이미 읽었다
    final repo = _FakeRepository([
      item(1, NotificationType.tripAfter, courseId: 7, read: true),
    ], unreadAfter: 0);
    _StubBadge.lastCount = null;
    await run(tester, repo);

    expect(repo.marked, isEmpty);
    expect(_StubBadge.lastCount, isNull);
  });

  testWidgets('목록을 못 읽어도 조용히 넘어간다', (tester) async {
    final repo = _FakeRepository(const [], unreadAfter: 0, fail: true);
    await run(tester, repo);

    expect(repo.marked, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _FakeRepository extends NotificationRepository {
  _FakeRepository(this.items, {required this.unreadAfter, this.fail = false})
    : super(Dio());

  final List<AppNotification> items;
  final int unreadAfter;
  final bool fail;
  final marked = <int>[];

  @override
  Future<({List<AppNotification> notifications, int unreadCount})> fetch({
    int page = 0,
    int size = 20,
  }) async {
    if (fail) throw Exception('서버 오류');
    return (notifications: items, unreadCount: items.length);
  }

  @override
  Future<int> markRead(int notificationId) async {
    marked.add(notificationId);
    return unreadAfter;
  }
}

/// 서버를 부르지 않는 배지 — 마지막으로 맞춘 수를 기억한다
class _StubBadge extends UnreadNotificationsBadge {
  static int? lastCount;

  @override
  bool build() => false;

  @override
  void setUnreadCount(int count) => lastCount = count;
}
