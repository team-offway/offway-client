import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';

/// 코스 링크를 카카오톡으로 보낸다.
///
/// 카카오톡이 깔려 있으면 앱을 바로 열고, 없으면 브라우저의 카카오톡 공유
/// 페이지로 넘긴다 — 어느 쪽이든 받는 사람에게는 같은 링크가 간다.
/// 어느 화면에서 공유했는지 — 링크를 받은 사람에게 보여줄 화면이 갈린다.
enum SharedCourseKind {
  /// 담기 전 추천 코스 — 날짜가 없다
  recommend,

  /// 담아 둔 내 코스 — 날짜·연차가 붙는다
  saved;

  String get path => name;
}

abstract final class KakaoShare {
  /// 공유가 실제로 열렸는지. 실패하면 화면이 그 사실을 알린다.
  static Future<bool> sendCourse({
    required String title,
    required String description,
    required String linkUrl,
    required String shareToken,
    required SharedCourseKind kind,
    String? imageUrl,
  }) async {
    final url = Uri.parse(linkUrl);

    // 실행 파라미터가 없으면 앱을 열지 않는다.
    // 단, 이 주소의 도메인이 카카오 콘솔 [플랫폼 › Web]에 등록돼 있어야
    // 버튼이 동작한다 — 미등록 도메인은 눌러도 아무 반응이 없다
    final webLink = Link(webUrl: url, mobileWebUrl: url);

    // 파라미터가 있으면 앱을 열고, 안 깔린 기기에서는
    // 카카오 콘솔에 등록한 마켓(App Store)으로 보낸다.
    final appLink = Link(
      webUrl: url,
      mobileWebUrl: url,
      // kind를 함께 실어야 앱이 웹과 같은 화면을 띄운다
      androidExecutionParams: {'shareToken': shareToken, 'kind': kind.path},
      iosExecutionParams: {'shareToken': shareToken, 'kind': kind.path},
    );

    final template = FeedTemplate(
      content: Content(
        title: title,
        description: description,
        // 이미지가 없으면 카카오가 회색 자리를 그린다 — 대표 이미지가 있으면 넣는다
        imageUrl: Uri.parse(imageUrl ?? ''),
        // 카드 본문은 웹으로 — 링크를 받는 사람 대부분은 앱이 없다
        link: webLink,
      ),
      buttons: [
        Button(title: '웹으로 보기', link: webLink),
        Button(title: '앱으로 보기', link: appLink),
      ],
    );

    try {
      if (await ShareClient.instance.isKakaoTalkSharingAvailable()) {
        // 카카오톡이 있으면 이 한 번으로 앱까지 띄워 준다
        await ShareClient.instance.shareDefault(template: template);
        return true;
      }

      // 카카오톡이 없으면 웹 공유 창으로 — 로그인 후 같은 링크를 보낼 수 있다
      final uri = await WebSharerClient.instance.makeDefaultUrl(
        template: template,
      );
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}
