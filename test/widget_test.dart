import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offway/app/app.dart';
import 'package:offway/core/network/api_envelope.dart';
import 'package:offway/core/router/app_router.dart';
import 'package:offway/core/widgets/trip_date_range_picker.dart';
import 'package:offway/core/storage/secure_storage.dart';
import 'package:offway/features/auth/data/auth_repository.dart';
import 'package:offway/features/auth/data/google_auth_service.dart';
import 'package:offway/features/course/data/course_repository.dart';
import 'package:offway/features/course/presentation/poi_detail_screen.dart';
import 'package:offway/features/course/presentation/widgets/place_info_sheet.dart';
import 'package:offway/features/course/presentation/my_courses_screen.dart';
import 'package:offway/features/course_wizard/data/origin_search_repository.dart';
import 'package:offway/features/course_wizard/data/region_recommend_repository.dart';
import 'package:offway/features/course_wizard/domain/origin_hub.dart';
import 'package:offway/features/home/data/home_repository.dart';
import 'package:offway/features/policy/data/policy_repository.dart';
import 'package:offway/features/update/application/app_update_provider.dart';
import 'package:offway/features/home/presentation/home_screen.dart';
import 'package:offway/features/my/presentation/my_screen.dart';
import 'package:offway/features/notification/application/push_registration.dart';
import 'package:offway/features/notification/data/device_repository.dart';
import 'package:offway/features/notification/data/notification_repository.dart';
import 'package:offway/features/notification/domain/app_notification.dart';
import 'package:offway/features/onboarding/data/leave_repository.dart';
import 'package:offway/features/region/data/region_list_repository.dart';
import 'package:offway/features/region/data/region_detail_repository.dart';
import 'package:offway/features/region/presentation/region_list_screen.dart';
import 'package:offway/features/region/presentation/widgets/leave_pick_card.dart';
import 'package:offway/mock/mock_data_source.dart';
import 'package:offway/core/network/image_cache.dart';
import 'package:offway/core/widgets/place_thumbnail.dart';

/// Keychain 삭제가 실패하는 상황을 재현하는 저장소
class _FailingSecureStoragePlatform extends TestFlutterSecureStoragePlatform {
  _FailingSecureStoragePlatform() : super({});

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => throw Exception('keychain unavailable');
}

/// 테스트는 서버를 부르지 않는다 — 홈은 mock JSON을 그대로 돌려준다
/// 정책 상세 — 홈이 지역별 혜택 색인을 만들려고 id를 차례로 읽는다. 여기서는
/// 정책이 없는 서버다(404). 실제 Dio로 나가면 응답을 기다리는 타이머가 남아
/// 테스트가 끝난 뒤 터진다
class _FakePolicyRepository extends PolicyRepository {
  _FakePolicyRepository() : super(Dio());

  @override
  Future<Map<String, dynamic>> detail(int policyId) async =>
      throw ApiException(status: 404, code: 'POLICY-404', detail: '정책이 없어요');
}

class _FakeHomeRepository extends HomeRepository {
  _FakeHomeRepository() : super(Dio());

  @override
  Future<HomeSnapshot> fetch({bool beforeLogin = false}) async => HomeSnapshot(
    user: await MockDataSource.user(),
    regions: await MockDataSource.allRegions(),
    filters: const [
      {'key': 'ALL', 'label': '전체'},
      {'key': 'SIGHT', 'label': '관광지'},
      {'key': 'STAY', 'label': '숙박'},
      {'key': 'EXPERIENCE', 'label': '체험'},
      {'key': 'FOOD', 'label': '맛집'},
    ],
  );
}

/// 온보딩 연차 저장 — 네트워크 없이 항상 성공한 것으로 친다
class _FakeLeaveRepository extends LeaveRepository {
  _FakeLeaveRepository() : super(Dio());

  @override
  Future<double> updateTotalDays(double totalDays) async => totalDays;

  /// 가용시간 계산은 실패로 친다 — 위저드가 로컬 추정 폴백으로 흐른다
  @override
  Future<AvailableTime> availableTime({
    required String transport,
    DateTime? startDate,
    DateTime? endDate,
    String? periodStyle,
    DateTime? baseDate,
    String? weekendBridge,
    int? leaveDays,
  }) async => throw const ApiException(
    status: 0,
    code: 'TEST',
    detail: '테스트에는 서버가 없어요',
  );

  /// 공휴일 조회도 실패로 친다 — 폴백이 주말만 거른 값으로 물러난다.
  /// 물려받은 구현을 그대로 두면 진짜 HTTP를 타서 타이머가 남는다
  @override
  Future<Set<DateTime>> holidays(int year) async => throw const ApiException(
    status: 0,
    code: 'TEST',
    detail: '테스트에는 서버가 없어요',
  );
}

/// 지역 목록 더보기 — mock 지역을 한 페이지로 돌려준다.
/// 실제로는 서버가 89곳을 페이지로 끊어 주지만, 화면 검증에는 한 장이면 된다
/// 지역 상세 — mock 지역을 서버 응답 형태(core #307)로 돌려준다.
class _FakeRegionDetailRepository extends RegionDetailRepository {
  _FakeRegionDetailRepository() : super(Dio());

