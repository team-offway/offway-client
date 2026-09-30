import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_envelope.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/tokens.dart';
import '../../../core/utils/leave_format.dart';
import '../../../core/widgets/data_source_note.dart';
import '../../../core/widgets/curated_link_card.dart';
import '../../../core/widgets/info_card.dart';
import '../../leave/presentation/widgets/golden_holiday_card.dart';
import '../../../core/widgets/curated_link_section.dart';
import '../../auth/application/current_user_provider.dart';
import '../../../core/utils/nickname.dart';
import '../../course/presentation/trip_outcome_prompt.dart';
import '../../update/presentation/update_prompt.dart';
import '../../notification/application/notification_provider.dart'
    show hasUnreadNotificationsProvider;
import '../../region/presentation/widgets/category_chip.dart';
import '../../region/presentation/widgets/leave_pick_card.dart';
import '../../policy/data/region_policies_provider.dart';
import '../../region/presentation/widgets/region_card.dart';
import '../../course_wizard/presentation/wizard_entry.dart';
import '../application/home_providers.dart';
import '../../../core/network/image_cache.dart';

/// 히어로 카드 CTA 배경 — Figma가 Atomic Neutral/22(#303030)를 직접 쓴다
const _heroCtaBackground = AppPalette.neutral22;

/// O-03 · 홈
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TripOutcomePrompt, UpdatePrompt, WidgetsBindingObserver {
  /// '이번달 추천 여행지' 가로 줄 — 어디까지 봤는지로 사진을 받을 카드를 정한다
  final _placesScroll = ScrollController();

  /// 사진을 받기 시작한 카드 수. 한 번 받은 카드는 되돌리지 않는다 — 다시
  /// 앞으로 넘겨도 사진이 사라지지 않게. 목록이 바뀌면(칩·섞기) 다시 센다
  int _placesLoadUntil = 0;
  Object? _placesListKey;

  /// 첫 화면 사진을 다 받았다 — 이제 나머지 카드도 예전처럼 전부 받는다
  bool _placesReleased = false;

  /// 첫 화면 사진을 기다리는 한계 — 큰 원본(2MB 넘는 것도 있다)이 끼어도
  /// 나머지가 한없이 기다리지 않게
  static const _placesReleaseTimeout = Duration(seconds: 3);

  /// **보이는 사진을 먼저 받고, 끝나면 나머지를 푼다.**
  ///
  /// 카드를 전부 만들면 사진 요청 50여 개가 왼쪽부터 줄을 서고 캐시가 10장씩
  /// 받는다 — 보이는 3~4장이 화면 밖 6~7장과 대역폭을 나눠 썼다. 처음에는
  /// 보이는 카드와 뒤 두 장만 받고, 그게 끝나면(또는 [_placesReleaseTimeout])
  /// 예전처럼 전부 푼다. 그 뒤의 동작은 예전과 같다
  void _releasePlacesAfter(Object listKey, List<String> firstUrls) {
    final prefetch = ref.read(imagePrefetcherProvider);
    Future.wait([for (final url in firstUrls) prefetch(url)])
        .timeout(_placesReleaseTimeout, onTimeout: () => const [])
        .whenComplete(() {
          if (!mounted || _placesListKey != listKey) return;
          setState(() => _placesReleased = true);
        });
  }

  /// 보이는 카드 뒤로 미리 받아 둘 장 수 — 넘기자마자 빈칸이 보이지 않게
  static const _placesLookahead = 2;

  /// 지금 스크롤 위치에서 사진을 받아야 할 카드 수(앞에서부터)
  int _placesVisibleUntil() {
    const step = RegionCard.boxedWidth + 20;
    final width = MediaQuery.sizeOf(context).width;
    final offset = _placesScroll.hasClients ? _placesScroll.offset : 0.0;
    return ((offset + width) / step).ceil() + _placesLookahead;
  }

  void _onPlacesScroll() {
    // 다 풀렸으면 할 일이 없다 — 줄 끝에서는 보이는 수가 카드 수를 넘어
    // 스크롤마다 홈 전체를 다시 그렸다
    if (_placesReleased) return;
    if (_placesVisibleUntil() > _placesLoadUntil) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _placesScroll.addListener(_onPlacesScroll);
    WidgetsBinding.instance.addObserver(this);
    // 홈에 들어올 때마다 종의 점을 다시 맞춘다 — 로그인 직후이거나 앞선
    // 조회가 실패했을 수 있다. 가벼운 요청 하나다
    unawaited(ref.read(hasUnreadNotificationsProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _placesScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드에 둔 사이 알림이 쌓였을 수 있다. 푸시 배너를 못 봤거나
    // 알림을 꺼 둔 사용자는 이 경로 말고는 점이 켜질 길이 없다
    if (state != AppLifecycleState.resumed) return;
    unawaited(ref.read(hasUnreadNotificationsProvider.notifier).refresh());
  }

  /// 로딩 중 깔아둘 지역 카드 자리 수 — 첫 화면에 걸쳐 보이는 만큼만
  static const _skeletonCardCount = 3;

  /// '이번 연차엔 여기 어때요?' 카드 개수 — 시안 노트: 최소 3 ~ 최대 7
  static const _minLeavePicks = 3;

  /// 지역 카드 아래에서 '이번 연차엔' 제목까지.
  ///
  /// 시안은 혜택 뱃지 글자 아래로 42다. 뱃지에 자체 아래 여백 3이 있어
  /// 그만큼 덜 준다
  static const _sectionGap = 39.0;

  /// 고른 칩 `{key, label}` — null이면 '전체'
  Map<String, dynamic>? _selected;

  /// 당겨서 새로고침한 횟수가 곧 섞는 씨앗 — null이면 아직 안 당겨 서버 순서다.
  /// 당길 때마다 1씩 올라 매번 다른 순서가 되고, 같은 횟수면 같은 순서라
  /// 테스트가 재현된다
  int? _shuffleSeed;

  /// 당겨서 새로고침 — 서버를 다시 읽고, 끝나면 카드 순서를 섞는다.
  ///
  /// 다시 읽는 동안 Riverpod이 이전 값을 남겨 두어 카드가 사라지지 않는다.
  /// 못 읽으면 각 섹션이 제 자리에서 알리므로 여기서는 삼킨다 — 그래도
  /// 순서는 섞는다. 당겼는데 아무것도 안 바뀌는 것보다 낫다.
  ///
  /// **종류를 가리지 않고 삼킨다.** 서버 오류(`ApiException`)만이 아니라
  /// 응답을 카드로 바꾸다 나는 예외도 프로바이더를 거쳐 여기로 온다. 하나라도
  /// 흘리면 새로고침 Future가 실패해 당김 컨트롤이 접히지 않는다
  Future<void> _refresh() async {
    ref.invalidate(homeSnapshotProvider);
    // 정책도 다시 읽는다 — 세션 동안 한 번만 읽는 값이라, 자정을 넘겨
    // 정책 기간이 바뀌었거나 정책이 새로 들어왔을 때 당기면 새 값이 오게.
    // 색인([regionPoliciesProvider])은 이 목록을 보므로 함께 다시 만든다
    ref.invalidate(allPoliciesProvider);
    try {
      await ref.read(homeSnapshotProvider.future);
    } catch (_) {
      // 섹션이 알린다
    }
    if (mounted) setState(() => _shuffleSeed = (_shuffleSeed ?? 0) + 1);
  }

  /// 선택된 카테고리의 콘텐츠가 있는 카드만 남긴다 — 더보기 화면과 같은 규칙
  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> all) =>
      filterCardsByCategory(all, _selected);

  /// 온보딩으로 한 번만 보낸다 — 프로바이더가 다시 읽힐 때마다 go가
  /// 겹치면 화면이 덜컥거린다
  bool _redirectedToOnboarding = false;

  /// 잔여 연차가 없으면 온보딩으로.
  ///
  /// 아직 못 읽었거나 실패했으면 아무것도 하지 않는다 — 서버를 못 부른 것과
  /// '연차가 없다'는 다르다. 홈은 그대로 두고 다음 조회를 기다린다.
  void _redirectIfLeaveMissing(AsyncValue<Map<String, dynamic>> user) {
    if (_redirectedToOnboarding) return;
    if (!leaveOnboardingNeeded(user)) return;

    _redirectedToOnboarding = true;
    // build 도중에는 화면을 바꿀 수 없다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppRoutes.onboardingLeave);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 홈 API의 user.name은 비회원까지 아우르는 값이라 로그인해도 '게스트'가
    // 온다(core HomeResponse.GUEST_NAME). 로그인했으면 /users/me의 이름으로
    // 덮은 값을 쓴다
    final user = ref.watch(currentUserProvider);
    final regions = ref
        .watch(homeRegionsProvider)
        .whenData((r) => shuffledForRefresh(r, _shuffleSeed));
    final places = ref
        .watch(homePlacesProvider)
        .whenData((p) => shuffledForRefresh(p, _shuffleSeed));

    // 연차를 등록하지 않았으면 온보딩으로 돌려보낸다.
    //
    // 로그인 직후의 분기(isNewUser)만으로는 부족하다 — 그 값은 '이번에
    // 계정을 만들었나'라서 온보딩에서 앱을 껐다 켠 사람에게는 다시 false다.
    // 그러면 잔여 연차가 빈 채로 홈에 갇혀, 코스 추천이 제 값을 못 낸다.
    _redirectIfLeaveMissing(user);

    // 시안 노트: 여행 종료 D+1 첫 홈 진입시 "다녀오셨나요?" 모달
    final askingTrip = watchTripOutcomePrompt();
    // 스토어에 새 버전이 있으면 업데이트 시트. "다녀오셨나요?"가 지금 뜨는
    // 중이면 그쪽이 먼저다 — 모달 둘이 겹치면 하나는 뒤에 가려 못 본다.
    // 답을 받으면 여행 목록이 다시 읽혀 이 build가 또 돌고, 그때 뜬다
    if (!askingTrip) watchUpdatePrompt();

    return Scaffold(
      backgroundColor: AppColors.backgroundNormal,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          // 내용이 짧아도 당길 수 있어야 새로고침이 되고, 당김 컨트롤은
          // 튕기는(overscroll) 물리를 전제한다
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // 당겨서 새로고침 — 사파리·메일과 같은 iOS 시스템 스피너다.
            // 당기는 만큼 살이 하나씩 드러나고, 넘으면 돌기 시작한다
            CupertinoSliverRefreshControl(onRefresh: _refresh),
            SliverPadding(
              padding: const EdgeInsets.only(top: 10, bottom: 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildTopBar(),
                  const SizedBox(height: 21),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildLeaveCard(user),
                  ),
                  // 시안 실측: 연차 카드~히어로 10
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildHeroCard(context, user),
                  ),
                  // 시안 실측: 히어로~섹션 제목 42
                  const SizedBox(height: 42),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(
                          '이번달 추천 여행지',
                          // 시안은 Headline 1/Bold(18) — heading1Bold(22)와 이름이 한 글자
                          // 차이라 잘못 집기 쉽다
                          style: AppTypography.headline1Bold.copyWith(
                            color: AppColors.labelNormal,
                          ),
                        ),
                        const Spacer(),
                        // 시안에서 '더보기' 글자는 숨겨지고 쉐브론만 남았다
                        Semantics(
                          button: true,
                          label: '추천 여행지 더 보기',
                          child: GestureDetector(
                            key: const Key('home-region-more'),
                            onTap: () => context.push(AppRoutes.regionList),
                            behavior: HitTestBehavior.opaque,
                            // **색을 덮지 않는다.** 에셋에 fill-opacity 0.61이
                            // 박혀 있어 그대로 두면 #37383C@61%가 나온다.
                            // labelAlternative(알파 0.61)를 srcIn으로 또
                            // 씌우면 0.37로 곱해져 흐려졌다
                            child: SvgPicture.asset(
                              'assets/icons/ic_chevron_right.svg',
                              // DS 쉐브론(Tight)은 12×24 비율이다
                              width: 12,
                              height: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 시안 실측: 제목~칩 16, 칩~카드 16
                  const SizedBox(height: 16),
                  _buildCategoryRow(),
                  const SizedBox(height: 16),
                  _buildRegionCards(places, fallback: regions),
                  const SizedBox(height: _sectionGap),
                  _buildLeavePicks(regions),
                  _buildCuratedLinks(),
                  // 공공데이터 출처 (core #417) — 화면 끝에 텍스트로 한 줄.
                  // 공모전 규정이 요구하고, 서버가 이 응답에 실제로 쓴 기관만 준다
                  DataSourceNote(
                    sources:
                        ref.watch(homeSnapshotProvider).value?.sources ??
                        const <DataSource>[],
                    padding: const EdgeInsets.fromLTRB(20, _sectionGap, 20, 0),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 3, 20, 0),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/logo_wordmark.svg',
            height: 24,
            semanticsLabel: 'Offway',
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push(AppRoutes.notifications),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SvgPicture.asset(
                  'assets/icons/ic_bell.svg',
                  width: 24,
                  height: 24,
                ),
                // 안 읽은 알림이 있으면 종 오른쪽 위에 점을 찍는다
                if (ref.watch(hasUnreadNotificationsProvider))
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryNormal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveCard(AsyncValue<Map<String, dynamic>> user) {
    final days = user.value?['remainingLeaveDays'];
    return GestureDetector(
      onTap: () => context.push(AppRoutes.myLeave),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundNormalAlternative,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.backgroundNormal,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/ic_timer.svg',
                width: 26,
                height: 26,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '남은 연차 일수',
              style: AppTypography.body1NormalMedium.copyWith(
                color: AppColors.labelNormal,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              // 서버가 double로 주므로(반차 0.5 단위) 15.0일로 보이지 않게 다듬는다
              days == null ? '-' : '${formatLeaveDays(days as num)}일',
              style: AppTypography.body1NormalBold.copyWith(
                color: AppColors.labelNormal,
              ),
            ),
            const Spacer(),
            SvgPicture.asset(
              'assets/icons/ic_chevron_right_16.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                AppColors.labelAlternative,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    AsyncValue<Map<String, dynamic>> user,
  ) {
    // 이름을 아직 못 읽었으면 이름 없이 인사한다.
    //
    // 기본값을 '오프웨이'로 두었더니 로그인 직후 '오프웨이님'으로 인사하고
    // 곧 내 이름으로 바뀌었다 — 남의 이름으로 불리는 것처럼 보인다.
    // 이름이 오면 그때 붙인다
    final nickname = user.value?['nickname'] as String?;
    final greeting = nickname == null
        ? '어디로 떠나볼까요?'
        : '${displayName(nickname)}님, 어디로 떠나볼까요?';
    return Container(
      height: 230,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.backgroundNormalAlternative,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 카드 패딩 밖으로 나가 아래·왼쪽에 걸치는 배경 일러스트.
          // 문구·버튼보다 먼저 그려 뒤에 깔리게 한다.
          // 발밑은 카드 바닥에 잘려 들어간다 — 띄우면 붕 뜬 것처럼 보인다.
          Positioned(
            left: -7,
            bottom: -24,
            child: SvgPicture.asset(
              'assets/images/home_hero_character.svg',
              width: 228,
              excludeFromSemantics: true,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: AppTypography.heading2Bold.copyWith(
                  color: AppColors.labelNormal,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '연차에 맞춘 추천 코스를 알려드려요!',
                style: AppTypography.label2Medium.copyWith(
                  color: AppColors.labelNeutral,
                ),
              ),
            ],
          ),
          Positioned(
            // 시안 좌표 기준 버튼은 카드 오른쪽·아래에서 각각 18 (카드 패딩 24 보정)
            right: -6,
            bottom: -6,
            child: FilledButton(
              // 지난번 고르다 만 값을 비우고 처음부터
              onPressed: () => startCourseWizard(context, ref),
              style: FilledButton.styleFrom(
                // TODO(디자인시스템): 디자인이 Atomic Neutral/22를 직접 참조한다.
                // 이 검정을 가리키는 Semantic 토큰이 생기면 그걸로 교체할 것.
                backgroundColor: _heroCtaBackground,
                foregroundColor: AppColors.staticWhite,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                // 가이드 버튼 크기 123×40 — 글자 높이에 맡기면 38로 줄어든다
                minimumSize: const Size(0, 40),
                fixedSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('바로 추천받기', style: AppTypography.body2NormalBold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow() {
    return CategoryChipRow(
      // 구성·순서는 서버가 정한다. 응답 전에는 기본 구성으로 자리를 지킨다
      filters: ref.watch(homeSnapshotProvider).value?.filters,
      selected: _selected,
      onSelect: (filter) =>
          setState(() => _selected = Map<String, dynamic>.from(filter)),
      // 가이드는 칩 줄만 21에서 시작해 화면 폭에 균등 배치된다
      padding: const EdgeInsets.symmetric(horizontal: 21),
    );
  }

  /// '연차 쓰기 전, 확인해보세요' — 황금연휴 카드 하나에 서버 링크 카드들.
  ///
  /// 첫 카드는 앱 안 화면(황금연휴)이라 늘 있고, 그 뒤에 서버가 고른 외부
  /// 링크가 온다. 링크가 비어도 섹션은 남는다 — 첫 카드가 있다
  Widget _buildCuratedLinks() {
    final links =
        ref.watch(homeSnapshotProvider).value?.curatedLinks ??
        const <CuratedLink>[];

    return Padding(
      // 위 섹션(가로 카드)과 붙지 않게 같은 간격을 준다
      padding: const EdgeInsets.only(top: _sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '연차 쓰기 전, 확인해보세요',
              style: AppTypography.headline1Bold.copyWith(
                color: AppColors.labelNormal,
              ),
            ),
          ),
          // 시안 실측: 제목~카드 16, 카드 사이 18
          const SizedBox(height: 16),
          SizedBox(
            height: InfoCard.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: links.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, i) => i == 0
                  ? const GoldenHolidayCard()
                  : CuratedLinkCard(link: links[i - 1]),
            ),
          ),
        ],
      ),
    );
  }

  /// '이번 연차엔 여기 어때요?' — 위쪽 '이번달 추천 여행지'와 같은 목록을
  /// 쓰지만 카테고리 필터를 걸지 않는다. 조건 없이 지역만 훑어보는 자리다.
  ///
  /// 시안: 카드 3~7개. 서버가 그보다 많이 주면 앞에서 7개만 쓴다
  Widget _buildLeavePicks(AsyncValue<List<Map<String, dynamic>>> regions) {
    final picks = (regions.value ?? const <Map<String, dynamic>>[])
        .take(homeLeavePickMax)
        .toList();
    // 3개도 못 채우면 섹션째 감춘다 — 한두 장만 놓인 가로 목록은 비어 보인다
    if (regions.hasValue && picks.length < _minLeavePicks) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '이번 연차엔 여기 어때요?',
            style: AppTypography.headline1Bold.copyWith(
              color: AppColors.labelNormal,
            ),
          ),
        ),
        // 시안 실측: 제목~카드 16, 카드 사이 18
        const SizedBox(height: 16),
        SizedBox(
          height: LeavePickCard.height,
          // 첫 로딩에만 스켈레톤. 당겨서 다시 읽는 동안은 이전 카드가 남아
          // 있어(hasValue) 그대로 보여준다 — 스켈레톤으로 바꾸면 깜빡인다
          child: regions.isLoading && !regions.hasValue
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _skeletonCardCount,
                  separatorBuilder: (_, _) => const SizedBox(width: 18),
                  itemBuilder: (_, _) => const LeavePickCardSkeleton(),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: picks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 18),
                  itemBuilder: (context, i) => LeavePickCard(region: picks[i]),
                ),
        ),
      ],
    );
  }

  /// '이번달 추천 여행지' — 장소 카드를 그린다.
  ///
  /// [fallback]은 장소 배치가 아직 안 돈 동안 쓰는 지역 카드다. 시안은 장소를
  /// 원하지만 빈 섹션보다는 낫고, 서버가 채우는 대로 저절로 갈아탄다
  Widget _buildRegionCards(
    AsyncValue<List<Map<String, dynamic>>> regions, {
    AsyncValue<List<Map<String, dynamic>>>? fallback,
  }) {
    // 로딩·에러·빈 상태는 자리만 잡아두면 되므로 높이를 고정한다.
    // 카드가 들어오면 높이를 카드에 맡긴다 — 고정하면 카드 내용보다 커져
    // 뱃지 아래에 빈 영역이 남고 다음 섹션이 그만큼 밀려 내려간다
    final placeholderHeight = RegionCard.boxedHeightFor(context);

    return regions.when(
      // 스피너 대신 카드가 들어올 자리를 미리 잡아둔다 (O-03 스켈레톤)
      loading: () => SizedBox(
        height: placeholderHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _skeletonCardCount,
          separatorBuilder: (_, _) => const SizedBox(width: 20),
          itemBuilder: (_, _) => const RegionCardSkeleton(),
        ),
      ),
      // 서버 detail이 사용자 문구라 그대로 보여준다. 그 외에는 원인을 감춘다
      error: (e, _) => SizedBox(
        height: placeholderHeight,
        child: Center(
          child: Text(
            e is ApiException ? e.detail : '추천 여행지를 불러오지 못했어요',
            textAlign: TextAlign.center,
            style: AppTypography.label1NormalMedium.copyWith(
              color: AppColors.labelAlternative,
            ),
          ),
        ),
      ),
      data: (served) {
        // 장소 배치(core #305)가 아직 안 돈 지역이 있다. 그럴 때 빈 칸을
        // 두느니 예전처럼 지역 카드를 보여준다 — 배치가 채우면 저절로 바뀐다
        final usingPlaces = served.isNotEmpty;
        final shown = usingPlaces
            ? homePlacesForChip(served, _selected)
            : _filter(fallback?.value ?? served);
        // 한 지역의 혜택 전부 — 서버는 대표 하나만 주므로 앱이 모은 색인을
        // 붙인다. 색인이 아직 없으면(첫 로딩·실패) 대표 하나 그대로다
        final index = ref.watch(regionPoliciesProvider).value;
        final list = index == null
            ? shown
            : [
                for (final card in shown)
                  {...card, 'benefits': benefitsForCard(card, index)},
              ];
        if (list.isEmpty) {
          return SizedBox(
            height: placeholderHeight,
            child: Center(
              child: Text(
                '해당 카테고리의 여행지가 아직 없어요',
                style: AppTypography.label1NormalMedium.copyWith(
                  color: AppColors.labelAlternative,
                ),
              ),
            ),
          );
        }
        // **사진은 화면 근처의 카드만 받는다.** 카드는 전부 만들어야
        // 줄 높이가 가장 긴 카드에 맞춰진다(아래 Row) — 그래서 카드는 그대로
        // 두고 사진만 미룬다. 예전에는 50여 장을 한꺼번에 받아 보이는 사진이
        // 대역폭을 나눠 쓰느라 늦게 떴다
        final listKey = (_selected?['key'], _shuffleSeed, list.length);
        if (listKey != _placesListKey) {
          _placesListKey = listKey;
          _placesLoadUntil = 0;
          _placesReleased = false;
          _releasePlacesAfter(listKey, [
            for (final card in list.take(_placesVisibleUntil()))
              if (card['imageUrl'] case final String url when url.isNotEmpty)
                url,
          ]);
        }
        _placesLoadUntil = _placesReleased
            ? list.length
            : math.max(_placesLoadUntil, _placesVisibleUntil());
        // Row로 감싸 카드가 스스로 높이를 정하게 한다. 가로 ListView는
        // 부모가 높이를 정해줘야 해서 여유분이 빈 영역으로 남는다
        return SingleChildScrollView(
          controller: _placesScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                RegionCard(region: list[i], loadImage: i < _placesLoadUntil),
              ],
            ],
          ),
        );
      },
    );
  }
}
