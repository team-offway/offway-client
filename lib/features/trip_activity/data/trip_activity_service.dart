import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/trip_countdown.dart';
import '../../../core/utils/log.dart';

/// 네이티브가 카드의 푸시 토큰을 받았다 — 카드 하나마다 토큰이 따로다
typedef PushTokenListener = void Function(String courseId, String token);

/// 네이티브가 **기기**의 push-to-start 토큰을 받았다 — 코스가 없다.
/// 서버가 이걸로 카드를 처음 띄운다(core #585)
typedef PushToStartTokenListener = void Function(String token);

/// 잠금화면·다이나믹 아일랜드(Live Activity)를 여닫는 다리.
///
/// **UI는 Swift가 그린다.** Flutter 위젯으로는 잠금화면을 그릴 수 없어,
/// 재료만 네이티브로 넘기고 화면은 Widget Extension(SwiftUI)이 맡는다.
///
/// iOS 16.1+ 에서만 동작한다. 그 아래면 **조용히 아무 일도
/// 하지 않는다** — 쓰는 쪽이 플랫폼을 검사하지 않게 여기서 삼킨다.
class TripActivityService {
  TripActivityService({
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting bool? isSupportedPlatform,
  }) : _channel = channel ?? const MethodChannel(channelName),
       // 테스트는 macOS VM 에서 돈다 — Platform.isIOS 를 그대로 보면
       // 모든 호출이 조용히 빠져나가 채널 계약을 잴 수 없다
       _isSupportedPlatform = isSupportedPlatform ?? Platform.isIOS;

  /// 네이티브와 약속한 이름 — AppDelegate 가 같은 문자열을 쓴다
  static const channelName = 'com.nth.offway/trip_activity';

  final MethodChannel _channel;

  /// iOS 에서만 Live Activity 가 있다. 아니면 조용히 아무 일도 하지 않는다
  final bool _isSupportedPlatform;

  /// 이 기기에서 Live Activity 를 띄울 수 있는가.
  ///
  /// iOS 16.1 미만·사용자가 설정에서 껐을 때 모두 거짓이다.
  /// 판정은 네이티브가 한다 — `ActivityAuthorizationInfo` 를 Dart 에서
  /// 볼 수 없다
  Future<bool> isAvailable() async {
    if (!_isSupportedPlatform) return false;
    try {
      return await _channel
              .invokeMethod<bool>('isAvailable')
              .timeout(_timeout) ??
          false;
    } on PlatformException catch (e) {
      logDebug('Live Activity 가능 여부를 묻지 못했다: ${e.message}');
      return false;
    } on MissingPluginException {
      // 네이티브가 아직 안 붙은 빌드 — 기능이 없는 것이지 오류가 아니다
      return false;
    } on TimeoutException {
      logDebug('Live Activity 가능 여부가 제때 오지 않았다');
      return false;
    }
  }

  /// 이 여행으로 잠금화면을 띄운다. 이미 떠 있으면 값만 갈아 끼운다.
  ///
  /// **문구가 아니라 재료를 넘긴다**(core #577 B안). 조립은 네이티브
  /// `ContentState` 가 한다 — 서버가 자정에 보내는 것과 같은 다섯 칸이라
  /// 앱이 띄운 카드와 서버가 갱신한 카드가 다른 말을 하지 않고, 카피를
  /// 바꿀 때 서버를 고칠 일이 없다.
  ///
  /// 성공 여부를 돌려준다 — 타임아웃이 나면 **띄운 건지 아닌지 알 수 없다**.
  /// 그때는 거짓이다(다음 기회에 다시 맞춘다)
  Future<bool> start(TripCountdown trip, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    return _invokeOk('start', {
      ..._tripArgs(trip),
      // 둘 중 하나만 값이 있다. null 도 그대로 보낸다 — 비어 있다는 것
      // 자체가 뜻이라(출발 전이냐 여행 중이냐), 빼면 네이티브가 직전
      // 값을 그대로 쓴다
      'daysLeft': trip.daysLeft(at),
      'dayNth': trip.dayNth(at),
    });
  }

