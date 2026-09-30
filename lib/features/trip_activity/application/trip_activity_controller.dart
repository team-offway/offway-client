import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../course/data/course_repository.dart';
import '../data/live_activity_repository.dart';
import '../data/trip_activity_service.dart';
import '../domain/trip_countdown.dart';
import '../../../core/storage/registration_memo.dart';
import '../../../core/utils/log.dart';
import '../../course/application/course_providers.dart';

final tripActivityServiceProvider = Provider<TripActivityService>(
  (ref) => TripActivityService(),
);

/// 잠금화면에 띄울 여행을 고르고, 앱이 앞으로 나올 때마다 값을 맞춘다.
///
/// **하루에 한 번꼴로 바뀌는 값이다**(D-3 → D-2). 자주 부를 이유가 없어
/// 앱이 켜지거나 포그라운드로 돌아올 때만 맞춘다 — 타이머를 두지 않는다.
///
/// 앱이 꺼져 있는 동안은 **서버가 자정마다 갱신한다**(core #577). 그러려면
/// 카드의 푸시 토큰을 서버가 알아야 하는데, 네이티브가 토큰을 올려 보내면
/// 여기서 등록한다. 카드를 내릴 때는 등록도 지운다.
class TripActivityController with WidgetsBindingObserver {
  TripActivityController(this._ref) {
    // 토큰 수신자는 **한 번만** 건다. 카드가 떠야 토큰이 오므로 start()
    // 전에는 어차피 안 오고, 세션이 끝난 뒤 늦게 온 것은 _stopped 가 거른다.
    //
    // push-to-start 토큰은 다르다 — 카드가 없어도 앱이 켜지면 바로 온다.
    // 로그인 전에 올 수 있어 여기서는 **보관만** 하고 등록은 세션이 열린
    // 뒤에 한다(`_registerPushToStart`)
    _ref
        .read(tripActivityServiceProvider)
        .listenPushToken(_onPushToken, onPushToStartToken: _onPushToStartToken);
  }

  final Ref _ref;
  bool _started = false;

  /// 진행 중인 맞추기. **겹쳐 돌면 안 된다** — 앱 재개가 연달아 오면
  /// (알림 센터를 내렸다 올리거나 앱 스위처를 스치면 실제로 그렇다)
  /// 늦게 시작한 쪽이 먼저 끝나 end() 와 start() 의 순서가 뒤집힌다
  Future<void>? _syncing;

  /// 멈춘 뒤인가. 진행 중이던 sync() 가 깨어났을 때 물러나게 한다 —
  /// 세션이 끝났는데 앞사람의 코스를 다시 띄우면 안 된다
  bool _stopped = false;

  /// 지금 잠금화면에 떠 있는(또는 띄우는 중인) 코스.
  ///
  /// 둘에 쓴다 — 내릴 때 서버 등록을 같이 지우고, **올라온 토큰이 이 코스의
  /// 것인지 가른다.** 네이티브 watcher 는 취소 검사와 Dart 호출 사이에 틈이
  /// 있어, 코스를 갈아타는 도중 내린 코스의 토큰이 늦게 닿을 수 있다
  String? _liveCourseId;

  /// 이 **기기**의 push-to-start 토큰 — 서버가 카드를 처음 띄우는 열쇠다.
  ///
  /// 카드와 무관하게 앱이 켜지면 온다. 로그인 전에 올 수 있어 보관해 뒀다가
  /// 세션이 열리면 등록하고, 로그아웃할 때 **이 값으로 이 기기만** 해제한다
  /// (전부 해제하면 다른 기기의 잠금화면이 같이 빈다).
  ///
  /// 세션이 끝나도 지우지 않는다 — 기기 토큰이라 다음 사람이 로그인해도
  /// 같은 값이고, iOS 가 다시 주지 않을 수 있다
  String? _pushToStartToken;

