// 코스 조회 provider — 화면 파일 밖에 두어 다른 기능이 화면을 import 하지 않게 한다(#366).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/trip_constants.dart';
import '../data/course_repository.dart';
import '../../course_wizard/application/available_time_provider.dart';
import '../../course_wizard/application/course_wizard_provider.dart';

/// 내 코스 목록 (`GET /courses?scope=`) — 정렬·범위는 서버가 맡는다.
/// 담기·삭제 후에는 invalidate로 다시 불러온다.
///
/// **세션 동안 들고 있는다**(#392). 탭 셸이 화면을 갈아 끼워 autoDispose 면
/// 내 코스 탭에 들어올 때마다 버려지고 스켈레톤부터 다시 떴다. 대신 탭에
/// 들어올 때 새로 받되 옛 목록을 보이는 채로 둔다(`MyCoursesScreen`).
///
/// 계정이 바뀌는 곳(로그인·로그아웃·탈퇴)에서는 `asReload: true` 로
/// 무효화한다 — 다시 받는 동안 화면은 옛 목록 대신 로딩을 그린다.
/// **값을 지우는 것은 아니다**: Riverpod 은 재로드 중에도 이전 값을 `.value`
/// 에 들고 있다. 이 목록을 `.value` 로 바로 그리면 앞사람의 목록이 보이니,
/// 늘 `when`/`whenRetryable`(재로드 중 로딩) 이나 `.future` 로 읽는다
final savedCoursesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
      (ref, scope) =>
          ref.watch(courseRepositoryProvider).savedCourseCards(scope: scope),
    );

/// 저장한 코스 하나 (`GET /courses/{id}`) — 카드 정보와 일정을 함께 받는다
final savedCourseDetailProvider = FutureProvider.autoDispose
    .family<
      ({Map<String, dynamic> saved, Map<String, dynamic> course})?,
      String
    >(
      (ref, savedId) =>
          ref.watch(courseRepositoryProvider).savedCourseDetail(savedId),
    );

/// 공유 링크로 받은 코스 (`GET /public/courses/{shareToken}`)
final sharedCourseProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, shareToken) =>
          ref.watch(courseRepositoryProvider).sharedCourse(shareToken),
    );

/// 장소 상세 (`GET /pois/{contentId}`)
final poiDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, contentId) =>
          ref.watch(courseRepositoryProvider).poiDetail(contentId),
    );

/// 위저드 조건(밀도·이동수단·기간)과 사용자가 고른 출발지로 코스를 생성한다.
///
/// 여행 날짜·일수는 가용시간 계산(서버, 공휴일 반영)이 확정한 값을 쓰고,
/// 계산에 실패했을 때만 로컬 추정으로 폴백한다.
final courseProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, ({String regionId, int desiredDays})>((
      ref,
      query,
    ) async {
      final draft = ref.read(courseWizardProvider);
      final availableTime = await ref.watch(availableTimeProvider.future);
      return ref
          .read(courseRepositoryProvider)
          .generate(
            regionId: query.regionId,
            travelDays: (availableTime?.travelDays ?? query.desiredDays).clamp(
              1,
              kMaxTripSpanDays + 1,
            ),
            density: draft.densityServerValue,
            transport: draft.transportServerValue,
            originCode: draft.origin?.code,
            travelDate:
                availableTime?.startDate ??
                draft.travelStartDate(DateUtils.dateOnly(DateTime.now())),
            // 캘린더에서 직접 고른 날짜만 확정으로 저장한다 — 추정 날짜를 실으면
            // 일정이 확정된 것처럼 보인다
            confirmedDate: draft.startDate,
          );
    });