  /// 네이티브가 여행 하나를 읽는 네 칸 — 라이브 액티비티와 위젯 목록이 같은
  /// 이름을 쓴다. 한 곳에서만 적어야 이름이 어긋나지 않는다
  static Map<String, Object?> _tripArgs(TripCountdown trip) => {
    'courseId': trip.courseId,
    'regionName': trip.regionName,
    'startDate': TripCountdown.isoDate(trip.startDate),
    'endDate': TripCountdown.isoDate(trip.endDate),
  };

  /// 떠 있는 잠금화면을 내린다 — 여행이 끝났거나 코스를 지웠을 때.
  ///
  /// **성공 여부를 돌려준다.** 로그아웃·탈퇴·세션 만료가 이걸 부르는데,
  /// 실패를 삼키면 앞사람의 여행지·날짜가 잠금화면에 남은 채로 로그인
  /// 화면으로 넘어간다 — 부르는 쪽이 알아야 다시 시도하든 알리든 한다
  Future<bool> end() => _invokeOk('end', const {});

  /// 홈·잠금화면 **위젯**이 읽을 예정 여행 목록을 네이티브 저장소(App Group)에
  /// 쓴다 — 쓰고 나면 네이티브가 위젯 시간표를 다시 만들게 한다.
  ///
  /// **고른 하나가 아니라 목록**을 넘긴다. 어느 날 무엇을 보여줄지는 위젯이
  /// 날짜별 시간표를 만들 때 정한다 — 하나만 넘기면 그 여행이 끝난 다음 날
  /// 앱을 안 열었을 때 다음 여행으로 못 넘어간다. 칸은 라이브 액티비티와
  /// 같다(`courseId`·`regionName`·`startDate`·`endDate`)
  /// [daysByCourse]는 코스 id → 일자별 날씨·장소([widgetDay]). **위젯에 뜰
  /// 여행 하나만** 담는다 — 나머지는 날짜·지역명만으로도 충분하고, 코스마다
  /// 상세를 읽으면 그만큼 요청이 늘어난다
  Future<bool> setWidgetTrips(
    List<TripCountdown> trips, {
    Map<String, List<Map<String, Object?>>> daysByCourse = const {},
  }) => _invokeOk('setWidgetTrips', {
    'trips': [
      for (final t in trips)
        {..._tripArgs(t), 'days': daysByCourse[t.courseId] ?? const []},
    ],
  });

  /// 위젯 하나에 실을 **일자별 날씨·장소** — 코스 상세에서 뽑아 온다.
  ///
  /// 카드 목록(`savedCourses`)에는 없는 값이라 상세를 따로 읽어야 한다.
  /// 위젯에 뜰 여행 하나만 읽으므로 호출은 한 번이다.
  ///
  /// [day]는 1부터다. 위젯이 날짜를 보고 어느 칸을 쓸지 정한다 —
  /// 출발 전과 1일차는 1번, 2일차는 2번이다
  static Map<String, Object?> widgetDay({
    required int day,
    String? sky,
    required List<String> places,
  }) => {'day': day, 'sky': ?sky, 'places': places};