  /// 기기 등록·해제를 **한 줄로 세운다**.
  ///
  /// 등록은 기다리지 않고 보내는데 해제는 로그아웃이 기다린다 — 그대로 두면
  /// 아직 날아가는 중인 PUT 이 DELETE 뒤에 서버에 닿아 **로그아웃한 사람의
  /// 등록이 되살아난다.** 그러면 다음 정오에 그 기기 잠금화면에 앞사람의
  /// 여행이 뜬다.
  ///
  /// 줄을 세우면 DELETE 가 앞의 PUT 이 끝난 뒤에 나간다
  Future<void>? _pushToStartOp;

  /// 예정 코스 목록 구독 — 앱 안에서 코스를 담거나 지우거나 날짜를 바꾸면
  /// 화면이 목록을 다시 읽는데(invalidate), 그때 위젯·잠금화면도 따라간다.
  /// 이게 없으면 앱을 다시 앞으로 낼 때까지 위젯이 지운 여행을 센다
  ProviderSubscription<AsyncValue<List<Map<String, dynamic>>>>? _courses;

  void start() {
    if (_started) return;
    _started = true;
    _stopped = false;
    WidgetsBinding.instance.addObserver(this);
    // 로그인 여부는 목록보다 먼저 — 첫 조회가 실패해도 위젯이 "로그인하세요"
    // 로 보이지 않게. 기다리지 않는다
    _ref.read(tripActivityServiceProvider).markWidgetSignedIn();
    // 로그인 전에 받아 둔 기기 토큰이 있으면 지금 올린다 — 앱을 켜자마자
    // 오는 값이라 대개 세션보다 먼저다. 이걸 빠뜨리면 이 기기는 앱을 다시
    // 켤 때까지 서버가 카드를 못 띄운다(core #585)
    _registerPushToStart();
    // 목록이 새로 읽힐 때마다 맞춘다. 로딩 중은 건너뛴다 — 값이 오면 온다.
    // sync() 는 읽기만 하고 invalidate 하지 않으므로 돌지 않는다.
    //
    // **처음 맞추기도 이 구독이 한다**(fireImmediately). 예전에는 바로 한 번
    // 부르고 목록이 로딩 → 데이터로 바뀔 때 또 불러, 앱을 켤 때마다 위젯용
    // 코스 상세 조회와 잠금화면 띄우기가 두 번씩 나갔다(#395). 이미 받아 둔
    // 목록이면 지금 한 번, 받는 중이면 값이 올 때 한 번이다
    _courses = _ref.listen(savedCoursesProvider('UPCOMING'), (_, next) {
      if (!next.isLoading) syncInBackground();
    }, fireImmediately: true);
  }

  /// 세션이 끝났다 — 옵저버를 떼고 **잠금화면도 내린다**.
  ///
  /// 로그아웃·탈퇴·세션 만료가 부른다. 내리기만 하고 옵저버를 남겨 두면
  /// 앱을 다시 앞으로 낼 때 앞사람의 코스로 다시 띄운다.
  ///
  /// **진행 중인 맞추기 뒤에 세운다.** 코스 조회에 머물러 있던 sync() 가
  /// 나중에 깨어나 start() 를 부르면, 방금 내린 앞사람의 여행이 다시
  /// 올라간다. 멈춘 뒤에는 sync() 가 스스로 물러나지만(_stopped),
  /// 이미 조회를 마친 것이 있을 수 있어 큐의 끝에서 내린다.
  ///
  /// 내려갔으면 참. **거짓이면 앞사람의 여행이 잠금화면에 남아 있다.**
  Future<bool> stop() async {
    dispose();
    _stopped = true;

    // 앞의 맞추기가 끝나길 기다린다 — 실패했든 말든 순서만 지키면 된다
    await (_syncing ?? Future<void>.value()).catchError((_) {});
    // 서버 등록을 먼저 지운다 — 아직 이 사람의 토큰이 살아 있을 때라야
    // 요청이 통한다(로그아웃 뒤에는 401 이다).
    //
    // 카드 등록과 기기 등록은 **다른 표**다(core #585). 카드 쪽만 지우면
    // 서버가 내일 정오에 이 기기로 새 카드를 띄운다 — 로그아웃한 사람의
    // 잠금화면에 앞사람의 여행이 뜬다. 둘은 독립된 왕복이라 같이 보낸다
    await (_unregisterLive(), _unregisterPushToStart()).wait;
    final service = _ref.read(tripActivityServiceProvider);
    // 위젯도 앞사람의 것이다 — 카드처럼 비운다. 둘은 독립된 왕복이라 같이 보낸다.
    // 돌려주는 값은 **카드**가 내려갔는가다 — 호출부가 그 뜻으로 안내를 띄운다.
    // 위젯 비우기는 네이티브가 실패할 길이 없어(타임아웃뿐) 기록만 남긴다
    final (ended, cleared) = await (service.end(), service.clearWidget()).wait;
    if (!cleared) logDebug('위젯을 비우지 못했다 — 앞사람의 여행이 남을 수 있다');
    return ended;
  }

