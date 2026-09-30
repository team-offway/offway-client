import 'dart:async';

import 'package:dio/dio.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offway/features/course/data/course_repository.dart';
import 'package:offway/features/trip_activity/application/trip_activity_controller.dart';
import 'package:offway/features/trip_activity/data/live_activity_repository.dart';
import 'package:offway/features/trip_activity/data/trip_activity_service.dart';
import 'package:offway/features/trip_activity/domain/trip_countdown.dart';
import 'package:offway/features/course/application/course_providers.dart';

/// 예정 코스를 읽어 **어느 여행을 잠금화면에 띄울지** 정하는 자리.
///
/// 고르는 규칙 자체는 [TripCountdown] 테스트가 잠근다. 여기서는 배선을 본다 —
/// 어느 범위를 읽는지, 띄울 것이 없을 때 내리는지.
class _FakeService implements TripActivityService {
  _FakeService({this.available = true, this.widgetAvailable = true});

  final bool available;
  final bool widgetAvailable;
  TripCountdown? started;
  int endCount = 0;

  /// 컨트롤러가 걸어 둔 토큰 수신자 — 테스트가 네이티브인 척 부른다
  PushTokenListener? listener;

  /// 기기의 push-to-start 토큰 수신자 (core #585)
  PushToStartTokenListener? pushToStartListener;

  @override
  void listenPushToken(
    PushTokenListener listener, {
    PushToStartTokenListener? onPushToStartToken,
  }) {
    this.listener = listener;
    pushToStartListener = onPushToStartToken;
  }

  @override
  Future<bool> isAvailable() async => available;

  /// 띄우기가 불린 횟수 — 앱을 켤 때 두 번 불리면 안 된다(#395)
  int startCalls = 0;

  @override
  Future<bool> start(TripCountdown trip, {DateTime? now}) async {
    startCalls++;
    started = trip;
    return true;
  }

  @override
  Future<bool> end() async {
    endCount++;
    return true;
  }

  /// 위젯 저장소에 마지막으로 쓴 목록 — 쓴 적 없으면 null
  List<TripCountdown>? widgetTrips;

  /// 위젯에 실린 일자별 날씨·장소 — 코스 id 별
  Map<String, List<Map<String, Object?>>> widgetDays = const {};
  int clearWidgetCount = 0;
  int signedInCount = 0;

  @override
  Future<bool> isWidgetAvailable() async => widgetAvailable;

  @override
  Future<bool> setWidgetTrips(
    List<TripCountdown> trips, {
    Map<String, List<Map<String, Object?>>> daysByCourse = const {},
  }) async {
    widgetTrips = trips;
    widgetDays = daysByCourse;
    return true;
  }

  @override
  Future<bool> markWidgetSignedIn() async {
    signedInCount++;
    return true;
  }

