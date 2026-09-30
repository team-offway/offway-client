import 'dart:io';

import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Apple 로그인 결과.
/// 서버에는 [identityToken]을 넘겨 검증받는다(카카오의 액세스 토큰에 대응).
class AppleLoginResult {
  const AppleLoginResult({
    required this.identityToken,
    required this.authorizationCode,
    required this.userIdentifier,
    this.email,
    this.fullName,
  });

  /// 서버가 Apple 공개키로 검증할 JWT
  final String identityToken;

  /// 서버가 Apple과 토큰을 교환할 때 쓰는 1회용 코드.
  ///
  /// **탈퇴 시 Apple 연결 해제(revoke)에 필요하다** — 앱 심사 항목이다
  /// (5.1.1(v)). Apple의 `/auth/revoke`는 refresh 토큰만 받는데, 서버가
  /// 그것을 얻는 유일한 길이 이 코드를 `/auth/token`에서 교환하는 것이다.
  ///
  /// **1회용이고 5분이면 만료된다** — 로그인하는 그 순간 함께 보내야 하고
  /// 나중에 따로 받아올 수 없다. [identityToken]은 신원 증명서라 취소할
  /// 대상이 아니므로 이 값을 대신하지 못한다.
  final String authorizationCode;

  /// Apple이 앱마다 부여하는 고유 사용자 ID
  final String userIdentifier;

  /// 최초 로그인 시에만 제공. 사용자가 가리기를 선택하면 릴레이 주소가 온다.
  final String? email;

  /// 최초 로그인 시에만 제공
  final String? fullName;
}

/// 사용자가 로그인 시트를 닫는 등 스스로 취소한 경우
class AppleLoginCancelled implements Exception {
  const AppleLoginCancelled();
}

/// iOS 외 플랫폼에서 호출된 경우
class AppleLoginUnsupported implements Exception {
  const AppleLoginUnsupported();

  @override
  String toString() => 'Apple 로그인은 iOS에서만 지원합니다.';
}

class AppleAuthService {
  const AppleAuthService();

  /// 취소 시 [AppleLoginCancelled], iOS가 아니면 [AppleLoginUnsupported]를 던진다.
  ///
  /// 이름·이메일은 **최초 로그인 1회만** 내려오므로, 서버가 이때 저장해야 한다.
  /// 재로그인 시에는 null이 오는 것이 정상.
  Future<AppleLoginResult> login() async {
    // iOS 전용 앱이다 — 그 밖의 플랫폼(테스트 환경 등)에서는 부르지 않는다
    if (!Platform.isIOS) throw const AppleLoginUnsupported();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final identityToken = credential.identityToken;
      if (identityToken == null) {
        throw StateError('Apple identityToken을 받지 못했습니다.');
      }
      final given = credential.givenName;
      final family = credential.familyName;
      final name = [family, given].whereType<String>().join();
      return AppleLoginResult(
        identityToken: identityToken,
        // SDK가 non-nullable로 주므로 항상 들어온다
        authorizationCode: credential.authorizationCode,
        userIdentifier: credential.userIdentifier ?? '',
        email: credential.email,
        fullName: name.isEmpty ? null : name,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AppleLoginCancelled();
      }
      rethrow;
    }
  }
}
