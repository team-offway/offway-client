import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/log.dart';

final deviceIdStorageProvider = Provider<DeviceIdStorage>(
  (ref) => DeviceIdStorage(const FlutterSecureStorage()),
);

/// 이 **기기**를 가리키는 값 — 서버가 같은 사용자의 기기를 가른다(core #587).
///
/// 잠금화면 카드가 기기마다 따로 뜨는데, 서버에는 "이 갱신 토큰이 어느 기기
/// 것인지" 를 알 수단이 없었다. 그래서 폰에 카드가 떠 있으면 태블릿을 이미
/// 떠 있는 것으로 보고 띄우기를 영영 안 보냈다.
///
/// **사용자가 아니라 기기에 딸린 값이다.** 로그아웃·탈퇴에도 지우지 않는다 —
/// 지우면 같은 기기가 매번 새 기기로 보여 서버의 표가 늘어나기만 한다.
/// 그래서 토큰 저장소([TokenStorage])와 따로 둔다.
///
/// **`identifierForVendor` 를 쓰지 않는다.** 그 값은 네이티브를 거쳐야 하고,
/// 앱을 지웠다 다시 깔면 바뀐다. 우리가 만든 값을 Keychain 에 두면 Dart 만으로
/// 끝나고, 앱을 지웠다 다시 깔아도 Keychain 이 남아 같은 기기로 이어진다
/// (그때 토큰은 새로 발급되므로 서버가 보기에 "같은 기기의 새 토큰" 이다).
class DeviceIdStorage {
  DeviceIdStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'device_id';

  /// 진행 중인 발급 — 앱이 뜨자마자 여러 곳이 동시에 부르면(푸시 등록·잠금화면)
  /// 각자 만들어 마지막 것만 남는다. 그러면 같은 실행 안에서도 기기 id 가
  /// 갈려 서버가 한 기기를 둘로 센다
  Future<String>? _pending;

  /// 이 기기의 id. 없으면 만들어 저장하고 그것을 돌려준다.
  ///
  /// **한 번 만들면 바뀌지 않는다.** 읽기가 실패하면(Keychain 접근 불가)
  /// 새로 만들어 쓰되 저장은 다시 시도하지 않는다 — 그 실행에서는 임시 값이고,
  /// 다음 실행에서 정상이면 제대로 자리잡는다
  Future<String> get() => _pending ??= _load();

  Future<String> _load() async {
    try {
      final saved = await _storage.read(key: _key);
      if (saved != null && saved.isNotEmpty) return saved;
    } on Object catch (e) {
      logDebug('기기 id 를 읽지 못했다: $e');
    }
    final id = newId();
    try {
      await _storage.write(key: _key, value: id);
    } on Object catch (e) {
      // 저장이 안 돼도 이번 실행에서는 이 값을 쓴다 — 없는 것보다 낫다
      logDebug('기기 id 를 저장하지 못했다: $e');
    }
    return id;
  }

  /// 32자리 hex — UUID 와 같은 128비트를 하이픈 없이 담는다.
  ///
  /// 서버가 문자열로만 다루므로 형식을 맞출 이유가 없고, 하이픈이 없으면
  /// 로그·URL 어디에 들어가도 그대로다
  @visibleForTesting
  static String newId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