  @override
  Future<bool> clearWidget() async {
    clearWidgetCount++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // push-to-start 등록 기억(RegistrationMemo)이 읽고 쓰는 Keychain 대역.
  // 테스트 하나 안에서는 컨테이너를 새로 만들어도 같은 기기처럼 남는다
  const keychain = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late Map<String, String> keychainStore;
  setUp(() {
    keychainStore = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keychain, (call) async {
          final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
          final key = args['key'] as String?;
          return switch (call.method) {
            'read' => keychainStore[key],
            'write' => () {
              keychainStore[key!] = args['value'] as String;
              return null;
            }(),
            'delete' => keychainStore.remove(key),
            _ => null,
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keychain, null);
  });

  // start() 가 앱 생명주기 옵저버를 단다 — 바인딩이 없으면 그 자리에서 터진다
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 20);

  Map<String, dynamic> card({
    required String id,
    required String start,
    String? end,
    String region = '정선군',
  }) => {
    'courseId': id,
    'regionName': region,
    'startDate': start,
    'endDate': ?end,
    'durationLabel': '당일치기',
  };

  ProviderContainer containerWith(
    List<Map<String, dynamic>> cards,
    _FakeService service, {
    _FakeRepository? repository,
    _FakeCourseRepository? courses,
  }) {
    final c = ProviderContainer(
      // 실패를 기다리는 테스트가 있다 — 기본 자동 재시도(최대 10번)가 돌면
      // 결과가 늦게 와 시간을 넘긴다. 앱은 전역 규칙(`providerRetry`)을 쓴다
      retry: (_, _) => null,
      overrides: [
        tripActivityServiceProvider.overrideWithValue(service),
        liveActivityRepositoryProvider.overrideWithValue(
          repository ?? _FakeRepository(),
        ),
        // 위젯에 실을 날씨·장소를 읽는 자리 — 서버를 부르지 않게 막는다
        courseRepositoryProvider.overrideWithValue(
          courses ?? _FakeCourseRepository(),
        ),
        // 목록을 나중에 바꿔 다시 읽게 할 수 있게 같은 리스트를 돌려준다
        savedCoursesProvider('UPCOMING').overrideWith((ref) async => cards),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 마이크로태스크를 비운다 — 기다리지 않는 등록이 끝나길
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('앱을 켤 때 맞추기는 한 번이다 — 목록이 이미 있든 받는 중이든', () async {
    // 예전에는 start() 가 바로 한 번, 목록이 로딩 → 데이터로 바뀔 때 또 한 번
    // 맞춰 잠금화면 띄우기와 코스 상세 조회가 두 번씩 나갔다(#395)
    final service = _FakeService();
    // start() 는 실제 시각으로 맞춘다 — 사흘 뒤 떠나는 여행이어야 띄운다
    final soon = DateTime.now().add(const Duration(days: 3));
    final iso =
        '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
    final c = containerWith([card(id: '1', start: iso)], service);
    c.read(tripActivityControllerProvider).start();
    for (var i = 0; i < 5; i++) {
      await settle();
    }
    expect(service.startCalls, 1);
  });

  test('가장 가까운 예정 여행을 띄운다', () async {
    final service = _FakeService();
    final c = containerWith([
      card(id: '1', start: '2026-09-25', region: '홍천군'),
      card(id: '2', start: '2026-09-22', region: '가평군'),
    ], service);

    await c.read(tripActivityControllerProvider).sync(now: now);

    expect(service.started?.regionName, '가평군');
  });

  test('띄울 것이 없으면 떠 있던 것을 내린다', () async {
    // 끝난 여행이 잠금화면에 남아 있을 이유가 없다
    final service = _FakeService();
    final c = containerWith([], service);

    await c.read(tripActivityControllerProvider).sync(now: now);

    expect(service.started, isNull);
    expect(service.endCount, 1);
  });

  test('코스를 못 읽으면 떠 있던 것을 내린다', () async {
    // **서버가 실패한다고 그냥 두지 않는다.** 무엇을 띄울지 모르는 채로
    // 두면 지난 여행 D-day 가 잠금화면에 무기한 남는다
    final service = _FakeService();
    final c = ProviderContainer(
      // 실패를 기다리는 테스트가 있다 — 기본 자동 재시도(최대 10번)가 돌면
      // 결과가 늦게 와 시간을 넘긴다. 앱은 전역 규칙(`providerRetry`)을 쓴다
      retry: (_, _) => null,
      overrides: [
        tripActivityServiceProvider.overrideWithValue(service),
        // Future.error 로 준다 — `async => throw` 는 로딩 상태로 남아
        // 컨테이너가 정리될 때 StateError 가 대신 튀어나온다
        savedCoursesProvider('UPCOMING').overrideWith(
          (ref) => Future<List<Map<String, dynamic>>>.error(Exception('500')),
        ),
      ],
    );
    addTearDown(c.dispose);

    // 삼키지 않고 위로 알린다 — syncInBackground 가 받아 적는다
    Object? thrown;
    try {
      await c.read(tripActivityControllerProvider).sync(now: now);
    } on Object catch (e) {
      thrown = e;
    }
    // 어떤 오류인지는 보지 않는다 — 여기서 확인할 것은 '삼키지 않는다'다
    expect(thrown, isNotNull);

    expect(service.endCount, 1);
    expect(service.started, isNull);
  });

  test('너무 먼 여행뿐이면 내린다', () async {
    final service = _FakeService();
    final c = containerWith([card(id: '1', start: '2026-12-01')], service);

    await c.read(tripActivityControllerProvider).sync(now: now);

    expect(service.started, isNull);
    expect(service.endCount, 1);
  });

  test('날짜 없는 코스는 건너뛴다 — 일정 미확정', () async {
    final service = _FakeService();
    final c = containerWith([
      {'courseId': '1', 'regionName': '태안군'},
      card(id: '2', start: '2026-09-22', region: '가평군'),
    ], service);

    await c.read(tripActivityControllerProvider).sync(now: now);

    expect(service.started?.regionName, '가평군');
  });

  group('push-to-start 등록 (core #585)', () {
    // 서버가 **앱을 안 열어도** 카드를 처음 띄우려면 기기 토큰을 알아야 한다.
    // 카드 토큰(#577)과 달리 코스가 없고, 카드가 없어도 온다

    /// 메모 확인 → 등록 → 기억까지 채널 왕복이 여럿이라 한 번으로는 모자라다
    Future<void> settleAll() async {
      for (var i = 0; i < 6; i++) {
        await settle();
      }
    }

    test('같은 토큰이 다시 와도 이레 안이면 올리지 않는다', () async {
      // iOS 는 앱을 켤 때마다 같은 값을 준다 — 그때마다 다시 보내고 있었다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();
      addTearDown(controller.dispose);

      service.pushToStartListener!('80a1b2');
      await settleAll();
      service.pushToStartListener!('80a1b2');
      await settleAll();

      expect(repo.pushToStartRegistered, ['80a1b2']);
    });

    test('토큰이 바뀌면 올린다', () async {
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();
      addTearDown(controller.dispose);

      service.pushToStartListener!('80a1b2');
      await settleAll();
      service.pushToStartListener!('c3d4e5');
      await settleAll();

      expect(repo.pushToStartRegistered, ['80a1b2', 'c3d4e5']);
    });

    test('로그아웃 뒤 같은 토큰이 오면 다시 올린다 — 다음 사람의 계정으로', () async {
      final service = _FakeService();
      final repo = _FakeRepository();
      final first = containerWith([], service, repository: repo);
      final controller = first.read(tripActivityControllerProvider)..start();
      service.pushToStartListener!('80a1b2');
      await settleAll();
      expect(repo.pushToStartRegistered, ['80a1b2']);

      await controller.stop(); // 로그아웃 — 등록도 지우고 기억도 잊는다
      await settleAll();
      expect(repo.pushToStartUnregistered, ['80a1b2']);

      // 같은 기기, 다른 사람이 로그인했다
      final again = _FakeService();
      final second = containerWith([], again, repository: repo);
      final next = second.read(tripActivityControllerProvider)..start();
      addTearDown(next.dispose);
      again.pushToStartListener!('80a1b2');
      await settleAll();

      expect(repo.pushToStartRegistered, ['80a1b2', '80a1b2']);
    });

    test('토큰을 받기 전에 로그아웃해도 앞 실행의 기억을 지운다', () async {
      // 앞 실행이 적어 둔 기억이 남으면 다음 사람의 등록이 건너뛰어진다
      keychainStore['push_to_start_registered'] =
          '80a1b2|${DateTime.now().toUtc().toIso8601String()}';
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();
      await controller.stop(); // 이번 실행에서는 토큰이 아직 안 왔다
      await settleAll();

      expect(keychainStore.containsKey('push_to_start_registered'), isFalse);
    });

    test('세션 중에 토큰이 오면 서버에 올린다', () async {
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();
      addTearDown(controller.dispose);

      service.pushToStartListener!('80a1b2');
      await settle();

      expect(repo.pushToStartRegistered, ['80a1b2']);
    });

    test('로그인 전에 온 토큰은 세션이 열릴 때 올린다', () async {
      // 기기 토큰은 앱을 켜자마자 온다 — 대개 로그인보다 먼저다. 그때
      // 올리면 JWT 가 없어 403 이고, 버리면 이 기기는 앱을 다시 켤 때까지
      // 서버가 카드를 못 띄운다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider);
      addTearDown(controller.dispose);

      service.pushToStartListener!('80a1b2'); // 아직 start() 전이다
      await settle();
      expect(repo.pushToStartRegistered, isEmpty);

      controller.start();
      await settle();

      expect(repo.pushToStartRegistered, ['80a1b2']);
    });

    test('카드가 없어도 올린다', () async {
      // 이것이 push-to-start 의 요점이다 — 띄울 카드가 없는 상태에서
      // 서버가 처음 띄울 열쇠를 쥔다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();
      addTearDown(controller.dispose);
      await controller.sync(now: now);

      service.pushToStartListener!('80a1b2');
      await settle();

      expect(repo.pushToStartRegistered, ['80a1b2']);
      expect(service.started, isNull); // 띄운 카드는 없다
    });

    test('로그아웃하면 이 기기 토큰으로만 해제한다', () async {
      // **전부 해제하면 안 된다.** 로그아웃은 기기별로 갈리는데(refreshToken)
      // 전부 풀면 폰에서 로그아웃한 사용자의 태블릿 잠금화면이 같이 빈다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();

      service.pushToStartListener!('80a1b2');
      await settle();
      await controller.stop();

      expect(repo.pushToStartUnregistered, ['80a1b2']);
    });

    test('날아가던 등록이 로그아웃을 되돌리지 않는다', () async {
      // 등록은 기다리지 않고 보내는데 해제는 로그아웃이 기다린다. 줄을
      // 세우지 않으면 아직 날아가던 PUT 이 DELETE 뒤에 서버에 닿아 **등록이
      // 되살아난다** — 다음 정오에 로그아웃한 기기에 앞사람의 여행이 뜬다
      final service = _FakeService();
      final repo = _FakeRepository()..holdRegister = Completer<void>();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();

      service.pushToStartListener!('80a1b2');
      await settle();
      // 등록이 아직 서버에 닿지 않았다
      expect(repo.pushToStartCalls, isEmpty);

      final stopping = controller.stop();
      await settle();
      repo.holdRegister!.complete(); // 이제야 등록이 도착한다
      await stopping;

      // 해제가 **뒤에** 갔다 — 최종 상태는 '이 기기는 풀렸다'
      expect(repo.pushToStartCalls, ['register', 'unregister']);
    });

    test('멈춘 뒤 늦게 온 토큰은 올리지 않는다', () async {
      // 로그아웃 뒤 도착한 기기 토큰을 올리면 앞사람의 계정으로 등록된다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();
      await controller.stop();

      service.pushToStartListener!('late');
      await settle();

      expect(repo.pushToStartRegistered, isEmpty);
    });

    test('토큰을 받은 적이 없으면 해제하지 않는다', () async {
      // iOS 17.2 미만은 토큰이 영영 안 온다 — 등록된 적이 없으니 지울 것도
      // 없다. null 을 보내면 '이 사용자 전부' 가 되어 다른 기기까지 푼다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      final controller = c.read(tripActivityControllerProvider)..start();

      await controller.stop();

      expect(repo.pushToStartUnregistered, isEmpty);
    });
  });

  group('서버 갱신 등록 (core #577)', () {
    // 서버가 자정마다 카드를 갱신하려면 그 카드의 푸시 토큰을 알아야 한다.
    // 네이티브가 토큰을 올리면 등록하고, 카드를 내리면 등록도 지운다

    test('토큰이 오면 서버에 등록한다', () async {
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith(
        [card(id: '122', start: '2026-09-22')],
        service,
        repository: repo,
      );
      final controller = c.read(tripActivityControllerProvider);
      await controller.sync(now: now);

      service.listener!('122', '80a1b2');
      await settle();

      expect(repo.registered, [(courseId: '122', token: '80a1b2')]);
    });

    test('토큰이 다시 와도 같은 등록을 다시 보낸다', () async {
      // iOS 가 토큰을 갈아 끼우면 또 준다 — 서버가 멱등이라 그대로 보낸다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith(
        [card(id: '122', start: '2026-09-22')],
        service,
        repository: repo,
      );
      await c.read(tripActivityControllerProvider).sync(now: now);

      service.listener!('122', 'old');
      service.listener!('122', 'new');
      await settle();

      expect(repo.registered.map((r) => r.token), ['old', 'new']);
    });

    test('같은 토큰이 다시 오면 한 번만 올린다 — 앱에 돌아올 때마다 다시 준다', () async {
      // 앱을 앞으로 낼 때마다 네이티브가 같은 카드의 감시를 다시 걸고, iOS 는
      // 현재 토큰을 곧바로 다시 준다(#395)
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith(
        [card(id: '122', start: '2026-09-22')],
        service,
        repository: repo,
      );
      await c.read(tripActivityControllerProvider).sync(now: now);

      service.listener!('122', 'same');
      service.listener!('122', 'same');
      service.listener!('122', 'same');
      await settle();

      expect(repo.registered.map((r) => r.token), ['same']);
    });

    test('올리기가 실패하면 같은 토큰도 다음에 다시 올린다', () async {
      final service = _FakeService();
      final failing = _FakeRepository(failRegister: true);
      final c = containerWith(
        [card(id: '122', start: '2026-09-22')],
        service,
        repository: failing,
      );
      await c.read(tripActivityControllerProvider).sync(now: now);

      service.listener!('122', 'tok');
      await settle();
      service.listener!('122', 'tok');
      await settle();

      // 실패는 기록되지 않지만 두 번 모두 시도했다 — 기억이 남아 막히지 않는다
      expect(failing.registerAttempts, 2);
    });

    test('세션이 끝나면 등록을 지우고 내린다', () async {
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith(
        [card(id: '122', start: '2026-09-22')],
        service,
        repository: repo,
      );
      final controller = c.read(tripActivityControllerProvider);
      await controller.sync(now: now);

      await controller.stop();

      expect(repo.unregistered, ['122']);
      expect(service.endCount, 1);
    });

    test('멈춘 뒤 늦게 온 토큰은 올리지 않는다', () async {
      // 로그아웃 뒤 도착한 토큰을 올리면 남의 계정으로 등록된다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith(
        [card(id: '122', start: '2026-09-22')],
        service,
        repository: repo,
      );
      final controller = c.read(tripActivityControllerProvider);
      await controller.stop();

      service.listener!('122', 'late');
      await settle();

      expect(repo.registered, isEmpty);
    });

    test('띄울 것이 없어지면 등록도 지운다', () async {
      final service = _FakeService();
      final repo = _FakeRepository();
      final cards = [card(id: '122', start: '2026-09-22')];
      final c = containerWith(cards, service, repository: repo);
      final controller = c.read(tripActivityControllerProvider);
      await controller.sync(now: now);

      cards.clear();
      c.invalidate(savedCoursesProvider('UPCOMING'));
      await controller.sync(now: now);

      expect(repo.unregistered, ['122']);
      expect(service.endCount, 1);
    });

    test('다른 코스로 바뀌면 앞 코스의 등록을 지운다', () async {
      // 안 지우면 서버가 내린 카드에 매일 갱신을 보내다 410 을 받고서야 치운다
      final service = _FakeService();
      final repo = _FakeRepository();
      final cards = [card(id: '122', start: '2026-09-22')];
      final c = containerWith(cards, service, repository: repo);
      final controller = c.read(tripActivityControllerProvider);
      await controller.sync(now: now);

      cards
        ..clear()
        ..add(card(id: '130', start: '2026-09-21'));
      c.invalidate(savedCoursesProvider('UPCOMING'));
      await controller.sync(now: now);

      expect(repo.unregistered, ['122']);
      expect(service.started?.courseId, '130');
    });

    test('코스를 갈아탄 뒤 늦게 온 앞 코스의 토큰은 올리지 않는다', () async {
      // 네이티브 watcher 는 취소 검사와 Dart 호출 사이에 틈이 있어, 내린
      // 코스의 토큰이 새 코스를 띄운 뒤에 닿을 수 있다. 그대로 올리면 방금
      // 지운 등록이 죽은 토큰으로 되살아난다
      final service = _FakeService();
      final repo = _FakeRepository();
      final cards = [card(id: '122', start: '2026-09-22')];
      final c = containerWith(cards, service, repository: repo);
      final controller = c.read(tripActivityControllerProvider);
      await controller.sync(now: now);

      cards
        ..clear()
        ..add(card(id: '130', start: '2026-09-21'));
      c.invalidate(savedCoursesProvider('UPCOMING'));
      await controller.sync(now: now);

      service.listener!('122', 'stale'); // 내린 코스 — 늦게 닿았다
      service.listener!('130', 'fresh'); // 지금 떠 있는 코스
      await settle();

      expect(repo.registered.map((r) => r.courseId), ['130']);
      expect(repo.unregistered, ['122']);
    });

    test('아직 띄우지 않은 코스의 토큰은 올리지 않는다', () async {
      // 어떤 코스도 안 띄웠는데 토큰이 오면 남의 것이거나 낡은 것이다
      final service = _FakeService();
      final repo = _FakeRepository();
      final c = containerWith([], service, repository: repo);
      c.read(tripActivityControllerProvider);

      service.listener!('122', 'orphan');
      await settle();

      expect(repo.registered, isEmpty);
    });

    test('등록이 실패해도 카드는 떠 있다', () async {
      // 등록은 덤이다 — 실패하면 자정 갱신이 안 오는 것뿐이고, 앱을 다시
      // 열면 다시 띄우며 다시 올린다
      final service = _FakeService();
      final repo = _FakeRepository(failRegister: true);
      final c = containerWith(
        [card(id: '122', start: '2026-09-22')],
        service,
        repository: repo,
      );
      final controller = c.read(tripActivityControllerProvider);
      await controller.sync(now: now);

      service.listener!('122', 'tok');
      await settle();

      expect(service.started?.courseId, '122');
      expect(service.endCount, 0);
    });
  });

  test('기능을 못 쓰는 기기에서는 잠금화면을 건드리지 않는다', () async {
    // iOS 16.1 미만·사용자가 껐을 때
    final service = _FakeService(available: false);
    final c = containerWith([card(id: '1', start: '2026-09-22')], service);

    await c.read(tripActivityControllerProvider).sync(now: now);

    expect(service.started, isNull);
    expect(service.endCount, 0, reason: '내릴 것도 없다');
  });

  group('위젯', () {
    test('예정 코스 목록을 위젯 저장소에 쓴다 — 고른 하나가 아니라 전부', () async {
      // 하나만 쓰면 그 여행이 끝난 다음 날 앱을 안 열었을 때 다음 여행으로
      // 못 넘어간다. 어느 날 무엇을 보여줄지는 위젯이 정한다
      final service = _FakeService();
      final c = containerWith([
        card(id: '1', start: '2026-09-25', region: '홍천군'),
        card(id: '2', start: '2026-10-20', region: '가평군'),
      ], service);

      await c.read(tripActivityControllerProvider).sync(now: now);

      expect(service.widgetTrips?.map((t) => t.courseId), ['1', '2']);
      // 잠금화면은 여전히 창(D-5) 안의 하나만
      expect(service.started?.courseId, '1');
    });

    test('지난 여행도 그대로 넘긴다 — 거르는 규칙은 위젯이 날짜별로 갖는다', () async {
      final service = _FakeService();
      final c = containerWith([
        card(id: '1', start: '2026-09-10', end: '2026-09-12'),
        card(id: '2', start: '2026-09-25'),
      ], service);

      await c.read(tripActivityControllerProvider).sync(now: now);

      expect(service.widgetTrips?.map((t) => t.courseId), ['1', '2']);
    });

    test('위젯도 카드도 못 그리는 기기면 코스를 읽지 않는다', () async {
      // iOS 16.1 미만 — 읽어도 쓸 데가 없다
      final service = _FakeService(available: false, widgetAvailable: false);
      var reads = 0;
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          tripActivityServiceProvider.overrideWithValue(service),
          liveActivityRepositoryProvider.overrideWithValue(_FakeRepository()),
          savedCoursesProvider('UPCOMING').overrideWith((ref) async {
            reads++;
            return [card(id: '1', start: '2026-09-22')];
          }),
        ],
      );
      addTearDown(c.dispose);

      await c.read(tripActivityControllerProvider).sync(now: now);

      expect(reads, 0);
      expect(service.widgetTrips, isNull);
      expect(service.started, isNull);
    });

    test('라이브 액티비티가 안 되는 기기에서도 위젯은 쓴다', () async {
      // 설정에서 라이브 액티비티를 껐어도 위젯은 따로다
      final service = _FakeService(available: false);
      final c = containerWith([card(id: '1', start: '2026-09-22')], service);

      await c.read(tripActivityControllerProvider).sync(now: now);

      expect(service.widgetTrips?.map((t) => t.courseId), ['1']);
      expect(service.started, isNull);
    });

    test('코스를 못 읽으면 위젯은 그대로 둔다', () async {
      // 위젯은 날짜를 스스로 세므로 알던 여행에 대해선 여전히 맞는 말을 한다.
      // 비우면 잠깐의 통신 실패가 "예정된 여행이 없어요" 로 보인다
      final service = _FakeService();
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          tripActivityServiceProvider.overrideWithValue(service),
          savedCoursesProvider('UPCOMING').overrideWith(
            (ref) => Future<List<Map<String, dynamic>>>.error(Exception('500')),
          ),
        ],
      );
      addTearDown(c.dispose);

      try {
        await c.read(tripActivityControllerProvider).sync(now: now);
      } on Object catch (_) {}

      expect(service.widgetTrips, isNull);
      expect(service.clearWidgetCount, 0);
    });

