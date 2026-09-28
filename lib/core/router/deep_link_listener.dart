import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/course_wizard/application/course_wizard_provider.dart';
import 'app_router.dart';
import 'pending_deep_link.dart';
import 'widget_deep_link.dart';
import '../storage/secure_storage.dart';

/// 공유 링크로 앱이 열렸을 때 그 코스 화면으로 보낸다.
///
/// 카카오톡 '앱으로 보기'는 앱 스킴에 `shareToken`을 실어 보낸다
/// (`kakao{앱키}://kakaolink?shareToken=...`). 이 값이 없으면 그냥 홈에 머문다.
///
/// 앱이 꺼져 있다 열린 경우(첫 링크)와 떠 있는 상태에서 열린 경우를 모두 받는다.
class DeepLinkListener extends ConsumerStatefulWidget {
  const DeepLinkListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends ConsumerState<DeepLinkListener> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  Future<void> _listen() async {
    // 앱이 꺼져 있다 링크로 열린 경우
    try {
      final initial = await _appLinks.getInitialLink();
      // 기다리는 사이 화면이 사라졌으면 여기서 끝낸다 — dispose가 이미 지나가
      // 아래에서 구독을 만들면 아무도 취소해 주지 않는다
      if (!mounted) return;
      if (initial != null) _handle(initial);
    } on Exception {
      // 링크를 못 읽어도 앱은 홈에서 정상 동작한다
      if (!mounted) return;
    }
    _subscription = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(Uri uri) async {
    // 위젯을 눌러 열렸다 — 공유 링크와 다른 스킴이라 먼저 가른다.
    //
    // **로그인 여부는 누른 그 순간의 토큰으로 본다.** 예전에는 앱을 켤 때
    // 정한 첫 화면(홈이면 로그인)으로 봐서, 켠 뒤 세션이 만료돼 로그인 화면에
    // 있는데도 위젯을 누르면 로그인을 건너뛰어 홈에 앞사람의 이름·연차가
    // 보였다. 반대로 로그인 전에 켰다가 로그인한 사람은 위젯을 눌러도 로그인
    // 화면으로 갔다. 세션 만료·로그아웃은 토큰을 지우므로 이 판단이 맞는다
    final signedIn = await hasStoredSession(ref.read(secureStorageProvider));
    if (!mounted) return;
    final widgetRoute = widgetDeepLinkRoute(uri, signedIn: signedIn);
    if (widgetRoute != null) {
      // **스택을 바꾼다(go).** 위저드 중간에 위젯을 누르면 push 는 옛 위저드
      // 화면 위에 새 위저드를 얹어, 뒤로 가면 비워진 초안의 옛 화면이 나온다.
      // 코스 상세도 같은 화면이 두 장 쌓이지 않게 같은 규칙이다.
      //
      // 홈으로 가는 링크도 그대로 보낸다 — 위저드·코스 상세에 있을 수 있어
      // 조기 반환하면 눌러도 아무 일이 없다. go 라 이미 홈이면 같은 화면이
      // 쌓이지 않는다
      _open(
        widgetRoute,
        replace: true,
        // 홈의 '코스 추천받기' 와 같이 처음부터 — 지난 선택이 남지 않게
        before: widgetRoute == AppRoutes.wizardOrigin
            ? () => ref.read(courseWizardProvider.notifier).reset()
            : null,
      );
      return;
    }

    final token = uri.queryParameters['shareToken'];
    // 어느 화면에서 공유했는지 — 없으면 추천코스로 본다(예전 링크 대비)
    final kind = uri.queryParameters['kind'];
    if (token == null || token.isEmpty) return;
    _open(AppRoutes.sharedCoursePath(token, kind: kind));
  }

  /// 목적지로 간다 — 라우터가 준비된 뒤, 스플래시가 끝난 뒤.
  ///
  /// context로는 라우터를 못 찾는다 — MaterialApp.router의 builder는 라우터
  /// 바깥이라 그 안에서 GoRouter.of(context)를 부르면 예외가 난다. 라우터를
  /// 직접 잡는다. 이동은 다음 프레임으로 미뤄 첫 프레임과 부딪히지 않게 한다.
  ///
  /// **스플래시가 떠 있으면 맡겨 둔다.** 그 위에 올리면 스플래시가 끝나며
  /// `go(next)` 로 스택을 갈아 치워 지운다 — [pendingDeepLinkProvider]
  void _open(String route, {bool replace = false, VoidCallback? before}) {
    final router = ref.read(appRouterProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      before?.call();
      if (router.routerDelegate.currentConfiguration.uri.path ==
          AppRoutes.splash) {
        ref.read(pendingDeepLinkProvider.notifier).set(route, replace: replace);
        return;
      }
      replace ? router.go(route) : router.push(route);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 지금 로그인돼 있는가 — 저장된 토큰으로 본다(앱 시작 판단 `main.dart` 와
/// 같은 기준). 못 읽으면 로그인 전으로 본다
Future<bool> hasStoredSession(TokenStorage storage) async {
  try {
    return await storage.accessToken != null;
  } on Exception {
    return false;
  }
}
