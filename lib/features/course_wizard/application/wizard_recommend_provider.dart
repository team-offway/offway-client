import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/trip_constants.dart';
import '../../../core/network/api_envelope.dart';
import 'available_time_provider.dart';
import 'course_wizard_provider.dart';
import '../data/region_recommend_repository.dart';

/// 위저드 조건(이동수단·기간)으로 후보지역을 추천받는다.
///
/// 도달 한계는 가용시간 계산이 정한다 — 당일치기 2시간 · 1박2일 3시간 ·
/// 2박3일 4시간(서버 기준). 계산에 실패하면 기본값([kMaxReachMinutes],
/// 420분)으로 폴백해 추천은 계속된다.
///
/// **출발지를 앱이 정하지 않는다.** GPS 를 걷어내면서(core #591) 사용자가
/// 첫 단계에서 고른 허브를 코드로 싣는다. 고른 것이 없으면 아무것도 싣지
/// 않고 서버가 기본 출발지를 쓴다
final wizardRecommendProvider =
    FutureProvider.autoDispose<
      ({List<Map<String, dynamic>> regions, List<DataSource> sources})
    >((ref) async {
      final transport = ref.watch(
        courseWizardProvider.select((draft) => draft.transportMode),
      );
      // **이동수단이 비면 묻지 않는다.** 후보 화면은 이동수단을 고른 뒤에만
      // 열린다 — 비는 것은 화면을 떠나는 순간뿐이다(닫기·담기의 초기화,
      // '다시 설정하기'). 그때 그대로 물으면 아래 기본값 때문에 **자차로**
      // 한 번 더 추천을 받았다. 끝나지 않는 Future 로 두면 화면이 닫히며
      // 함께 버려진다
      if (transport == null) {
        return Completer<
              ({List<Map<String, dynamic>> regions, List<DataSource> sources})
            >()
            .future;
      }
      final origin = ref.watch(
        courseWizardProvider.select((draft) => draft.origin),
      );
      final availableTime = await ref.watch(availableTimeProvider.future);
      return ref
          .read(regionRecommendRepositoryProvider)
          .recommend(
            originCode: origin?.code,
            transport: transport.serverValue,
            maxReachMinutes: availableTime?.maxReachMinutes ?? kMaxReachMinutes,
          );
    });

/// 후보 지역 카드들. 화면 넷이 이 목록만 보므로 출처와 갈라 둔다 —
/// 함께 묶으면 지역만 필요한 랜덤 지역 화면까지 레코드를 풀어야 한다
final wizardCandidatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) async => (await ref.watch(wizardRecommendProvider.future)).regions,
    );

/// 후보 지역 응답이 빌려 쓴 공공데이터 (core #417)
final wizardSourcesProvider = FutureProvider.autoDispose<List<DataSource>>(
  (ref) async => (await ref.watch(wizardRecommendProvider.future)).sources,
);
