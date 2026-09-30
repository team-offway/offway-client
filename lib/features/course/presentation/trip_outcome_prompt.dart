import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_envelope.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/leave_format.dart';
import '../../../core/widgets/app_toast.dart';
import '../../leave/data/leave_usages_provider.dart' show invalidateLeaveData;
import '../../notification/application/notification_provider.dart'
    show markTripAfterNotificationsRead;
import '../application/pending_trip_provider.dart';
import '../data/course_repository.dart';
import '../data/trip_outcome_snooze_storage.dart';
import '../domain/pending_trip.dart';
import 'widgets/trip_outcome_dialog.dart';
import '../application/course_providers.dart';

/// "다녀오셨나요?" 모달을 화면에 붙인다.
///
/// 시안 노트가 **홈**과 **내 연차** 두 곳에서 띄우라고 한다. 답을 처리하는
/// 절차(서버 기록 → 미룸 정리 → 연차 다시 읽기 → 토스트)가 똑같으므로
/// 화면마다 옮겨 적지 않고 한 곳에 둔다.
///
/// 쓰는 쪽은 [build] 안에서 [watchTripOutcomePrompt]를 한 번 부르면 된다.
mixin TripOutcomePrompt<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// 방금 물은 여행의 코스 id — 같은 여행을 두 번 묻지 않으려는 자물쇠.
  ///
  /// 프로바이더가 다시 읽힐 때마다(연차 갱신 등) 모달이 또 뜨는 걸 막는다.
  /// '나중에 할게요'는 저장소가 하루를 기억하지만, 그 저장이 끝나기 전에
  /// 다음 프레임이 오면 같은 여행을 두 번 묻게 된다.
  ///
  /// **여행마다 따로 센다.** 예전에는 한 번 물었다는 사실만 참·거짓으로
  /// 들고 있어, 밀린 여행이 둘 이상이면 첫 답 뒤 나머지가 묻히고 다른
  /// 메뉴를 다녀와야 나왔다
  int? _askedCourseId;

  /// 모달이 지금 떠 있는가 — 다른 모달(업데이트 시트)이 겹치지 않게 알린다
  bool _tripDialogOpen = false;

  /// 기록 토스트에 '보러가기'를 붙일지.
  ///
  /// 내 연차 화면은 그 버튼이 가리키는 곳이 자기 자신이라 끈다 —
  /// 눌러도 제자리인 버튼은 없느니만 못하다.
  bool get showsLeaveShortcut => true;

  /// 눌러서 들어온 "다녀오셨나요?" 알림이 가리키는 코스. 알림 없이 왔으면 null.
  ///
  /// **그 여행에 한해** [PendingTrip.askableFrom]을 다시 재지 않는다 — 알림이
  /// 곧 "지금 물어볼 때"라는 서버의 판단인데, 기기 시계가 몇 초 느리거나
  /// 시간대가 다르면 알림을 눌렀는데 모달이 안 뜨는 일이 생긴다.
  ///
  /// 다른 여행에는 적용하지 않는다. 프로바이더는 가장 오래 밀린 여행을
  /// 고르므로, 옛 알림을 뒤늦게 누른 아침에 어제 끝난 다른 여행이 걸리면
  /// 그 여행은 아직 물을 때가 아니다.
  int? get notificationCourseId => null;

  /// 물어볼 여행이 있으면 화면이 그려진 뒤 모달을 띄운다.
  ///
  /// [build] 안에서 부른다 — build 도중에는 `showDialog`를 열 수 없어
  /// 다음 프레임으로 미룬다.
  ///
  /// 돌려주는 값은 **이 모달이 지금 화면을 차지하는가**다 — 곧 띄우거나 이미
  /// 떠 있으면 true. 업데이트 시트처럼 같은 자리에 뜨는 다른 모달이 이 값을
  /// 보고 물러난다. 후보 여행이 있어도 아직 물을 때가 아니면 false다 — 그때
  /// 다른 모달까지 막으면 아무것도 안 뜬다.
  bool watchTripOutcomePrompt() {
    if (_tripDialogOpen) return true;
    // listen이 아니라 watch로 읽는다: 이 화면에 돌아왔을 때 이미 값이
    // 캐시돼 있으면 listen은 '바뀐 적 없다'며 부르지 않는다
    // 알림을 눌러 왔으면 **그 알림의 여행만** 묻는다 — 오늘 미뤘어도, 더
    // 오래된 여행이 밀려 있어도. 알림이 곧 질문이다. 이미 답한 여행이면
    // 목록에 없어 조용하다
    final notified = notificationCourseId;
    final trip = notified != null
        ? ref.watch(notifiedTripProvider(notified)).value
        : ref.watch(pendingTripProvider).value;
    if (trip == null || trip.courseId == _askedCourseId) return false;
    // 알림(다음 날 20시)보다 먼저 묻지 않는다 — 자정에 넘어온 여행은
    // 저녁까지 홈에 들어와도 조용하다. 그 여행의 알림을 눌러 왔을 때만 예외
    if (notified == null && !trip.isAskableAt(DateTime.now())) return false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && trip.courseId != _askedCourseId) _ask(trip);
    });
    return true;
  }

  Future<void> _ask(PendingTrip trip) async {
    _askedCourseId = trip.courseId;
    _tripDialogOpen = true;
    final result = await showTripOutcomeDialog(context, trip: trip);
    _tripDialogOpen = false;
    if (!mounted) return;

    if (result.answer == TripOutcomeAnswer.later) {
      // 오늘만 접는다 — 내일 들어오면 다시 묻는다
      await ref
          .read(tripOutcomeSnoozeProvider)
          .snooze(trip.courseId, DateTime.now());
      if (!mounted) return;
      // 미룬 것은 **이 여행 하나**다. 다른 밀린 여행이 있으면 이어서 묻는다 —
      // 여기서 멈추면 다음 것은 화면을 나갔다 와야 나온다
      ref.invalidate(pendingTripProvider);
      return;
    }

    final visited = result.answer == TripOutcomeAnswer.visited;
    final double? remainingDays;
    try {
      remainingDays = await ref
          .read(courseRepositoryProvider)
          .answerTripOutcome(
            trip.courseId,
            visited: visited,
            comment: result.comment,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      // 409(이미 답함)면 목록에서 빠지므로 다시 묻지 않는다.
      // 그 밖의 실패는 다음 진입에 다시 묻게 두고 알리기만 한다
      showAppToast(context, e.detail.isEmpty ? '기록하지 못했어요' : e.detail);
      return;
    }

    // 같은 여행의 "다녀오셨나요?" 알림도 읽음으로 — 알림을 누르지 않고 홈에서
    // 뜬 모달로 답하면 알림이 안 읽음으로 남았다. 알림을 눌러 들어왔으면 누를
    // 때 이미 읽었다
    if (notificationCourseId != trip.courseId) {
      unawaited(markTripAfterNotificationsRead(ref, trip.courseId));
    }

    // 답을 받았으니 미룸 기록은 필요 없다
    await ref.read(tripOutcomeSnoozeProvider).clear(trip.courseId);
    if (!mounted) return;

    // 홈 최상단 '남은 연차'와 연차 화면을 즉시 고쳐 그린다 (시안 노트)
    invalidateLeaveData(ref);
    // 답을 했으니 다시 물어보지 않는다
    ref.invalidate(pendingTripProvider);
    if (notificationCourseId case final id?) {
      ref.invalidate(notifiedTripProvider(id));
    }
    // 내 코스 카드의 여행완료·미방문 칩이 이 답(leaveDeducted)으로 갈리므로
    // 목록도 다시 읽는다
    ref.invalidate(savedCoursesProvider);

    // 안 갔다고 답하면 바뀐 게 없다 — 알릴 것도 없다
    if (!visited) return;

    showAppToast(
      context,
      '${trip.shortRegionName ?? '이번'} 여행을 기록했어요.',
      detail: _deductionDetail(trip.consumedLeaveDays, remainingDays),
      kind: AppToastKind.success,
      // 시안 흐름: 토스트 → 내 연차. 줄어든 잔여 연차와 방금 기록이
      // 한 화면에 같이 있다
      actionLabel: showsLeaveShortcut ? '보러가기' : null,
      onAction: showsLeaveShortcut
          ? () => context.push(AppRoutes.myLeave)
          : null,
    );
  }

  /// `연차 3일을 사용해 10일 남았어요.`
  ///
  /// 깎은 연차가 없으면(주말·공휴일만 다녀온 여행) 아예 말하지 않는다 —
  /// 모달이 차감 안내를 접은 것과 같은 이유로, '0일을 사용'은 헛말이다.
  /// 서버가 남은 연차를 안 주면(연차를 설정한 적 없는 사용자) 뒷말을 뺀다 —
  /// '0일 남았어요'로 잘못 말하느니 쓴 만큼만 알린다.
  String? _deductionDetail(double used, double? remaining) {
    if (used <= 0) return null;
    final spent = '연차 ${formatLeaveDays(used)}일을 사용';
    if (remaining == null) return '$spent했어요.';
    return '$spent해 ${formatLeaveDays(remaining)}일 남았어요.';
  }
}
