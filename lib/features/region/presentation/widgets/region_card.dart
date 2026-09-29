import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/tokens/tokens.dart';
import '../../../../core/widgets/place_thumbnail.dart';
import '../../../policy/domain/region_benefit.dart';
import '../../../policy/presentation/benefit_badge.dart';
import '../../../policy/presentation/region_benefits_sheet.dart';

/// 지역 카드 표시 형태
enum RegionCardStyle {
  /// 홈 가로 리스트 — 폭 152 고정
  boxed,

  /// 목록 그리드 — 폭은 그리드가 결정
  plain,
}

/// 지역 카드 (홈 가로 리스트 · 추천 여행지 목록 공용).
/// DS Card 컴포넌트 기준: 4:3 썸네일(radius 12) + 제목 + 설명 + 회색 뱃지.
class RegionCard extends StatelessWidget {
  const RegionCard({
    super.key,
    required this.region,
    this.style = RegionCardStyle.boxed,
    this.loadImage = true,
  });

  final Map<String, dynamic> region;
  final RegionCardStyle style;

  /// 사진을 지금 받을지 — 화면 밖 카드는 가까워질 때까지 미룬다
  /// ([PlaceThumbnail.deferLoad]). 모양·크기는 그대로다
  final bool loadImage;

  /// 홈 가로 리스트에서 쓰는 고정 폭
  static const boxedWidth = 152.0;

  /// 사진이 테두리 안쪽으로 들어가는 여백 — 사방 1
  static const _imageInset = 1.0;

  /// 홈 카드 **사진**의 폭. 카드 폭에서 테두리 안쪽 여백을 뺀 값이다.
  ///
  /// 첫 화면 사진을 미리 풀 때(`decodeHomeFirstImages`) 이 폭을 써야 한다 —
  /// 카드 폭(152)으로 풀면 사진이 실제로 찾는 키(150)와 달라 헛일이 된다
  static const boxedImageWidth = boxedWidth - _imageInset * 2;

  /// 텍스트·뱃지 영역의 기본 높이 (제목 1줄 + 설명 2줄 + 뱃지 + 간격).
  ///
  /// 설명은 두 줄까지 보여준다(시안) — 한 줄(18)을 더 잡아 둔다. 설명이
  /// 한 줄이거나 없는 카드는 그만큼 아래가 비지만, 가로 목록·그리드는
  /// 셀 높이가 하나라 가장 긴 경우에 맞춰야 옆 카드와 줄이 맞는다
  static const _textAreaHeight = 102.0;

  /// 그리드가 이 카드를 담을 때 필요한 셀 높이.
  /// 카드 구성이 바뀌면 이 공식만 고치면 되도록 카드 옆에 둔다.
  /// 텍스트는 시스템 글자 크기 배율을 따르므로 그 배율만큼 여유를 준다.
  static double mainAxisExtentFor(BuildContext context, double columnWidth) {
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return columnWidth * 3 / 4 + _textAreaHeight * textScale + 8;
  }

  /// 홈 가로 리스트를 담을 높이. 하드코딩하면 카드 내용보다 커져 아래에
  /// 빈 공간이 남고, 다음 섹션이 그만큼 밀려 내려간다
  static double boxedHeightFor(BuildContext context) =>
      mainAxisExtentFor(context, boxedWidth);