    test('세션이 끝나면 위젯도 비운다', () async {
      // 앞사람의 여행이 위젯에 남지 않게 — 카드와 같은 이유
      final service = _FakeService();
      final c = containerWith([card(id: '1', start: '2026-09-22')], service);
      final controller = c.read(tripActivityControllerProvider);
      await controller.sync(now: now);

      final ok = await controller.stop();

      expect(ok, isTrue);
      expect(service.endCount, 1);
      expect(service.clearWidgetCount, 1);
    });

    test('세션이 시작되면 목록보다 먼저 로그인 표시를 세운다', () async {
      // 첫 조회가 실패해도 위젯이 "로그인하세요" 로 보이지 않게
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = _FakeService();
      final c = containerWith([], service);
      final controller = c.read(tripActivityControllerProvider);
      addTearDown(controller.dispose);

      controller.start();

      expect(service.signedInCount, 1);
    });

    test('위젯에 그날 날씨와 들를 곳을 함께 싣는다', () async {
      // 시안(1669:42131·42467)이 날씨 아이콘과 장소 네 줄을 요구한다.
      // 카드 목록에는 없는 값이라 코스 상세를 따로 읽어 채운다
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = _FakeService();
      final soon = DateTime.now().add(const Duration(days: 2));
      final c = containerWith(
        [card(id: '1', start: TripCountdown.isoDate(soon))],
        service,
        courses: _FakeCourseRepository(
          days: [
            {
              'day': 1,
              'weather': {'sky': '맑음'},
              'places': [
                {'name': '삼탄아트마인'},
                {'name': '정선5일장'},
              ],
            },
          ],
        ),
      );
      final controller = c.read(tripActivityControllerProvider);
      addTearDown(controller.dispose);

      controller.start();
      await settle();
      await settle();

      expect(service.widgetDays['1'], [
        {
          'day': 1,
          'sky': '맑음',
          'places': ['삼탄아트마인', '정선5일장'],
        },
      ]);
    });

