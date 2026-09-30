import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/pending_deep_link.dart';
import '../../../core/theme/tokens/tokens.dart';

/// 앱을 켜면 처음 보이는 화면 (O-00).
///
/// 하는 일은 잠깐 워드마크를 보여주는 것뿐이다 — 토큰 확인은 [main]이 라우터를
/// 만들기 전에 이미 끝내 놓는다. 다음 목적지도 그때 정해진 초기 경로를 그대로
/// 따른다(로그인했으면 홈, 아니면 온보딩).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// 이 시간이 지나면 갈 곳. [main]이 정한 초기 경로다.
  final String next;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// 워드마크가 눈에 남을 만큼만 머문다. 더 끌면 앱이 느려 보인다.
  ///
  /// 1.2초였다 — 네이티브 런치 화면까지 더하면 로고가 1.5초 넘게 떠 있었다.
  /// 0.7초로 줄였다가(#396) 0.9초로 조정했다. 네이티브 런치 화면을 더하면
  /// 대략 1.1~1.4초다. 이 동안 로그인한 사용자는 홈 데이터와 첫 화면 사진을
  /// 뒤에서 받는다
  static const _hold = Duration(milliseconds: 900);

  /// 워드마크 중심의 세로 위치(화면 높이 대비).
  ///
  /// 시안 402x874에서 텍스트 박스가 `top: calc(50% - 84.72px)`, 높이 49다.
  /// 중심은 437 - 84.72 + 24.5 = 376.78 → 화면 높이의 43.11% 지점.
  ///
  /// 네이티브 런치스크린도 같은 값을 쓴다 — `LaunchScreen.storyboard`의 centerY
  /// 제약 multiplier. 한쪽만 바꾸면 두 화면이 어긋나 로고가 튄다.
  static const _wordmarkY = 0.4311;

  /// 로고 크기 — 네이티브 런치스크린의 LaunchImage(125x38pt)와 같아야 한다.
  /// 1pt만 달라도 엔진이 뜨는 순간 로고가 씰룩인다 (#131)
  static const _logoWidth = 125.0;
  static const _logoHeight = 38.0;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_hold, _goNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goNext() {
    if (!mounted) return;
    // go: 스플래시는 뒤로 돌아올 곳이 아니므로 스택에 남기지 않는다
    context.go(widget.next);
    // 스플래시가 떠 있는 동안 링크(위젯·공유)로 열렸으면 그 화면으로 —
    // 먼저 올려 두면 방금의 go 가 지우므로 여기서 연다
    final pending = ref.read(pendingDeepLinkProvider.notifier).take();
    if (pending == null) return;
    pending.replace ? context.go(pending.route) : context.push(pending.route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundNormal,
      // 네이티브 런치스크린(LaunchScreen.storyboard)과 같은 자리에 그린다. iOS가
      // 먼저 띄우는 그 화면은 없앨 수 없으므로, 위치가 어긋나면 엔진이 뜨는 순간
      // 로고가 튀어 스플래시가 두 번 뜬 것처럼 보인다.
      // Alignment로 43.11%를 주면 안 된다 — Alignment는 화면이 아니라
      // (화면 - 로고 높이) 안에서 비율을 잡아 로고가 네이티브보다 2.6pt 위에
      // 놓이고, 엔진이 뜨는 순간 로고가 위로 튄다 (#131).
      // 네이티브처럼 '로고 중심 = 화면 높이 x 43.11%'를 직접 계산한다
      body: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.only(
            top: constraints.maxHeight * _wordmarkY - _logoHeight / 2,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SvgPicture.asset(
              'assets/icons/logo_wordmark_blue.svg',
              width: _logoWidth,
              height: _logoHeight,
              semanticsLabel: 'Offway',
            ),
          ),
        ),
      ),
    );
  }
}