  @override
  Widget build(BuildContext context) {
    // 혜택 — 서버가 홈·상세를 한 모양으로 맞췄다(core #418). 대표 하나는
    // `benefit`, 그 지역의 전부는 `benefits`(있으면, 대표가 맨 앞)다
    final benefits = RegionBenefit.parseList(region['benefits']);
    final benefit =
        benefits.firstOrNull ?? RegionBenefit.tryParse(region['benefit']);
    // 장소 카드(홈 위 섹션)면 이름이 들어 있다. 지역 카드는 null이다
    final placeName = region['placeName'] as String?;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DS Thumbnail: 4:3 고정비, radius 12, 헤어라인 보더.
        //
        // 보더를 Container에 두고 clipBehavior로 자르면 자식이 보더 '안쪽'으로
        // 잘려 모서리에 계단이 남는다(QA: 카드 라운드가 깨져 보여요).
        // 시안대로 사진을 먼저 둥글게 자르고 그 위에 선을 덮는다
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 사진은 테두리 **안쪽**까지만 그린다.
              //
              // 바깥 곡률 12로 자르고 그 위에 1px 선을 덮으면, 선이 안쪽으로
              // 그려져 실효 곡률이 11이 된다. 그 1px 어긋난 자리에 사진이
              // 비쳐 모서리가 계단처럼 보인다. 안쪽 곡률(11)로 잘라 덮는다
              Padding(
                padding: const EdgeInsets.all(_imageInset),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  clipBehavior: Clip.antiAliasWithSaveLayer,
                  child: _buildImage(),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lineNormalAlternative),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // 홈 위 섹션은 장소('삼탄아트마인'), 목록·아래 섹션은 지역이다.
        // 장소 카드는 사진 오버레이에 지역명이 따로 있어 여기서 겹치지 않는다
        Text(
          (region['placeName'] as String?) ?? _regionLabel(region),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body2NormalBold.copyWith(
            color: AppColors.labelNormal,
          ),
        ),
        // 부제를 만들 재료가 없는 장소가 있다(core #305 — 숙박 61%·체험 60%).
        // 서버가 지어내지 않고 비워 보내므로 앱은 그 줄을 접는다
        if (region['description'] case final String desc
            when desc.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            desc,
            // 시안: 설명은 두 줄까지 — 한 줄로 자르면 '폐광촌에서 다시 태어난…'
            // 처럼 문장이 끊긴다
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label2Medium.copyWith(
              color: AppColors.labelAlternative,
            ),
          ),
        ],
        if (benefit != null) ...[
          const SizedBox(height: 6),
          // 뱃지를 누르면 혜택 상세가 열린다 — 카드 전체 탭(지역 상세)보다
          // 안쪽이라 뱃지가 제스처를 먼저 받는다. 혜택이 여럿이면 `+1`을
          // 붙이고, 먼저 고르는 시트를 연다
          BenefitBadge(
            benefit: benefit,
            size: BenefitBadgeSize.card,
            extraCount: benefits.length > 1 ? benefits.length - 1 : 0,
            onTap: benefits.length > 1
                ? () => showRegionBenefitsSheet(
                    context,
                    regionLabel: _regionLabel(region),
                    benefits: benefits,
                  )
                : null,
          ),
        ],
      ],
    );

    return GestureDetector(
      // 장소 카드의 id는 지역이 아니라 poiContentId다 — 지역 상세로 보내면
      // 엉뚱한 지역이 열린다. 장소면 장소 상세로 간다
      onTap: () => context.push(
        placeName == null
            ? AppRoutes.regionDetailPath(region['id'] as String)
            : AppRoutes.poiDetailPath(
                region['id'] as String,
                name: placeName,
                // 상단바에 띄울 지역 — 카드 오버레이와 같은 "동구 · 부산광역시".
                // 시군구만 넘기면 동구가 어느 동구인지 상세에서 알 수 없다
                regionName: _regionLabel(region),
              ),
      ),
      child: style == RegionCardStyle.boxed
          ? SizedBox(width: boxedWidth, child: content)
          : content,
    );
  }

  Widget _buildImage() {
    final imageUrl = region['imageUrl'] as String?;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 사진이 없거나 죽어 있으면 자리 아이콘을 남긴다 — 빈 회색 칸으로
        // 두면 아직 불러오는 중인지 없는 것인지 구분되지 않는다
        PlaceThumbnail(
          imageUrl: imageUrl,
          width: double.infinity,
          height: double.infinity,
          radius: 0,
          iconSize: 48,
          deferLoad: !loadImage,
        ),
        // DS Thumbnail Overlay — 밝은 사진 위에서도 글자가 읽히도록
        // 위쪽에만 검정을 35%까지 깔고 아래로 사라지게 한다
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.staticBlack.withValues(alpha: 0.35),
                  AppColors.staticBlack.withValues(alpha: 0),
                ],
              ),
            ),
            child: Text(
              _regionLabel(region),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption1Regular.copyWith(
                color: AppColors.staticWhite,
                shadows: const [
                  Shadow(blurRadius: 12, color: Color(0x29000000)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 로딩 중 [RegionCard] 자리에 놓는 회색 블록.
///
/// 카드가 들어올 자리를 미리 잡아둬 데이터가 도착할 때 화면이 밀리지 않는다.
/// 치수는 카드와 같은 값을 써야 하므로 카드 옆에 둔다.
class RegionCardSkeleton extends StatelessWidget {
  const RegionCardSkeleton({
    super.key,
    this.style = RegionCardStyle.boxed,
    this.hasBadge = true,
  });

  final RegionCardStyle style;

  /// 들어올 카드에 혜택 뱃지가 있는지.
  /// 실제 카드는 뱃지가 없으면 그 줄을 통째로 빼므로, 여기서도 맞춰야
  /// 데이터가 도착할 때 카드 아래가 들썩이지 않는다.
  final bool hasBadge;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: _Block(radius: 12, height: double.infinity),
        ),
        const SizedBox(height: 6),
        // 제목 한 줄 — 카드에서 body2NormalBold 1줄이 차지하는 높이
        const _Block(width: double.infinity, height: 22),
        const SizedBox(height: 4),
        // 설명 두 줄 — 실제 문구처럼 첫 줄은 길고 둘째 줄은 짧게 둔다
        const FractionallySizedBox(
          widthFactor: 0.82,
          alignment: Alignment.centerLeft,
          child: _Block(height: 18),
        ),
        const FractionallySizedBox(
          widthFactor: 0.55,
          alignment: Alignment.centerLeft,
          child: _Block(height: 18),
        ),
        if (hasBadge) ...[
          const SizedBox(height: 6),
          const _Block(width: 62, height: 20),
        ],
      ],
    );

    return style == RegionCardStyle.boxed
        ? SizedBox(width: RegionCard.boxedWidth, child: content)
        : content;
  }
}

/// 스켈레톤을 이루는 회색 사각형 하나
class _Block extends StatelessWidget {
  const _Block({this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.backgroundNormalAlternative,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// '시군구 · 시도' — 장소 카드는 시도가 없어 가운뎃점만 남으므로 붙이지 않는다
String _regionLabel(Map<String, dynamic> region) {
  final name = region['name'] as String? ?? '';
  final sido = region['sido'] as String? ?? '';
  return sido.isEmpty ? name : '$name · $sido';
}
