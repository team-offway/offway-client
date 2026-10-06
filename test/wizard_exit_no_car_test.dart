import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offway/core/network/api_envelope.dart';
import 'package:offway/features/course/application/course_providers.dart';
import 'package:offway/features/course/data/course_repository.dart';
import 'package:offway/features/course_wizard/application/course_wizard_provider.dart';
import 'package:offway/features/course_wizard/application/wizard_recommend_provider.dart';
import 'package:offway/features/course_wizard/data/region_recommend_repository.dart';
import 'package:offway/features/onboarding/data/leave_repository.dart';

/// 대중교통으로 코스를 만들었는데 **자차 코스가 한 번 더 생성됐다.**
///
/// '담기'·'닫기'가 위저드를 비우는 순간 화면은 아직 닫히기 전이라, 가용시간이
/// 다시 계산되며 코스·후보 추천이 다시 돌았다. 그때는 이동수단이 비어 기본값인
/// 자차로 나갔다(운영 알림: 같은 사용자, "서구 3일 (대중교통)" 다음 "(자차)")
void main() {
  late _RecordingCourseRepository courses;
  late _RecordingRecommendRepository recommends;
  late ProviderContainer container;

  setUp(() {
    courses = _RecordingCourseRepository();
    recommends = _RecordingRecommendRepository();
    container = ProviderContainer(
      overrides: [
        courseRepositoryProvider.overrideWithValue(courses),
        regionRecommendRepositoryProvider.overrideWithValue(recommends),
        leaveRepositoryProvider.overrideWithValue(_FakeLeaveRepository()),
      ],
    );
    addTearDown(container.dispose);
    container.read(courseWizardProvider.notifier)
      ..selectPeriodStyle(PeriodStyle.dayTrip)
      ..selectTransport(TransportMode.publicTransit);
  });

  /// 후보 화면 → 코스 화면이 떠 있는 상태 — 둘 다 구독 중이다
  Future<void> openCourse() async {
    container.listen(wizardRecommendProvider, (_, _) {});
    await container.read(wizardRecommendProvider.future);
    const key = (regionId: '1', desiredDays: 1);
    container.listen(courseProvider(key), (_, _) {});
    await container.read(courseProvider(key).future);
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('담기·닫기로 위저드를 비워도 코스·추천을 다시 부르지 않는다', () async {
    await openCourse();
    expect(courses.transports, ['TRANSIT']);
    expect(recommends.transports, ['TRANSIT']);

    container.read(courseWizardProvider.notifier).reset();
    await settle();

    expect(courses.transports, ['TRANSIT'], reason: '자차 코스가 또 나갔다');
    expect(recommends.transports, ['TRANSIT'], reason: '자차 추천이 또 나갔다');
  });

  test("'다시 설정하기'로 이동수단을 비워도 자차로 추천받지 않는다", () async {
    await openCourse();

    container.read(courseWizardProvider.notifier).restartFromTransport();
    await settle();
    expect(recommends.transports, ['TRANSIT']);

    // 다시 고르면 그 수단으로 묻는다
    container
        .read(courseWizardProvider.notifier)
        .selectTransport(TransportMode.car);
    await container.read(wizardRecommendProvider.future);
    expect(recommends.transports, ['TRANSIT', 'CAR']);
  });
}

class _RecordingCourseRepository extends CourseRepository {
  _RecordingCourseRepository() : super(Dio());

  final transports = <String>[];

  @override
  Future<Map<String, dynamic>> generate({
    required String regionId,
    required int travelDays,
    required String density,
    required String transport,
    required String? originCode,
    required DateTime travelDate,
    DateTime? confirmedDate,
  }) async {
    transports.add(transport);
    return {'regionId': regionId};
  }
}

class _RecordingRecommendRepository extends RegionRecommendRepository {
  _RecordingRecommendRepository() : super(Dio());

  final transports = <String>[];

  @override
  Future<({List<Map<String, dynamic>> regions, List<DataSource> sources})>
  recommend({
    required String? originCode,
    required String transport,
    required int maxReachMinutes,
  }) async {
    transports.add(transport);
    return (
      regions: const <Map<String, dynamic>>[],
      sources: const <DataSource>[],
    );
  }
}

class _FakeLeaveRepository extends LeaveRepository {
  _FakeLeaveRepository() : super(Dio());

  @override
  Future<AvailableTime> availableTime({
    required String transport,
    DateTime? startDate,
    DateTime? endDate,
    String? periodStyle,
    DateTime? baseDate,
    String? weekendBridge,
    int? leaveDays,
  }) async => (
    startDate: DateTime(2026, 10, 10),
    endDate: DateTime(2026, 10, 10),
    travelDays: 1,
    consumedLeaveDays: 1.0,
    maxReachMinutes: 120,
  );
}