  void dispose() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _courses?.close();
    _courses = null;
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 서버에서 바뀐 것(다른 기기)을 받아오게 목록을 다시 읽는다 — 구독이
    // 살아 있어 캐시가 남으므로, 읽기만 해서는 옛 값이다. 다시 읽히면
    // 구독이 맞춘다
    if (state == AppLifecycleState.resumed) {
      _ref.invalidate(savedCoursesProvider('UPCOMING'));
    }
  }

  /// 기다리지 않고 맞춘다 — 실패해도 앱이 하던 일을 막지 않는다.
  /// 잠금화면이 안 뜨는 것뿐이다
  void syncInBackground() {
    // 앞의 맞추기가 끝난 뒤에 잇는다 — 겹쳐 돌면 순서가 뒤집힌다
    _syncing = (_syncing ?? Future<void>.value())
        .then((_) => sync())
        .catchError((Object e) {
          logDebug('잠금화면을 맞추지 못했다: $e');
        });
  }

  /// 예정 코스를 읽어 **위젯 목록을 갈아 끼우고**, 잠금화면에 띄울 하나를 고른다.
  ///
  /// 띄울 것이 없으면(예정이 없거나 다 지났으면) 떠 있던 것을 내린다 —
  /// 끝난 여행이 잠금화면에 남아 있을 이유가 없다
  Future<void> sync({DateTime? now}) async {
    final service = _ref.read(tripActivityServiceProvider);
    if (_stopped) return;
    // 위젯도 카드도 못 그리는 기기(iOS 16.1 미만)면 코스를 읽지
    // 않는다 — 읽어도 쓸 데가 없다
    final (widgetOk, liveOk) = await (
      service.isWidgetAvailable(),
      service.isAvailable(),
    ).wait;
    if (!widgetOk && !liveOk) return;
    if (_stopped) return;

    final List<Map<String, dynamic>> cards;
    try {
      cards = await _ref.read(savedCoursesProvider('UPCOMING').future);
    } on Object catch (e) {
      // **코스를 못 읽었다고 떠 있는 것을 그냥 두지 않는다.** 서버가 계속
      // 실패하면 지난 여행 D-day 가 잠금화면에 무기한 남는다 — 무엇을
      // 띄울지 모르는 상태라면 아무것도 띄우지 않는 편이 맞다.
      //
      // 위젯은 그대로 둔다 — 위젯은 날짜를 스스로 세므로 알던 여행에 대해선
      // 여전히 맞는 말을 한다. 비우면 잠깐의 통신 실패가 "예정된 여행이
      // 없어요" 로 보인다
      logDebug('예정 코스를 읽지 못해 잠금화면을 내린다: $e');
      if (!_stopped) {
        await _unregisterLive();
        await service.end();
      }
      rethrow;
    }

    // **조회를 기다리는 동안 세션이 끝났을 수 있다.** 그 사이에 stop() 이
    // 내려 둔 것을 여기서 다시 띄우면 앞사람의 여행이 되살아난다
    if (_stopped) return;

    final at = now ?? DateTime.now();
    final trips = cards
        .map(TripCountdown.tryFrom)
        .whereType<TripCountdown>()
        .toList();

    // 위젯은 라이브 액티비티가 안 되는 기기(설정에서 껐거나)에서도 그린다.
    // 목록을 그대로 넘긴다 — 지난 여행을 거르는 규칙은 위젯이 날짜별로 갖고
    // 있다. 여기서도 거르면 같은 규칙이 두 곳에 산다
    if (widgetOk) {
      await service.setWidgetTrips(
        trips,
        daysByCourse: await _widgetDays(trips, at),
      );
    }

    if (!liveOk) return;
    if (_stopped) return;

    final picked = TripCountdown.pick(trips, at);

    if (picked == null) {
      await _unregisterLive();
      await service.end();
      return;
    }
    // 다른 코스로 바뀐다 — 앞 코스의 등록은 지운다. 안 지우면 서버가
    // 내린 카드에 매일 갱신을 보내다 410 을 받고서야 치운다
    if (_liveCourseId != null && _liveCourseId != picked.courseId) {
      await _unregisterLive();
    }
    // **띄우기 전에 세운다.** 토큰은 start() 가 답한 뒤에 오지만, 그 전에
    // 세워 둬야 '시작 중인 코스' 의 토큰을 남의 것으로 버리지 않는다.
    // 띄우기가 실패해도 그대로 둔다 — 다음 맞추기가 다시 띄우고, 지울 일이
    // 생기면 등록된 적 없는 코스의 DELETE 는 서버가 성공으로 받는다
    _liveCourseId = picked.courseId;
    await service.start(picked, now: now);
  }

  /// 위젯에 실을 **일자별 날씨·장소**를 코스 상세에서 뽑는다.
  ///
  /// 카드 목록에는 없는 값이라 상세를 따로 읽어야 한다. **위젯에 뜰 여행
  /// 하나만** 읽는다 — 저장 코스가 열 개여도 요청은 한 번이다.
  ///
  /// **창을 두지 않는다**(`within: null`). 위젯은 잠금화면 카드와 달리
  /// D-30 이든 뜨므로(네이티브 `TripWidgetTrip.pick`), 카드의 창(7일)으로
  /// 고르면 먼 여행일 때 위젯에만 날씨·장소가 빠진다
  ///
  /// **실패해도 위젯은 뜬다.** 날씨·장소가 없으면 시안대로 로고와 날짜만
  /// 그린다 — 통신 한 번 실패로 위젯이 비면 그게 더 나쁘다
  Future<Map<String, List<Map<String, Object?>>>> _widgetDays(
    List<TripCountdown> trips,
    DateTime at,
  ) async {
    final picked = TripCountdown.pick(trips, at, within: null);
    if (picked == null) return const {};
    try {
      final detail = await _ref
          .read(courseRepositoryProvider)
          .savedCourseDetail(picked.courseId)
          // **위젯 갱신이 이 응답을 하염없이 기다리지 않는다.** 날씨·장소는
          // 덤이고, 못 받아도 날짜와 지역명은 그려야 한다
          .timeout(const Duration(seconds: 3));
      final days = (detail?.course['days'] as List?) ?? const [];
      return {
        picked.courseId: [
          for (final day in days.cast<Map<String, dynamic>>())
            TripActivityService.widgetDay(
              day: (day['day'] as num).toInt(),
              sky: (day['weather'] as Map<String, dynamic>?)?['sky'] as String?,
              places: [
                // 시안은 네 줄까지다. 적으면 있는 만큼만 그린다
                for (final p
                    in ((day['places'] as List?) ?? const [])
                        .cast<Map<String, dynamic>>()
                        .take(4))
                  if (p['name'] case final String name) name,
              ],
            ),
        ],
      };
    } on Object catch (e) {
      logDebug('위젯에 실을 코스 상세를 읽지 못했다: $e');
      return const {};
    }
  }

  /// 네이티브가 카드의 토큰을 올려 보냈다 — 서버에 등록한다.
  ///
  /// **기다리지 않는다.** 등록이 늦어도 카드는 이미 떠 있다. 실패하면 다음
  /// 자정 갱신이 안 오는 것뿐이고, iOS 가 토큰을 다시 주거나 앱이 다시
  /// 띄울 때 또 온다
  void _onPushToken(String courseId, String token) {
    if (_stopped) return; // 세션이 끝난 뒤 늦게 온 토큰 — 남의 것이 된다
    // **지금 떠 있는 코스의 토큰만 올린다.** 코스를 갈아타는 도중 내린 코스의
    // 토큰이 늦게 닿으면, 방금 지운 등록이 죽은 토큰으로 되살아난다 — 서버가
    // 자정마다 거기 보내다 410 을 받고서야 치운다
    if (courseId != _liveCourseId) {
      logDebug('내린 코스($courseId)의 토큰은 올리지 않는다');
      return;
    }
    // **방금 올린 것과 같으면 다시 보내지 않는다**(#395). 앱을 앞으로 낼
    // 때마다 네이티브가 같은 카드의 토큰 감시를 다시 걸고, iOS 는 그때 현재
    // 토큰을 곧바로 다시 준다 — 기억이 없으면 복귀할 때마다 같은 PUT 이
    // 나갔다. 실패하면 기억을 지워 다음에 다시 올린다
    final key = '$courseId|$token';
    if (_registeredLiveToken == key) return;
    _registeredLiveToken = key;
    _ref
        .read(liveActivityRepositoryProvider)
        .register(courseId: courseId, token: token)
        .catchError((Object e) {
          if (_registeredLiveToken == key) _registeredLiveToken = null;
          logDebug('잠금화면 갱신 토큰을 올리지 못했다: $e');
        });
  }

  /// 마지막으로 서버에 올린 카드 토큰 — `코스|토큰`. 같은 값을 되풀이해
  /// 올리지 않게 한다. 카드를 내리면(등록을 지우면) 비운다
  String? _registeredLiveToken;

  /// 네이티브가 **기기**의 push-to-start 토큰을 올려 보냈다 (core #585).
  ///
  /// **카드와 무관하다** — 떠 있는 카드가 없어도 온다. 그래서 `_liveCourseId`
  /// 와 맞춰 보지 않는다. 앱이 켜지면 iOS 가 곧 주고, 갈아 끼우면 또 준다.
  ///
  /// 로그인 전에 올 수 있어 **보관부터** 한다 — 그때 등록하면 JWT 가 없어
  /// 403 만 남는다. 세션이 열려 있으면 바로 올린다
  void _onPushToStartToken(String token) {
    _pushToStartToken = token;
    if (_stopped || !_started) return;
    _registerPushToStart();
  }

  /// 보관해 둔 기기 토큰을 서버에 올린다.
  ///
  /// **부르는 쪽은 기다리지 않는다.** 실패하면 서버가 카드를 처음 띄우지
  /// 못하는 것뿐이고, 앱을 열면 예전처럼 앱이 띄운다. 다음에 앱을 켤 때
  /// 토큰이 또 오므로 그때 다시 시도된다.
  ///
  /// 다만 **해제와는 줄을 맞춘다**(`_pushToStartOp`) — 늦게 닿은 등록이
  /// 로그아웃을 되돌리면 안 된다
  void _registerPushToStart() {
    if (_pushToStartToken == null) return;
    _pushToStartOp = (_pushToStartOp ?? Future<void>.value()).then((_) async {
      // 줄을 서는 사이에 세션이 끝났을 수 있다 — 그때는 올리지 않는다.
      // 여기서 막지 않으면 방금 지운 등록을 다시 만든다
      final token = _pushToStartToken;
      if (_stopped || token == null) return;
      try {
        // 같은 토큰을 이레 안에 올린 적이 있으면 건너뛴다 — iOS 는 앱을 켤
        // 때마다 같은 값을 주고, 그때마다 다시 보내고 있었다
        final memo = _ref.read(pushToStartMemoProvider);
        if (await memo.isRegistered(token) || _stopped) return;
        await _ref
            .read(liveActivityRepositoryProvider)
            .registerPushToStart(token);
        if (_stopped) return;
        await memo.remember(token);
      } on Object catch (e) {
        logDebug('push-to-start 토큰을 올리지 못했다: $e');
      }
    });
  }

  /// 이 기기의 push-to-start 등록을 지운다 — 로그아웃.
  ///
  /// **이 기기 토큰만 보낸다.** 로그아웃은 기기별로 갈리는데(refreshToken 을
  /// 보낸다) 전부 풀면 폰에서 로그아웃한 사용자의 태블릿 잠금화면이 같이
  /// 빈다 — "아무것도 안 했는데 사라졌다" 가 된다.
  ///
  /// 토큰을 모르면(iOS 17.2 미만이라 받은 적이 없다) 부르지 않는다 — 등록된
  /// 적도 없다. 실패는 삼킨다. 탈퇴는 서버가 이벤트로 지우므로 여기서
  /// 실패해도 남지 않는다
  Future<void> _unregisterPushToStart() {
    final token = _pushToStartToken;
    // 이번 실행에서 토큰을 받기 전에 로그아웃했어도 **기억은 지운다** —
    // 앞 실행이 적어 둔 것이 남으면 다음 사람의 등록이 건너뛰어진다
    if (token == null) {
      final op = (_pushToStartOp ?? Future<void>.value()).then(
        (_) => _forgetPushToStart(),
      );
      _pushToStartOp = op;
      return op;
    }
    // **앞의 등록이 끝난 뒤에 나간다.** 먼저 보내면 아직 날아가던 PUT 이
    // 뒤에 닿아 등록이 되살아난다
    final op = (_pushToStartOp ?? Future<void>.value()).then((_) async {
      try {
        await _ref
            .read(liveActivityRepositoryProvider)
            .unregisterPushToStart(token: token);
      } on Object catch (e) {
        logDebug('push-to-start 등록을 지우지 못했다: $e');
      }
      // 다음 사람은 같은 기기 토큰을 자기 계정으로 다시 올려야 한다
      await _forgetPushToStart();
    });
    _pushToStartOp = op;
    return op;
  }

  Future<void> _forgetPushToStart() async {
    try {
      await _ref.read(pushToStartMemoProvider).forget();
    } on Object catch (e) {
      logDebug('push-to-start 등록 기억을 지우지 못했다: $e');
    }
  }

  /// 떠 있던 코스의 서버 등록을 지운다.
  ///
  /// 실패해도 삼킨다 — 안 불러도 결국 정리된다(여행이 끝나면 배치가, 토큰이
  /// 죽으면 410 이 지운다). 이 호출은 그보다 빨리 치우는 것뿐이라, 잠금화면
  /// 정리나 로그아웃을 막을 이유가 없다
  Future<void> _unregisterLive() async {
    final id = _liveCourseId;
    if (id == null) return;
    _liveCourseId = null;
    // 등록을 지웠다 — 같은 코스를 다시 띄우면 토큰을 다시 올려야 한다
    _registeredLiveToken = null;
    try {
      await _ref.read(liveActivityRepositoryProvider).unregister(id);
    } on Object catch (e) {
      logDebug('잠금화면 갱신 등록을 지우지 못했다: $e');
    }
  }
}

final tripActivityControllerProvider = Provider<TripActivityController>((ref) {
  final controller = TripActivityController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
