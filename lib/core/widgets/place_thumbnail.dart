import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../network/image_cache.dart';
import '../theme/tokens/tokens.dart';

/// [PlaceThumbnail] 이 [logicalWidth] 폭으로 그릴 [url] 을 **메모리에 풀어
/// 둔다**. 끝나면(실패해도) 완료된다.
///
/// 디스크에 받아 둔 사진도 화면에 뜨려면 파일을 읽어 풀어야 해, 그 한두
/// 프레임은 자리색만 보인다 — 처음 화면에서 사진이 한 박자 늦게 채워지는 게
/// 이것이다. 카드와 **같은 키**([PlaceThumbnail.providerFor])로 풀어 두면 첫
/// 프레임부터 그려진다.
///
/// 테스트는 이 provider 를 바꿔 끼운다 — 키를 만드는 것만으로 디스크 캐시가
/// 열리며 캐시 폴더를 찾다 죽는다
final placeThumbnailPrecacheProvider =
    Provider<
      Future<void> Function(
        BuildContext context,
        String url,
        double logicalWidth,
      )
    >(
      (ref) =>
          (context, url, logicalWidth) => precacheImage(
            PlaceThumbnail.providerFor(context, url, logicalWidth),
            context,
            onError: (_, _) {},
          ),
    );

/// 장소 썸네일 — 이미지가 없거나 못 불러오면 회색 자리에 아이콘을 남긴다.
///
/// TourAPI 이미지 URL은 종종 죽어 있어서, 빈 칸으로 두면 목록 오른쪽이
/// 들쭉날쭉해 보인다. 자리와 모양은 늘 유지한다.
///
/// 목록의 정사각 썸네일이 기본이고, [width]·[height]를 주면 상세 화면의
/// 가로로 긴 배너로도 쓴다.
class PlaceThumbnail extends StatelessWidget {
  const PlaceThumbnail({
    super.key,
    required this.imageUrl,
    this.size = 70,
    this.radius = 12,
    this.width,
    this.height,
    this.background,
    this.iconSize,
    this.decodeToFit = true,
    this.fit = BoxFit.cover,
    this.deferLoad = false,
  });

  final String? imageUrl;

  /// 정사각일 때의 한 변. [width]·[height]를 주면 그쪽이 이긴다
  final double size;
  final double radius;

  /// 가로로 긴 배너로 쓸 때 — null이면 [size] 정사각이다
  final double? width;
  final double? height;

  /// 자리 색. 화면마다 쓰는 회색이 달라 열어 둔다
  final Color? background;

  /// 아이콘 한 변. null이면 짧은 쪽의 34%로 잡는다
  final double? iconSize;

  /// 그리는 폭까지만 디코드할지(기본). 화면에서는 켜 두는 게 맞다.
  ///
  /// **캡처(공유 이미지)에서는 끈다.** 축소 디코드는 이미지 캐시 키에 폭이
  /// 붙어(`ResizeImage`), 캡처 전에 `precacheImage`로 받아 둔 원본 키와
  /// 달라진다. 그러면 캐시를 못 찾고 다시 디코드하는 사이에 찍혀 사진이
  /// 빈 자리로 남는다(#155). 끄면 프리캐시와 같은 키라 바로 그려진다
  final bool decodeToFit;

  /// 아직 받지 않는다 — **받는 중과 같은 모양**(자리색만)으로 둔다.
  ///
  /// 가로로 넘기는 카드 줄은 카드를 전부 한꺼번에 만든다. 그대로 두면 화면
  /// 밖 사진까지 수십 장을 동시에 받아, 정작 보이는 사진이 대역폭을 나눠
  /// 쓰느라 늦게 떴다. 화면 근처에 온 카드만 받게 한다(홈)
  final bool deferLoad;