  /// 위젯을 그릴 수 있는 기기인가 — iOS 16.1 이상. 라이브 액티비티와 달리
  /// 사용자가 끌 수 있는 것이 아니라 버전만 본다
  Future<bool> isWidgetAvailable() async {
    if (!_isSupportedPlatform) return false;
    try {
      return await _channel
              .invokeMethod<bool>('isWidgetAvailable')
              .timeout(_timeout) ??
          false;
    } on PlatformException catch (e) {
      logDebug('위젯 가능 여부를 묻지 못했다: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// 세션이 시작됐다 — 목록을 아직 못 받았어도 위젯이 "로그인하세요" 로
  /// 보이지 않게. 로그인 여부와 여행 목록은 다른 사실이라 따로 알린다
  Future<bool> markWidgetSignedIn() =>
      _invokeOk('markWidgetSignedIn', const {});

  /// 위젯을 로그인 전 상태로 되돌린다 — 로그아웃·탈퇴.
  /// 안 비우면 앞사람의 여행이 위젯에 남는다
  Future<bool> clearWidget() => _invokeOk('clearWidget', const {});

  /// 네이티브가 푸시 토큰을 올려 보내면 받는다 — **두 종류**다.
  ///
  /// 서버 등록은 JWT 를 쥔 Dart 가 한다(`LiveActivityRepository`).
  ///
  /// - [listener] : 떠 있는 **카드** 하나의 갱신 토큰. 카드를 띄운 직후 첫
  ///   토큰이 오고, 도중에 갈아 끼우면 또 온다 — 그때마다 같은 등록을 다시
  ///   보내면 된다(서버가 (사용자, 코스)로 한 행만 둔다)
  /// - [onPushToStartToken] : **기기**의 push-to-start 토큰. 카드가 없어도
  ///   오고, 서버가 이걸로 카드를 처음 띄운다(core #585). iOS 17.2+ 에서만
  ///   온다 — 그 아래 기기에서는 영영 안 온다
  ///
  /// **핸들러는 한 번만 걸린다.** 채널이 하나라 따로 걸면 앞의 것을 덮어써,
  /// 카드 토큰이 조용히 끊긴다 — 그래서 둘을 여기서 함께 받는다
  void listenPushToken(
    PushTokenListener listener, {
    PushToStartTokenListener? onPushToStartToken,
  }) {
    if (!_isSupportedPlatform) return;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>();
      final token = args?['token'] as String?;
      switch (call.method) {
        case 'onPushToken':
          final courseId = args?['courseId'] as String?;
          if (courseId == null || token == null || token.isEmpty) return;
          listener(courseId, token);
        case 'onPushToStartToken':
          if (token == null || token.isEmpty) return;
          onPushToStartToken?.call(token);
        default:
          throw MissingPluginException('${call.method} 은 받지 않는다');
      }
    });
    // **수신자를 건 뒤에 알린다.** 네이티브는 `didFinishLaunching` 에서 뜨고
    // 여기는 위젯 트리가 선 뒤라, 그 사이에 나온 기기 토큰은 Flutter 가
    // 버퍼링하지 않아 사라진다 — 네이티브가 담아 뒀다가 이 신호에 넘긴다.
    // 기다리지 않는다: 담아 둔 것이 없으면 아무 일도 없다
    _invokeOk('pushToStartReady', const {});
  }

  /// 네이티브가 답하지 않을 때 기다리는 한도.
  ///
  /// ActivityKit 이 매달리면 `invokeMethod` 의 Future 가 영영 완결되지
  /// 않는다 — 앱 재개마다 부르는 자리라 그대로 쌓인다
  static const _timeout = Duration(seconds: 5);

  /// 네이티브를 부르고 **해냈는지**를 돌려준다.
  ///
  /// 던지지는 않는다 — 잠금화면 때문에 로그아웃이 막히면 안 된다. 대신
  /// 실패를 거짓으로 알려, 부르는 쪽이 판단하게 둔다
  Future<bool> _invokeOk(String method, Map<String, Object?> args) async {
    // 안 되는 플랫폼은 '실패'가 아니다 — 내릴 것이 애초에 없다
    if (!_isSupportedPlatform) return true;
    try {
      await _channel.invokeMethod<void>(method, args).timeout(_timeout);
      return true;
    } on PlatformException catch (e) {
      logDebug('Live Activity $method 실패: ${e.message}');
      return false;
    } on MissingPluginException {
      // 네이티브가 없는 빌드 — 띄운 적이 없으니 남을 것도 없다
      logDebug('Live Activity 네이티브가 없는 빌드다 ($method)');
      return true;
    } on TimeoutException {
      // **뜬 건지 아닌지 모른다.** 모르면 안 된 것으로 친다
      logDebug('Live Activity $method 가 제때 답하지 않았다');
      return false;
    }
  }
}
