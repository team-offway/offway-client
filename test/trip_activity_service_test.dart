import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offway/features/trip_activity/data/trip_activity_service.dart';
import 'package:offway/features/trip_activity/domain/trip_countdown.dart';

/// 잠금화면을 여닫는 다리 — 네이티브와 주고받는 약속을 고정한다.
///
/// **UI는 Swift가 그린다.** 여기서 보는 것은 "무엇을 어떤 이름으로
/// 넘기는가"뿐이다. 이름이나 키가 어긋나면 실기기에서만 드러나므로
/// 여기서 못 박는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late TripActivityService service;

  /// 네이티브 대신 받아 적는 대역
  void stub({Object? Function(MethodCall call)? answer}) {
    calls = [];
    const channel = MethodChannel(TripActivityService.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer?.call(call);
        });
    // 테스트는 macOS VM 에서 돈다 — iOS 인 척해야 채널까지 간다
    service = TripActivityService(channel: channel, isSupportedPlatform: true);
  }

  final trip = TripCountdown(
    courseId: '7',
    regionName: '정선군',
    startDate: DateTime(2026, 9, 23),
    endDate: DateTime(2026, 9, 25),
  );

  test('띄울 때 화면이 쓸 값을 모두 넘긴다', () async {
    stub();
    await service.start(trip, now: DateTime(2026, 9, 20));

    expect(calls.single.method, 'start');
    final args = (calls.single.arguments as Map).cast<String, Object?>();
    expect(args['courseId'], '7');
    expect(args['regionName'], '정선군');
    // **문구가 아니라 재료다**(core #577 B안). 서버가 자정에 보내는 것과
    // 같은 다섯 칸 — 이름이 하나라도 어긋나면 네이티브가 조용히 못 읽는다
    expect(args['daysLeft'], 3);
    expect(args['startDate'], '2026-09-23');
    expect(args['endDate'], '2026-09-25');
    // 여행 중이 아니면 dayNth 는 null — **키는 있어야 한다.** 빼면 네이티브가
    // 직전 값을 그대로 쓴다
    expect(args.containsKey('dayNth'), isTrue);
    expect(args['dayNth'], isNull);
    // 문구 키는 더 보내지 않는다 — ContentState 계약에 없다
    expect(args.keys, isNot(contains('headline')));
    expect(args.keys, isNot(contains('compactLabel')));
  });

  test('여행 중이면 며칠째인지 넘긴다', () async {
    stub();
    await service.start(trip, now: DateTime(2026, 9, 24));

    final args = (calls.single.arguments as Map).cast<String, Object?>();
    expect(args['dayNth'], 2);
    expect(args['daysLeft'], isNull);
  });

  test('네이티브가 올린 푸시 토큰을 받는다', () async {
    // 카드를 띄우면 iOS 가 토큰을 주고, 네이티브가 Dart 로 되부른다.
    // 서버 등록은 JWT 를 쥔 Dart 몫이다
    stub();
    String? gotCourse;
    String? gotToken;
    service.listenPushToken((courseId, token) {
      gotCourse = courseId;
      gotToken = token;
    });

    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      const MethodCall('onPushToken', {'courseId': '7', 'token': '80a1b2'}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          TripActivityService.channelName,
          message,
          (_) {},
        );

    expect(gotCourse, '7');
    expect(gotToken, '80a1b2');
  });

  test('빈 토큰은 흘려보낸다', () async {
    stub();
    var called = false;
    service.listenPushToken((_, _) => called = true);

    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      const MethodCall('onPushToken', {'courseId': '7', 'token': ''}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          TripActivityService.channelName,
          message,
          (_) {},
        );

    expect(called, isFalse);
  });

  test('내릴 때는 end 를 부른다', () async {
    stub();
    await service.end();

    expect(calls.single.method, 'end');
  });

  test('가능 여부는 네이티브가 답한다', () async {
    stub(answer: (_) => true);
    expect(await service.isAvailable(), isTrue);
    expect(calls.single.method, 'isAvailable');
  });

  test('안 되는 플랫폼에서는 채널을 아예 때리지 않는다', () async {
    // iOS 16.1 미만에서는 네이티브가 없다. 불러 보고 실패를
    // 삼키는 게 아니라 **가기 전에 멈춘다**
    calls = [];
    const channel = MethodChannel(TripActivityService.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final android = TripActivityService(
      channel: channel,
      isSupportedPlatform: false,
    );

    expect(await android.isAvailable(), isFalse);
    await android.start(trip, now: DateTime(2026, 9, 20));
    await android.end();

    expect(calls, isEmpty);
  });

  test('네이티브가 없는 빌드에서도 깨지지 않는다', () async {
    // 채널을 아예 걸지 않는다 — MissingPluginException 이 난다
    const channel = MethodChannel(TripActivityService.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final s = TripActivityService(channel: channel, isSupportedPlatform: true);

    // 잠금화면이 안 뜨는 것뿐이다 — 앱이 하던 일을 막지 않는다
    expect(await s.isAvailable(), isFalse);
    await s.start(trip);
    await s.end();
  });

  test('네이티브가 실패해도 삼킨다', () async {
    stub(
      answer: (_) => throw PlatformException(code: 'ERR', message: '못 띄웠다'),
    );

    expect(await service.isAvailable(), isFalse);
    // 던지지 않는다
    await service.start(trip);
    await service.end();
  });

  group('위젯', () {
    test('위젯에는 목록을 넘긴다 — 칸은 라이브 액티비티와 같다', () async {
      stub();
      final later = TripCountdown(
        courseId: '8',
        regionName: '가평군',
        startDate: DateTime(2026, 10, 20),
        endDate: DateTime(2026, 10, 20),
      );

      await service.setWidgetTrips([trip, later]);

      expect(calls.single.method, 'setWidgetTrips');
      final args = (calls.single.arguments as Map).cast<String, Object?>();
      final trips = (args['trips'] as List).cast<Map>();
      expect(trips, hasLength(2));
      expect(trips.first['courseId'], '7');
      expect(trips.first['regionName'], '정선군');
      expect(trips.first['startDate'], '2026-09-23');
      expect(trips.first['endDate'], '2026-09-25');
      // 날짜별 판단은 위젯이 한다 — 여기서 D-day 를 미리 세지 않는다
      expect(trips.first.keys, isNot(contains('daysLeft')));
      expect(trips.first.keys, isNot(contains('dayNth')));
    });

    test('비울 때는 인자 없이 부른다', () async {
      stub();
      expect(await service.clearWidget(), isTrue);
      expect(calls.single.method, 'clearWidget');
    });
  });
}