  @override
  Future<Map<String, dynamic>> detail(String regionId) async {
    final all = await MockDataSource.allRegions();
    final r = all.firstWhere(
      (e) => e['id'] == regionId || e['name'] == regionId,
      orElse: () => const <String, dynamic>{},
    );
    return {
      'regionId': regionId,
      'name': '${r['name'] ?? regionId} \u00b7 ${r['sido'] ?? ''}',
      'overview': r['story'],
      'photos': (r['photos'] as List?)?.cast<String>() ?? const <String>[],
      'benefit': ?r['benefit'],
      'highlightSpots': [
        for (final s
            in (r['highlightSpots'] as List?)?.cast<Map<String, dynamic>>() ??
                const [])
          {
            'poiContentId': s['poiContentId'],
            'name': s['name'],
            'imageUrl': s['imageUrl'],
            'catchphrase': s['caption'],
          },
      ],
    };
  }
}

class _FakeRegionListRepository extends RegionListRepository {
  _FakeRegionListRepository() : super(Dio());

  @override
  Future<RegionPage> fetch({
    String? category,
    int page = 0,
    int size = 20,
  }) async => RegionPage(
    regions: page == 0 ? await MockDataSource.allRegions() : const [],
    hasMore: false,
  );
}

/// 후보지역 추천 — mock 후보를 새 카드 형태로 돌려준다.
/// id가 mock 코스의 키('정선')와 같아 코스 화면까지 이어지는 플로우가 유지된다.
/// 출발지 자동완성 — 무엇을 쳐도 한 곳을 돌려준다.
/// 이 파일이 재는 것은 위저드가 이어지는가이지 검색 품질이 아니다
class _FakeOriginSearchRepository extends OriginSearchRepository {
  _FakeOriginSearchRepository() : super(Dio());

  @override
  Future<List<OriginHub>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    if (query.trim().length < OriginSearchRepository.minQueryLength) {
      return const [];
    }
    return const [
      OriginHub(
        code: 'TRAIN:NAT010000',
        name: '서울역',
        area: '서울',
        kind: 'TRAIN_STATION',
      ),
    ];
  }
}

class _FakeRegionRecommendRepository extends RegionRecommendRepository {
  _FakeRegionRecommendRepository() : super(Dio());

  @override
  Future<({List<Map<String, dynamic>> regions, List<DataSource> sources})>
  recommend({
    required String? originCode,
    required String transport,
    required int maxReachMinutes,
  }) async {
    final data = await MockDataSource.regions();
    final list = (data['candidates'] as List).cast<Map<String, dynamic>>();
    return (
      regions: [
        for (final r in list)
          {
            'id': r['id'],
            'name': r['name'],
            'sido': r['sido'],
            'imageUrl': r['imageUrl'],
            'description': r['description'],
            'reachMinutes': r['travelMinutesByCar'],
            'benefit': ?r['benefit'],
          },
      ],
      sources: const [DataSource(key: 'KTO', label: '한국관광공사')],
    );
  }
}

