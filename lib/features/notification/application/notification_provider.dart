import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_envelope.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';
import 'app_icon_badge.dart';

/// 알림 목록 한 페이지와 안읽음 전체 수.
///
/// [unreadCount]는 이 페이지가 아니라 **전체** 안읽음 수다 — 홈 배지가 쓴다.
typedef NotificationFeed = ({
  List<AppNotification> notifications,
  int unreadCount,
});

/// 알림 목록 (`GET /notifications`).
///
/// 화면을 나갔다 오면 다시 읽는다 — 읽음 처리와 새 알림이 서버에서 온다.
final notificationFeedProvider = FutureProvider.autoDispose<NotificationFeed>(
  (ref) => ref.watch(notificationRepositoryProvider).fetch(),
);

/// 홈 종 아이콘의 배지 — 안 읽은 알림이 하나라도 있는지.
///
/// **목록과 따로 둔다.** 목록은 autoDispose라 알림 화면을 나가면 버려지는데,
/// 배지는 홈에 머무는 내내 떠 있어야 한다.
///
/// 처음 켜질 때 스스로 한 번 조회한다 — 홈이 알림 화면을 거치지 않고도
/// 배지를 그릴 수 있어야 한다. 그 뒤로는 목록 조회·읽음 처리가 돌려주는
/// 수로 갱신한다([setUnreadCount]) — 배지를 고치려고 목록을 다시 부르지
/// 않는다.
///
/// 읽지 못했으면 켜지 않는다 — 잘못 켠 배지는 눌러도 빈 목록이라
/// 사용자를 두 번 속인다.
final hasUnreadNotificationsProvider =
    NotifierProvider<UnreadNotificationsBadge, bool>(
      UnreadNotificationsBadge.new,
    );

class UnreadNotificationsBadge extends Notifier<bool> {
  /// 지금 서버에 묻고 있는가 — 화면이 여럿 겹쳐도 왕복은 한 번이다
  bool _loading = false;

  @override
  bool build() {
    unawaited(refresh());
    return false;
  }

  /// 서버에 안읽음 수를 다시 묻는다.
  ///
  /// **처음 한 번으로는 모자란다.** 앱을 백그라운드에 둔 사이 알림이 쌓이면
  /// 돌아와도 점이 꺼져 있고, 로그인 직후에는 앞 계정 기준이 남는다. 조회가
  /// 실패했을 때도 다시 시도할 길이 없었다.
  ///
  /// 가벼운 요청 하나이므로 화면이 뜰 때마다 불러도 된다. 겹쳐 부르면
  /// [_loading]이 뒤 호출을 흘린다.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final feed = await ref.read(notificationRepositoryProvider).fetch();
      state = feed.unreadCount > 0;
      unawaited(syncAppIconBadge(feed.unreadCount));
    } on ApiException {
      // 배지는 덤이다 — 못 읽었으면 그대로 둔다. 다음 기회에 다시 묻는다
    } finally {
      _loading = false;
    }
  }

  /// 서버가 준 안읽음 수로 배지를 맞춘다 — 종의 점과 아이콘 숫자를 함께
  void setUnreadCount(int count) {
    state = count > 0;
    unawaited(syncAppIconBadge(count));
  }

  /// 푸시가 막 도착했다 — 서버에 묻지 않고 켠다.
  ///
  /// 방금 온 알림은 당연히 안 읽음이라 왕복할 이유가 없다. 목록을 다시
  /// 읽어 켜려 하면 그 사이 홈에 돌아온 사용자가 배지 없는 종을 본다.
  void markArrived() => state = true;
}

/// 여행 뒤 "다녀오셨나요?" 에 답한 **그 여행의 알림**을 읽음으로 바꾼다.
///
/// 모달은 알림을 누르지 않아도 홈·내 연차에 들어오면 저절로 뜬다. 그 길로 답하면
/// 같은 여행의 "다녀오셨나요?" 알림이 안 읽음으로 남아, 이미 답한 여행인데
/// 종에 점이 계속 떠 있었다. 서버에는 코스 단위 읽음 처리가 없어 최근 목록에서
/// 그 여행(`courseId`)의 안 읽은 [NotificationType.tripAfter] 만 골라 하나씩
/// 읽는다 — 한 여행에 알림은 하나라 보통 한 번이다. 최근 한 페이지만 본다:
/// 방금 답한 여행의 알림은 늘 앞쪽에 있다.
///
/// **기다리기 전에 쥐어 둔다.** 모달을 닫고 화면을 떠나도 끝까지 간다.
/// 실패는 삼킨다 — 읽음 표시가 남는 것뿐이고 알림함에서 누르면 읽힌다
Future<void> markTripAfterNotificationsRead(WidgetRef ref, int courseId) async {
  final repository = ref.read(notificationRepositoryProvider);
  final badge = ref.read(hasUnreadNotificationsProvider.notifier);
  try {
    final feed = await repository.fetch();
    int? unread;
    for (final item in feed.notifications) {
      if (item.read ||
          item.type != NotificationType.tripAfter ||
          item.courseId != courseId) {
        continue;
      }
      unread = await repository.markRead(item.id);
    }
    // 읽은 게 있을 때만 맞춘다 — 서버가 센 남은 수다
    if (unread != null) badge.setUnreadCount(unread);
  } on Object {
    // 읽음 표시가 남는 것뿐이다
  }
}