  /// 이미지를 자리에 맞추는 방식.
  ///
  /// 기본 [BoxFit.cover]는 자리를 꽉 채우려 가장자리를 잘라낸다 — 장소 사진은
  /// 어디를 잘라도 그 장소라 이 편이 맞다. **글씨가 들어간 배너·포스터는
  /// 다르다.** 비율이 다른 원본을 잘라 채우면 가운데 글씨만 크게 확대돼
  /// 무엇인지 못 읽는다. 그때는 [BoxFit.contain]으로 통째로 넣는다
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final content = Container(
      width: w,
      height: h,
      color: background ?? AppColors.backgroundNormalAlternative,
      child: imageUrl == null
          ? _placeholder(w, h)
          : deferLoad
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, constraints) => CachedNetworkImage(
                imageUrl: imageUrl!,
                cacheManager: appImageCacheManager,
                fit: fit,
                // TourAPI 원본은 장당 100~500KB에 800px가 넘는다. 디스크에
                // 캐시해 다음 실행부터 다시 받지 않고, 그리는 폭(픽셀)까지만
                // 디코드해 메모리·디코드 시간을 줄인다 — 152pt 카드에
                // 원본 해상도 그대로 올릴 이유가 없다
                memCacheWidth: decodeToFit
                    ? decodeWidthFor(context, constraints.maxWidth)
                    : null,
                // 기본 0.5초 페이드인을 끈다 — 디스크 캐시에서 바로 왔는데도
                // 스르륵 나타나 오히려 느려 보인다. 예전처럼 준비되는 즉시 뜬다
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholderFadeInDuration: Duration.zero,
                // 주소가 살아 있어도 서버가 죽어 있을 수 있다 — 빈 칸으로
                // 두면 왜 비었는지 알 수 없으니 자리 아이콘으로 되돌린다
                errorWidget: (_, _, _) => _placeholder(w, h),
                // 받는 동안은 자리색만 — 아이콘까지 띄우면 실패로 보인다
                placeholder: (_, _) => const SizedBox.expand(),
              ),
            ),
    );
    // radius 0이면 자를 것이 없다. 그래도 ClipRRect를 두면 바깥에서 둥글게
    // 자르는 카드와 겹쳐 안티앨리어싱이 두 번 걸리고, 모서리에 계단이 남는다
    if (radius == 0) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: content,
    );
  }

  /// 이 위젯이 [logicalWidth] 폭으로 [url] 을 그릴 때 쓰는 이미지 — 메모리
  /// 캐시의 **키**다. `CachedNetworkImage` 가 안에서 만드는 것(주소 + 그리는
  /// 폭까지 축소)과 같아야 한다. `decodeToFit` 을 끈 자리와는 키가 다르다.
  ///
  /// 이 키로 미리 풀어 두면([placeThumbnailPrecacheProvider]) 첫 프레임부터
  /// 사진이 있다
  static ImageProvider providerFor(
    BuildContext context,
    String url,
    double logicalWidth,
  ) => ResizeImage.resizeIfNeeded(
    decodeWidthFor(context, logicalWidth),
    null,
    CachedNetworkImageProvider(url, cacheManager: appImageCacheManager),
  );

  /// 이 폭(논리 px)으로 그릴 이미지를 몇 픽셀까지 디코드할지.
  ///
  /// 기기 배율을 곱해 화면에서 흐려지지 않는 최소 크기로 잡는다. 폭이
  /// 정해지지 않은 자리(무한 제약)는 화면 폭 기준이다.
  static int decodeWidthFor(BuildContext context, double logicalWidth) {
    final media = MediaQuery.of(context);
    final width = logicalWidth.isFinite ? logicalWidth : media.size.width;
    return (width * media.devicePixelRatio).ceil();
  }

  /// DS Icon/Normal/Image — Material 기본(image_outlined)은 모서리 곡률과
  /// 산 모양이 달라 시안과 어긋난다. 에셋에 박힌 검정은 걷어내고 칠한다
  Widget _placeholder(double w, double h) {
    final side = iconSize ?? (w < h ? w : h) * 0.34;
    return Center(
      child: SvgPicture.asset(
        'assets/icons/ic_image.svg',
        width: side,
        height: side,
        colorFilter: const ColorFilter.mode(
          AppColors.labelDisable,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