    test('앱 안에서 코스 목록이 바뀌면 위젯도 따라간다', () async {
      // 코스를 담고·지우고·날짜를 바꾸면 화면이 목록을 다시 읽는다(invalidate).
      // 그때 위젯도 맞춰야 앱을 다시 앞으로 낼 때까지 지운 여행을 세지 않는다
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = _FakeService();
      final soon = DateTime.now().add(const Duration(days: 2));
      final cards = [card(id: '1', start: TripCountdown.isoDate(soon))];
      final c = containerWith(cards, service);
      final controller = c.read(tripActivityControllerProvider);
      addTearDown(controller.dispose);

      controller.start();
      await settle();
      await settle();
      expect(service.widgetTrips?.map((t) => t.courseId), ['1']);

      cards.add(
        card(id: '2', start: TripCountdown.isoDate(soon), region: '가평군'),
      );
      c.invalidate(savedCoursesProvider('UPCOMING'));
      await settle();
      await settle();

      expect(service.widgetTrips?.map((t) => t.courseId), ['1', '2']);
    });
  });
}

/// **`noSuchMethod` 를 두지 않는다.** 두면 레포에 메서드가 늘어도 조용히
/// 삼켜, 실기기에서만 터지는 구멍이 생긴다
class _FakeRepository implements LiveActivityRepository {
  _FakeRepository({this.failRegister = false});