/// 코스 생성 — 옛 mock 선택 규칙(지역 일치 + 희망일수에 가장 가까운 코스)을 재현한다
class _FakeCourseRepository extends CourseRepository {
  _FakeCourseRepository() : super(Dio());

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
    final data = await MockDataSource.courses();
    final courses = (data['courses'] as List)
        .cast<Map<String, dynamic>>()
        .where((c) => c['regionId'] == regionId)
        .toList();
    courses.sort(
      (a, b) => ((a['durationDays'] as int) - travelDays).abs().compareTo(
        ((b['durationDays'] as int) - travelDays).abs(),
      ),
    );
    return {
      ...courses.first,
      'regionName': regionId,
      '_save': <String, dynamic>{},
    };
  }

  @override
  Future<({int courseId, String? shareToken})> save(
    Map<String, dynamic> savePayload,
  ) async => (courseId: 1, shareToken: 'test-token');

  /// 물어볼 지난 여행은 없다 — 홈에 들어설 때마다 "다녀오셨나요?" 모달이
  /// 뜨면 다른 테스트가 전부 그 모달에 가려 막힌다.
  /// 모달 자체는 trip_outcome_dialog_test.dart가 따로 확인한다
  @override
  Future<({double? remainingDays, List<Map<String, dynamic>> trips})>
  pendingTrips() async =>
      (remainingDays: null, trips: const <Map<String, dynamic>>[]);

  @override
  Future<double?> answerTripOutcome(
    int courseId, {
    required bool visited,
    String? comment,
  }) async => null;

  @override
  Future<List<Map<String, dynamic>>> savedCourseCards({
    String scope = 'ALL',
  }) async {
    final data = await MockDataSource.courses();
    // 서버는 최신순으로 정렬해 준다 — mock은 오래된 것부터라 뒤집는다
    return (data['savedCourses'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .reversed
        .toList();
  }

  @override
  Future<({Map<String, dynamic> saved, Map<String, dynamic> course})?>
  savedCourseDetail(String courseId) async {
    final data = await MockDataSource.courses();
    final saved = (data['savedCourses'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((s) => s['id'] == courseId)
        .firstOrNull;
    if (saved == null) return null;
    final course = (data['courses'] as List)
        .cast<Map<String, dynamic>>()
        .where((c) => c['id'] == saved['courseId'])
        .firstOrNull;
    if (course == null) return null;
    return (saved: saved, course: course);
  }

  @override
  Future<void> delete(String courseId) async {}
}

/// 알림은 비어 있다 — 홈이 배지를 그리려고 서버를 부르는데,
/// 안 덮으면 그 요청 타이머가 테스트가 끝날 때까지 남는다.
/// 알림 화면 자체는 notification_test.dart가 따로 확인한다
class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository() : super(Dio());

  @override
  Future<({List<AppNotification> notifications, int unreadCount})> fetch({
    int page = 0,
    int size = 20,
  }) async => (notifications: const <AppNotification>[], unreadCount: 0);

  @override
  Future<int> markRead(int notificationId) async => 0;

  @override
  Future<int> markAllRead() async => 0;
}

/// 기기 등록은 서버를 부르지 않는다 — 로그아웃·탈퇴가 이걸 타는데,
/// 안 덮으면 그 요청 타이머가 테스트가 끝날 때까지 남는다
class _FakePushRegistration implements PushRegistration {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeviceRepository implements DeviceRepository {
  @override
  Future<void> register(String token) async {}

  @override
  Future<void> unregister() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 실서버를 부르는 repository를 전부 가짜로 바꾼다.
/// 테스트 환경은 HTTP를 400으로 막아, 안 바꾸면 화면 플로우가 전부 끊긴다.
/// 계정 선택 창을 띄우지 않고 바로 성공을 돌려주는 구글 로그인.
///
/// 테스트는 이 버튼으로 플로우에 진입하므로 실제 SDK를 타면 안 된다.
class _FakeGoogleAuthService implements GoogleAuthService {
  @override
  Future<GoogleLoginResult> login() async => (
    idToken: 'test-id-token',
    email: 'test@example.com',
    displayName: '테스트',
    userId: 'test-user-id',
  );

  @override
  Future<void> logout() async {}
}

/// 서버 토큰 교환 — 테스트 환경은 HTTP가 400으로 막혀 실제 호출을 못 한다.
///
/// `isNewUser: true`로 둔다. 테스트들이 로그인 직후 온보딩(잔여 연차 입력)을
/// 지나 홈으로 가는 흐름을 검증하기 때문이다.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._storage);

  final TokenStorage _storage;

  @override
  Future<AuthTokens> loginWithSocial(
    SocialProvider provider,
    String socialAccessToken, {
    SocialProfile? profile,
    String? authorizationCode,
  }) async => const AuthTokens(
    accessToken: 'test-access',
    refreshToken: 'test-refresh',
    isNewUser: true,
  );

  @override
  Future<AuthTokens?> reissue() async => null;

  /// 서버는 부르지 않고 Keychain만 비운다 — 삭제가 실패하면 그대로 던져
  /// "토큰이 남았는데 로그인 화면으로 보내지 않는다"를 검증할 수 있게 한다
  @override
  Future<void> logout() => _storage.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _serverOverrides = [
  // 홈이 첫 화면 사진을 미리 받는다 — 테스트에서는 네트워크 없이 바로
  // 끝낸다. 실제 캐시를 쓰면 받기가 끝나지 않아 3초 제한 타이머가 남는다
  imagePrefetcherProvider.overrideWithValue((_) async {}),
  // 홈으로 넘어가기 전 첫 사진을 메모리에 푼다 — 실제로 풀면 디스크 캐시가
  // 열리며 캐시 폴더를 찾다 테스트가 끝난 뒤 예외가 난다
  placeThumbnailPrecacheProvider.overrideWithValue((_, _, _) async {}),
  // 이 파일의 테스트는 로그인 화면부터 시작하는 플로우를 본다. 앱의 실제 첫
  // 화면은 스플래시라 그대로 두면 스플래시 시간을 기다려야 하고, 테스트가 재는 것도
  // 스플래시가 아니다 — 초기 경로를 로그인으로 고정한다.
  // 스플래시 자체는 splash_test.dart 가 따로 검증한다
  initialRouteProvider.overrideWithValue(AppRoutes.login),
  googleAuthServiceProvider.overrideWithValue(_FakeGoogleAuthService()),
  deviceRepositoryProvider.overrideWithValue(_FakeDeviceRepository()),
  // OffwayApp.initState가 FirebaseMessaging을 직접 부른다 —
  // 덮지 않으면 테스트가 실제 SDK를 탄다
  pushRegistrationProvider.overrideWithValue(_FakePushRegistration()),
  notificationRepositoryProvider.overrideWithValue(
    _FakeNotificationRepository(),
  ),
  homeRepositoryProvider.overrideWithValue(_FakeHomeRepository()),
  policyRepositoryProvider.overrideWithValue(_FakePolicyRepository()),
  // 업데이트 확인은 애플을 부른다 — 여기서는 새 버전이 없는 것으로 둔다
  availableUpdateProvider.overrideWith((ref) async => null),
  regionListRepositoryProvider.overrideWithValue(_FakeRegionListRepository()),
  regionDetailRepositoryProvider.overrideWithValue(
    _FakeRegionDetailRepository(),
  ),
  leaveRepositoryProvider.overrideWithValue(_FakeLeaveRepository()),
  originSearchRepositoryProvider.overrideWithValue(
    _FakeOriginSearchRepository(),
  ),
  regionRecommendRepositoryProvider.overrideWithValue(
    _FakeRegionRecommendRepository(),
  ),
  courseRepositoryProvider.overrideWithValue(_FakeCourseRepository()),
  authRepositoryProvider.overrideWith(
    (ref) => _FakeAuthRepository(ref.watch(secureStorageProvider)),
  ),
];

/// 위저드 첫 단계(출발지)를 통과한다.
///
/// 출발지는 코스 추천의 1/5 단계라 뒤의 어느 단계를 재든 먼저 지난다.
/// 검색은 손이 멈춘 뒤(디바운스 300ms) 한 번만 나가므로 그만큼 흘려보낸다.
Future<void> _passOriginStep(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '서울');
  await tester.pump(const Duration(milliseconds: 350)); // 디바운스
  await tester.pump();
  await tester.tap(find.text('서울역').last);
  await tester.pump();
  await tester.tap(find.text('다음'));
  // 전환이 끝나야 출발지 화면이 트리에서 빠진다 — 400ms 만 흘리면 두 화면의
  // '다음' 버튼이 함께 잡혀 뒤 화면을 재는 finder 가 전부 어긋난다
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // Keychain 플러그인은 테스트 환경에 없으므로 인메모리 구현으로 대체
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
  });
  testWidgets('앱 실행 시 로그인 화면이 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Offway'), findsOneWidget); // 워드마크 로고
    expect(find.text('연차로 떠나는 로컬 여행'), findsOneWidget);
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('Apple로 시작하기'), findsOneWidget);
    expect(find.text('Google로 시작하기'), findsOneWidget);
  });

  testWidgets('소셜 로그인 버튼을 누르면 잔여연차 온보딩으로 이동한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();

    expect(find.text('남은 연차를 입력해 주세요'), findsOneWidget);
  });

  testWidgets('온보딩 연차가 한계에 닿으면 왜 못 바꾸는지 토스트로 알린다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();

    // 0일까지 내린 뒤 한 번 더 누르면 하한 안내가 뜬다
    await tester.tap(find.text('15일'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('0일'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.textContaining('0일보다 적게'), findsOneWidget);

    // 상한(99일)에서도 마찬가지
    await tester.tap(find.text('0일'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('99일'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.textContaining('최대 99일까지'), findsOneWidget);
  });

  testWidgets('온보딩에서 연차를 조절하고 시작하면 홈으로 이동한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();

    expect(find.text('15일'), findsOneWidget);
    // 반차 단위(0.5일)로 증감
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('15.5일'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('15일'), findsOneWidget);

    // 숫자를 눌러 직접 입력 (소수점 허용, 0.5 단위로 보정)
    await tester.tap(find.text('15일'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '7.3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('7.5일'), findsOneWidget);

    // 빈 여백을 탭해도 입력이 확정된다
    await tester.tap(find.text('7.5일'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('남은 연차를 입력해 주세요'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(TextField), findsNothing); // 입력 모드 종료
    expect(find.text('3일'), findsOneWidget);

    await tester.tap(find.text('시작하기'));
    await tester.pump();
    // rootBundle 로드가 FakeAsync에 갇힌 채 전역 캐시에 남지 않도록 실제 비동기로 완료시킨다
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    // 홈은 네트워크 이미지 로드가 있어 pumpAndSettle 대신 유한 pump 사용
    await tester.pump();
    expect(find.text('남은 연차 일수'), findsOneWidget); // 홈 도착
  });

  testWidgets('홈에 mock 사용자·추천 여행지가 표시된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    // rootBundle 로드(실제 I/O)가 FakeAsync에서 멈추지 않도록 runAsync로 대기
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    // 네트워크 이미지 로드가 있어 pumpAndSettle 대신 유한 pump 사용
    await tester.pump();

    expect(find.text('11일'), findsOneWidget); // mock 잔여연차
    expect(find.textContaining('어디로 떠나볼까요?'), findsOneWidget);
    expect(find.text('이번달 추천 여행지'), findsOneWidget);
    // 카드 제목과 썸네일 위 오버레이 두 곳에 지역명이 나온다
    expect(find.text('정선 · 강원'), findsNWidgets(2));
    expect(find.text('숙박비 30% 지원'), findsOneWidget);

    // 히어로 CTA는 브랜드 하늘색이 아니라 검정(Neutral/22)이다.
    // 다른 화면 CTA와 같아 보여 무심코 Primary로 바꾸기 쉬워 고정해 둔다.
    final cta = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('바로 추천받기'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(cta.style?.backgroundColor?.resolve({}), const Color(0xFF303030));
  });

  testWidgets('홈 아래에 "이번 연차엔 여기 어때요?" 카드가 깔린다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google로 시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 섹션이 화면 밖에 있으므로 끌어올려 찾는다
    final section = find.text('이번 연차엔 여기 어때요?');
    await tester.scrollUntilVisible(
      section,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(section, findsOneWidget);

    // 시안 실측 190×220 — 카드가 그 크기로 깔린다
    final card = find.byType(LeavePickCard);
    expect(card, findsWidgets);
    expect(tester.getSize(card.first), const Size(190, 220));
  });

  testWidgets('하단 탭에서 마이로 이동하고 로그아웃하면 로그인 화면으로 돌아간다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('마이'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.textContaining('반가워요!'), findsOneWidget);
    expect(find.text('개인정보처리방침'), findsOneWidget);
    expect(find.text('회원탈퇴'), findsOneWidget);

    // 로그아웃은 확인 다이얼로그를 거친다
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    // 모달이 열리면 '로그아웃'이 메뉴와 제목 두 곳에 뜬다
    expect(find.text('정말 로그아웃 할까요?'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('연차로 떠나는 로컬 여행'), findsOneWidget); // 로그인 화면
  });

  testWidgets('로그아웃이 실패하면 로그인 화면으로 넘어가지 않고 알린다', (tester) async {
    // 토큰이 남은 채 로그인 화면으로 보내면 로그아웃된 줄 알게 되므로
    FlutterSecureStoragePlatform.instance = _FailingSecureStoragePlatform();

    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('마이'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.textContaining('로그아웃에 실패'), findsOneWidget);
    expect(find.byType(MyScreen), findsOneWidget); // 마이 화면에 그대로 머문다
    expect(find.text('연차로 떠나는 로컬 여행'), findsNothing);
  });

  testWidgets('하단 탭에서 내 코스로 이동하면 저장한 코스가 확정 여부와 함께 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('내 코스'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    Finder inCourses(String text) => find.descendant(
      of: find.byType(MyCoursesScreen),
      matching: find.text(text),
    );

    // 서브탭 3종이 있고, 최신순(영월 미확정)이 위에 온다
    expect(inCourses('전체'), findsOneWidget);
    expect(inCourses('예정된 여행'), findsOneWidget);
    expect(inCourses('지난 여행'), findsOneWidget);
    expect(inCourses('영월 · 당일치기'), findsOneWidget);
    expect(inCourses('날짜 미정'), findsOneWidget);
    expect(inCourses('정선 · 2박3일'), findsOneWidget);
    expect(inCourses('2026.7.20 - 7.22'), findsOneWidget);
    // 끝난 여행에는 완료 뱃지가 붙는다 (mock 정선은 과거 날짜)
    expect(inCourses('여행완료'), findsOneWidget);
  });

  testWidgets('내 코스에서 확정 코스를 열면 날짜와 사용 연차가 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('내 코스'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 확정 코스(정선)는 목록 아래쪽이라 스크롤해서 누른다
    final coursesList = find.descendant(
      of: find.byType(MyCoursesScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('정선 · 2박3일'),
      200,
      scrollable: coursesList,
    );
    // 떠 있는 하단 탭바가 카드를 덮지 않도록 한 번 더 올린다
    await tester.drag(coursesList, const Offset(0, -150));
    await tester.pump();
    await tester.tap(find.text('정선 · 2박3일'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.textContaining('정선 여행'), findsOneWidget);
    // 목록 카드(뒤에 남아 있음)와 상세가 같은 날짜 표기를 쓴다
    expect(find.text('2026.7.20 - 7.22'), findsWidgets);
    // 서버 계산이 stub에서 실패하므로 평일 수(월~수=3일) 폴백이 보인다
    expect(find.text('사용 연차 일수 3일'), findsOneWidget);
    expect(find.text('Day 3'), findsOneWidget);

    // 편집 시트에 날짜 수정과 삭제가 들어 있다
    await tester.tap(find.bySemanticsLabel('코스 편집'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('여행날짜 수정'), findsOneWidget);
    expect(find.text('코스 삭제'), findsOneWidget);
    // 시안 실측: 두 항목 상단 간격 52 (아이콘 배경 32 + 여백 20)
    final first = tester.getRect(find.text('여행날짜 수정'));
    final second = tester.getRect(find.text('코스 삭제'));
    expect(second.top - first.top, 52);
  });

  testWidgets('미확정 코스는 날짜 대신 일정 정하기 링크가 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('내 코스'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 최신순 기본이라 미확정(영월)이 맨 위
    await tester.tap(find.text('영월 · 당일치기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.textContaining('영월 여행'), findsOneWidget);
    expect(find.text('여행 일정 정하기'), findsOneWidget);
    // 당일치기는 Day 탭이 하나뿐
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 2'), findsNothing);
  });

  testWidgets('미확정 코스에서 여행 일정 정하기를 누르면 캘린더로 이동한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('내 코스'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 미확정(영월) 코스로 들어가 일정 정하기 링크를 누른다
    await tester.tap(find.text('영월 · 당일치기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    await tester.tap(find.text('여행 일정 정하기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('여행 날짜 선택'), findsOneWidget);
    expect(find.text('최대 2박3일까지 선택할 수 있어요'), findsOneWidget);

    // 날짜를 고르기 전에는 선택 완료가 비활성
    final done = find.widgetWithText(FilledButton, '선택 완료');
    expect(tester.widget<FilledButton>(done).onPressed, isNull);

    // 시작일 하나만 고르면 코스 길이(당일치기=하루)만큼 범위가 완성된다.
    // 다음 달 중순(15일)을 쓴다 — 월말에 실행돼도 안전하고 그리드에서 유일하다.
    // 아래 코스 상세 화면이 트리에 남아 같은 숫자가 또 있을 수 있으므로
    // 화면에 실제로 보이는 셀만 대상으로 한다
    final today = DateUtils.dateOnly(DateTime.now());
    final nextMonth = DateTime(today.year, today.month + 1);
    await tester.scrollUntilVisible(
      find.text('${nextMonth.year}년 ${nextMonth.month}월'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(find.text('15').hitTestable());
    await tester.pump();
    expect(find.text('가는날'), findsOneWidget);
    expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
  });

  testWidgets('하단 탭 전환은 좌우 슬라이드 없이 한 프레임에 끝난다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 홈 → 마이: 한 프레임 뒤 이미 제자리(dx=0)에 있어야 한다
    await tester.tap(find.text('마이'));
    await tester.pump();
    expect(find.byType(MyScreen), findsOneWidget);
    expect(tester.getTopLeft(find.byType(MyScreen)).dx, 0);

    await tester.pumpAndSettle();

    // 마이 → 홈도 마찬가지
    await tester.tap(find.text('홈'));
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.getTopLeft(find.byType(HomeScreen)).dx, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('홈 더보기 → 추천 여행지 목록에서 카테고리로 필터한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 시안에서 '더보기' 글자가 빠지고 쉐브론만 남았다 — 라벨로 찾는다
    await tester.tap(find.byKey(const Key('home-region-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 홈은 전환 없는 페이지라 목록 아래에 그대로 남아있다(불투명 배경에 가려짐).
    // 같은 문구가 홈에도 있으므로 목록 화면 안에서만 찾는다
    Finder inList(String text) => find.descendant(
      of: find.byType(RegionListScreen),
      matching: find.text(text),
    );
    // 지역명은 카드 제목과 썸네일 오버레이 두 곳에 나온다 — 제목만 겨냥한다
    Finder titleInList(String text) => find.descendant(
      of: find.byType(RegionListScreen),
      matching: find.byWidgetPredicate(
        (w) => w is Text && w.data == text && w.style?.fontSize == 15,
      ),
    );

    // 목록 화면: 헤더 + mock 5개 지역
    expect(inList('이번달 추천 여행지'), findsOneWidget);
    expect(titleInList('정선 · 강원'), findsOneWidget);
    // 마지막 지역은 뷰포트 아래라 스크롤해서 확인
    await tester.scrollUntilVisible(
      titleInList('영양 · 경북'),
      200,
      scrollable: find.descendant(
        of: find.byType(RegionListScreen),
        matching: find.byType(Scrollable),
      ),
    );
    expect(titleInList('영양 · 경북'), findsOneWidget);

    // 카테고리 필터는 지역별 콘텐츠 분포(실데이터) 기준으로 동작.
    // 칩 줄은 그리드 밖에 고정돼 있어 스크롤과 무관하게 늘 보인다
    await tester.tap(inList('체험'));
    await tester.pump();
    // 위에서 영양까지 내려둔 스크롤이 남아 있으므로 정선을 화면 안으로 올린다.
    // 오버레이 때문에 지역명이 두 번 나오므로 제목만 겨냥해야 단일 대상이 된다
    await tester.scrollUntilVisible(
      titleInList('정선 · 강원'),
      -200,
      scrollable: find.descendant(
        of: find.byType(RegionListScreen),
        matching: find.byType(Scrollable),
      ),
    );
    // 오버레이가 붙어 지역명이 두 번 나오므로 카드 제목만 겨냥한다
    expect(titleInList('정선 · 강원'), findsOneWidget); // 체험 11건
  });

  testWidgets('홈에서 지역 카드를 누르면 지역 상세로 이동한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 지역 카드는 뷰포트 아래라 스크롤해서 올린 뒤 탭
    await tester.scrollUntilVisible(
      find.text('정선 · 강원').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('정선 · 강원').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 시안: 제목·뱃지 바로 아래가 소개 본문이다(한 줄 제목은 시안에 없다)
    expect(find.textContaining('삼탄아트마인'), findsOneWidget);
    expect(find.text('정선 매력 포인트 장소'), findsOneWidget);

    // 화면 끝 안내는 뷰포트 아래라 스크롤해서 확인
    await tester.scrollUntilVisible(
      find.text('아직 발견할 매력이 많은 지역이에요'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('지역만의 숨은 매력을 발견해보세요'), findsOneWidget);
  });

  testWidgets('바로 추천받기 → 날짜 갈림길에서 선택해야 다음이 활성화된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 400)); // 전환 애니메이션 완료
    await tester.pump();

    await tester.tap(find.text('바로 추천받기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 페이지 전환
    await _passOriginStep(tester);

    expect(find.text('여행 날짜가 있나요?'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);

    // 선택 전에는 다음 버튼 비활성
    final nextButton = find.widgetWithText(FilledButton, '다음');
    expect(tester.widget<FilledButton>(nextButton).onPressed, isNull);

    await tester.tap(find.text('아직 안 정했어요'));
    await tester.pump();
    expect(tester.widget<FilledButton>(nextButton).onPressed, isNotNull);
  });

  testWidgets('캘린더에서 2박3일 범위를 선택하면 선택 완료가 활성화된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('바로 추천받기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _passOriginStep(tester);

    await tester.tap(find.text('가고싶은 날짜가 있어요'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('여행 날짜 선택'), findsOneWidget);
    expect(find.text('최대 2박3일까지 선택할 수 있어요'), findsOneWidget);

    final done = find.widgetWithText(FilledButton, '선택 완료');
    expect(tester.widget<FilledButton>(done).onPressed, isNull);

    // 다음달 1일~2일 선택 (과거 날짜 회피, 첫 번째 달력의 셀은 중복 텍스트 가능성 → first)
    final nextMonth = DateTime.now().month == 12
        ? '1월'
        : '${DateTime.now().month + 1}월';
    await tester.scrollUntilVisible(
      find.textContaining(nextMonth),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    // 다음달 헤더 아래의 1, 2일 탭
    await tester.tap(find.text('1').last);
    await tester.pump();
    // 정책: 가는날+2일 초과 날짜는 비활성 — 탭해도 반응 없음
    await tester.tap(find.text('5').last);
    await tester.pump();
    expect(find.text('오는날'), findsNothing);
    await tester.tap(find.text('2').last);
    await tester.pump();

    expect(find.text('가는날'), findsOneWidget);
    expect(find.text('오는날'), findsOneWidget);
    expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
  });

  testWidgets('기간스타일: 당일치기는 바로, 연차만은 스테퍼 완료 후 다음이 활성화된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('바로 추천받기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _passOriginStep(tester);

    await tester.tap(find.text('아직 안 정했어요'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pump();
    // 전환이 끝나기 전에는 카드 탭이 흡수되므로 화면이 자리잡을 때까지 기다린다
    await tester.pumpAndSettle();

    expect(find.text('어떻게 떠날까요?'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('남은 연차일수 11일'), findsOneWidget); // mock 연차

    // 이전 화면(갈림길)의 '다음'이 트리에 남아있을 수 있어 최상단 것만 조회
    final next = find.widgetWithText(FilledButton, '다음').last;
    expect(tester.widget<FilledButton>(next).onPressed, isNull);

    // 당일치기: 모달 없이 바로 완료
    await tester.tap(find.text('당일치기 · 연차'));
    await tester.pump();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

    // 연차만: 일수 선택 모달에서 완료해야 유지
    // 세 번째 카드는 작은 화면에서 액션 영역 아래로 밀려 있어 스크롤해서 누른다
    await tester.scrollUntilVisible(
      find.text('연차만 (주말 미포함)'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('연차만 (주말 미포함)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 시트 애니메이션
    expect(find.text('평일 연차, 며칠 쓸까요?'), findsOneWidget);
    // 2일·3일 두 버튼 중에서 고른다 (정책: 최소 2일 ~ 최대 2박3일)
    expect(find.text('1박2일'), findsOneWidget);
    expect(find.text('2박3일'), findsOneWidget);
    await tester.tap(find.text('1박2일'));
    await tester.pump();
    await tester.tap(find.text('완료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
  });

  testWidgets('이동수단 → 일정밀도 → 로딩 → 후보지역까지 위저드가 이어진다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Google로 시작하기'),
    ); // 카카오·Apple은 실제 SDK 호출이라 stub인 구글로 진입
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('바로 추천받기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _passOriginStep(tester);
    await tester.tap(find.text('아직 안 정했어요'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('당일치기 · 연차'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '다음').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // O-05 이동수단
    expect(find.text('어떻게 이동하세요?'), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget);
    await tester.tap(find.text('대중교통'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '다음').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // O-06 일정밀도
    expect(find.text('내가 선호하는 여행 스타일은?'), findsOneWidget);
    expect(find.text('5/5'), findsOneWidget);
    await tester.tap(find.text('널널한 일정'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '다음').last);
    await tester.pump();

    // O-07 로딩은 여기서 보지 않는다 — GPS 조회를 걷어내며(core #591)
    // 남은 비동기가 목 호출뿐이라, 화면 전환이 끝날 때쯤 결과도 와 있어
    // 로딩을 붙잡을 시점이 없다. 로딩 화면 자체는
    // `candidates_loading_test.dart` 가 느린 응답으로 고정한다

    // 검색(mock 로드)이 끝나면 같은 화면이 결과로 바뀐다
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // O-08 후보지역
    // 개수만 브랜드색으로 강조하느라 한 Text를 조각으로 나눠 담는다
    expect(find.textContaining('조건에 맞는 여행지'), findsOneWidget);
    expect(find.text('정선 · 강원'), findsOneWidget);
    expect(find.text('폐광촌에서 다시 태어난 마을'), findsOneWidget);
    expect(find.text('추천순'), findsOneWidget); // 정렬 칩
    // 카드가 커서 두 번째 후보는 첫 화면 밖에 있다
    await tester.scrollUntilVisible(
      find.text('영월 · 강원'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('영월 · 강원'), findsOneWidget);
    // 다음 단계는 첫 카드에서 이어가므로 되돌려 놓는다
    await tester.scrollUntilVisible(
      find.text('정선 · 강원'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );

    // O-09 코스확정: 정선 카드 탭 → 당일치기 코스 (위저드에서 당일치기 선택했음)
    await tester.tap(find.text('정선 · 강원'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.textContaining('정선, 당일치기'), findsOneWidget);
    // 담기 버튼은 고정이 아니라 목록 끝에 따라오므로 스크롤해야 보인다
    await tester.scrollUntilVisible(
      find.text('내 코스에 담기'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('내 코스에 담기'), findsOneWidget);
    // 장소 리스트는 뷰포트 아래라 스크롤 후 확인
    await tester.scrollUntilVisible(
      find.text('가리왕산자연휴양림'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('가리왕산자연휴양림'), findsOneWidget); // mock 실데이터 코스
    expect(find.text('Day 1'), findsNothing); // 당일치기는 Day 탭 없음

    // 담기 전에도 장소를 눌러 볼 수 있어야 한다. 누르면 **운영 정보 시트**가
    // 뜨고, 시트 안 제목을 눌러야 상세로 간다 — 담은 뒤 화면과 같은 흐름이다
    // (QA 9/11). 예전에는 여기서만 바로 상세로 넘어갔다.
    //
    // 목록 끝까지 스크롤한 상태라 첫 장소는 화면 위로 벗어나 있다.
    // ListView는 벗어난 항목도 트리에 남겨 finder는 찾지만 탭은 닿지 않으므로
    // scrollUntilVisible이 '이미 보인다'고 보고 움직이지 않는다 — 직접 내린다
    final place = find.text('가리왕산자연휴양림');
    final list = find.byType(Scrollable).last;
    for (var i = 0; i < 8 && tester.getCenter(place).dy < 0; i++) {
      await tester.drag(list, const Offset(0, 200));
      await tester.pump();
    }
    await tester.tap(place);
    await tester.pumpAndSettle();
    expect(find.byType(PlaceInfoSheet), findsOneWidget);

    // 시트 안 제목을 누르면 상세로 간다 — 목록의 같은 이름과 헷갈리지 않게
    // 시트 안쪽에서 찾는다
    await tester.tap(
      find.descendant(
        of: find.byType(PlaceInfoSheet),
        matching: find.text('가리왕산자연휴양림'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PoiDetailScreen), findsOneWidget);
  });

  testWidgets('2박3일 코스는 Day 탭으로 일자별 장소를 전환한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    // 코스 화면 직접 진입 (3일 희망 → 정선 2박3일 코스 매칭)
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.push('/course/정선?days=3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 지역·기간만 브랜드색으로 강조하느라 한 Text를 조각으로 나눠 담는다
    expect(find.textContaining('추천코스입니다'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Day 1'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.scrollUntilVisible(
      find.text('가리왕산자연휴양림'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('가리왕산자연휴양림'), findsOneWidget); // Day1 첫 장소

    await tester.scrollUntilVisible(
      find.text('Day 2'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Day 2'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('하이원리조트'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('하이원리조트'), findsOneWidget); // Day2 숙박
    expect(find.text('가리왕산자연휴양림'), findsNothing);
  });

  testWidgets('코스 화면에서 내 코스에 담기를 누르면 내 코스 탭으로 이동한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _serverOverrides, child: const OffwayApp()),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.push('/course/정선?days=3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // 담기 버튼은 목록 끝에 따라오므로 스크롤해서 누른다
    await tester.scrollUntilVisible(
      find.text('내 코스에 담기'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('내 코스에 담기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 프리셋 경로(날짜 미지정)라 담기 전에 여행 날짜부터 확정한다
    expect(find.text('여행 날짜 선택'), findsOneWidget);
    expect(find.textContaining('날씨예보, 휴무일'), findsOneWidget);
    final done = find.widgetWithText(FilledButton, '선택 완료');
    expect(tester.widget<FilledButton>(done).onPressed, isNull); // 날짜 전엔 비활성

    // 오늘을 시작일로 고르면 코스 길이(3일)만큼 범위가 완성된다.
    //
    // 달 끝자락이면 그 주가 달력 영역 밖으로 밀린다. ListView는 잘린 칸도
    // 트리에 남겨 finder는 찾지만 탭은 닿지 않으므로, 달력 안에 완전히
    // 들어올 때까지 끌어올린다. 오늘이 몇째 주냐에 따라 갈리면 안 된다.
    //
    // **달력 안으로 좁혀 찾는다.** push 뒤에도 코스 화면이 트리에 남아,
    // 매달 1일에는 트리 전체의 첫 '1'이 뒤 화면의 장소 번호가 된다 —
    // 화면 밖 좌표를 탭하며 달만 바뀌면 터지는 테스트였다
    final today = find
        .descendant(
          of: find.byType(TripDateRangePicker),
          matching: find.text('${DateTime.now().day}'),
        )
        .first;
    final calendar = find.descendant(
      of: find.byType(TripDateRangePicker),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 6; i++) {
      final area = tester.getRect(find.byType(TripDateRangePicker));
      if (area.contains(tester.getCenter(today))) break;
      await tester.drag(calendar, const Offset(0, -80));
      await tester.pump();
    }
    await tester.tap(today);
    await tester.pump();
    expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
    await tester.tap(done);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 내 코스 목록에 도착 (담기 화면으로 되돌아가지 않는다)
    expect(find.byType(MyCoursesScreen), findsOneWidget);
    expect(find.text('내 코스에 담기'), findsNothing);
    // 전환 중에는 이전·새 Scaffold 양쪽에 토스트가 그려질 수 있어 개수는 세지 않는다
    expect(find.textContaining('내 코스에 담았어요'), findsWidgets);
  });
}