  final bool failRegister;
  final registered = <({String courseId, String token})>[];
  final unregistered = <String>[];

  /// 등록을 시도한 횟수 — 실패해도 센다
  int registerAttempts = 0;

  @override
  Future<void> register({
    required String courseId,
    required String token,
  }) async {
    registerAttempts++;
    if (failRegister) throw Exception('등록 실패');
    registered.add((courseId: courseId, token: token));
  }

  @override
  Future<void> unregister(String courseId) async => unregistered.add(courseId);

  /// 이 기기의 push-to-start 등록 (core #585)
  final pushToStartRegistered = <String>[];

  /// 등록·해제가 **서버에 닿은 순서**. 뒤집히면 로그아웃이 되돌려진다
  final pushToStartCalls = <String>[];

  /// 등록을 일부러 늦춘다 — 느린 네트워크를 흉내 내 경쟁을 만든다
  Completer<void>? holdRegister;

  /// 해제에 실린 토큰. **비어 있음(null)과 기록 없음은 다르다** — null 은
  /// '이 사용자 전부' 라는 뜻이라 기기별 해제와 구별해야 한다
  final pushToStartUnregistered = <String?>[];

  @override
  Future<void> registerPushToStart(String token) async {
    // 붙잡아 두면 '아직 날아가는 중' 이 된다
    if (holdRegister != null) await holdRegister!.future;
    pushToStartRegistered.add(token);
    pushToStartCalls.add('register');
  }

  @override
  Future<void> unregisterPushToStart({String? token}) async {
    pushToStartUnregistered.add(token);
    pushToStartCalls.add('unregister');
  }
}

/// 위젯에 실을 **날씨·장소**를 주는 대역 — 서버를 부르지 않는다.
///
/// 컨트롤러가 코스 상세를 읽어 일자별 값을 뽑는데, 테스트에서 진짜 Dio 가
/// 나가면 통신 오류로 위젯 갱신 자체가 늦어진다
class _FakeCourseRepository extends CourseRepository {
  _FakeCourseRepository({this.days = const []}) : super(Dio());

  /// `_toCourseMap` 이 주는 모양 — `day`·`weather`·`places`
  final List<Map<String, dynamic>> days;

  @override
  Future<({Map<String, dynamic> saved, Map<String, dynamic> course})?>
  savedCourseDetail(String courseId) async =>
      (saved: <String, dynamic>{}, course: <String, dynamic>{'days': days});
}
