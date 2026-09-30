import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/trip_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/tokens.dart';
import '../../../core/utils/leave_format.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_inline_notice.dart';
import '../../../core/widgets/app_back_button.dart';
import '../application/course_wizard_provider.dart';
import '../domain/weekday_range.dart';
import 'widgets/wizard_choice_step.dart';
import '../../home/application/home_providers.dart';
import '../../../core/utils/date_format.dart';

/// O-04 · 기간스타일 (B 경로, STEP 3/5)
/// 주말 포함/연차만 선택 시 바텀시트로 하위 선택을 받는다.
class PeriodStyleScreen extends ConsumerWidget {
  const PeriodStyleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(courseWizardProvider);
    final leaveDays = ref.watch(homeUserProvider).value?['remainingLeaveDays'];

    return Scaffold(
      backgroundColor: AppColors.backgroundNormal,
      body: SafeArea(
        // 액션 영역은 스크롤 밖에 두어 화면이 작아도 항상 닿는다.
        // 안에 넣으면 콘텐츠에 밀려 화면 밖으로 나가버린다.
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildTopBar(context),
                    const SizedBox(height: kWizardTopGap),
                    SvgPicture.asset(
                      'assets/icons/ic_plane.svg',
                      width: 48,
                      height: 48,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '어떻게 떠날까요?',
                      textAlign: TextAlign.center,
                      style: AppTypography.title3Bold.copyWith(
                        color: AppColors.labelNormal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '여행 스타일에 맞는 코스를\n찾아드려요.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body1NormalMedium.copyWith(
                        color: AppColors.labelAlternative,
                      ),
                    ),
                    const SizedBox(height: 37),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _StyleCard(
                            iconAsset: 'assets/icons/ic_timer_bold.svg',
                            title: '당일치기 · 연차',
                            subtitle: '짧게 다녀와요',
                            selected: draft.periodStyle == PeriodStyle.dayTrip,
                            onTap: () => ref
                                .read(courseWizardProvider.notifier)
                                .selectPeriodStyle(PeriodStyle.dayTrip),
                          ),
                          const SizedBox(height: 12),
                          _StyleCard(
                            iconAsset: 'assets/icons/ic_clock.svg',
                            title: '주말 포함 여행',
                            subtitle: '주말을 이어 떠나요',
                            selected:
                                draft.periodStyle == PeriodStyle.weekendCombo,
                            onTap: () {
                              ref
                                  .read(courseWizardProvider.notifier)
                                  .selectPeriodStyle(PeriodStyle.weekendCombo);
                              _showWeekendDaysSheet(context, ref);
                            },
                          ),
                          const SizedBox(height: 12),
                          _StyleCard(
                            iconAsset: 'assets/icons/ic_coffee.svg',
                            title: '연차만 (주말 미포함)',
                            subtitle: '평일에 여유를 즐겨요',
                            selected:
                                draft.periodStyle == PeriodStyle.leaveOnly,
                            onTap: () {
                              ref
                                  .read(courseWizardProvider.notifier)
                                  .selectPeriodStyle(PeriodStyle.leaveOnly);
                              _showLeaveStepperSheet(context, ref);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Text(
                    '남은 연차일수 ${leaveDays is num ? formatLeaveDays(leaveDays) : '-'}일',
                    style: AppTypography.label1ReadingMedium.copyWith(
                      color: AppColors.labelAlternative,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: draft.isPeriodStyleComplete
                          ? () => context.push(AppRoutes.wizardTransport)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryNormal,
                        disabledBackgroundColor: AppColors.interactionDisable,
                        foregroundColor: AppColors.staticWhite,
                        disabledForegroundColor: AppColors.labelAssistive,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('다음', style: AppTypography.body1NormalBold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 뒤로가기 + 단계 표시. 단계는 오른쪽에 옅게 둔다.
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      // 버튼이 아이콘보다 넓으므로 좌측 여백을 줄여 아이콘 위치를 맞춘다
      padding: const EdgeInsets.fromLTRB(6, 0, 16, 0),
      child: Row(
        children: [
          AppBackButton(onTap: () => context.pop()),
          const Spacer(),
          Text(
            '3/5',
            style: AppTypography.body1NormalBold.copyWith(
              color: AppColors.labelAssistive,
            ),
          ),
        ],
      ),
    );
  }

  /// 모달: 언제 떠날까요? (주말 포함 — 이어지는 요일 범위를 고른다)
  ///
  /// 예전에는 금·토·일 / 토·일·월 두 조합만 골랐다. 시안이 월~일에서 범위를
  /// 직접 고르게 바뀌었다 — 사용자는 "조합"보다 "목·금·토"로 생각한다.
  void _showWeekendDaysSheet(BuildContext context, WidgetRef ref) {
    showAppBottomSheet<void>(
      context,
      builder: (sheetContext) {
        var range = const WeekdayRange.empty();

        return StatefulBuilder(
          builder: (context, setSheetState) => _SheetScaffold(
            title: '언제 떠날까요?',
            subtitle: '주말을 포함한 최대 ${WeekdayRange.maxDays}일까지 선택할 수 있어요',
            confirmEnabled: range.canConfirm,
            onConfirm: () {
              ref
                  .read(courseWizardProvider.notifier)
                  .selectWeekendDays(
                    WeekendDays(startWeekday: range.start!, days: range.days),
                  );
              Navigator.of(sheetContext).pop();
            },
            footer: Padding(
              // 시안: 안내문 위 24, 완료 버튼과 16
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
              child: Text(
                // 왜 완료가 잠겼는지 알려준다. 주말이 빠진 경우가 가장 헷갈린다
                // — 목·금처럼 이어 골랐는데도 버튼이 흐린 이유가 안 보인다.
                //
                // **조건을 채우면 비운다.** 다 골랐는데 '연속된 요일만' 이 남아
                // 있으면 아직 뭘 더 해야 하는 줄 안다. 빈 문자열도 한 줄
                // 높이를 차지하므로 완료 버튼이 위로 튀지 않는다
                range.canConfirm
                    ? ''
                    : range.days >= WeekdayRange.minDays &&
                          !range.includesWeekend
                    ? '토요일이나 일요일이 하루는 포함돼야 해요'
                    : '연속된 요일만 선택 가능해요',
                textAlign: TextAlign.center,
                style: AppTypography.label2Regular.copyWith(
                  color: AppColors.labelNeutral,
                ),
              ),
            ),
            // 시안 간격(13.2)은 402pt 기준이라 iPhone 12(390pt)에서 6.4 넘친다.
            // 칩은 탭 대상이라 크기를 지키고, 좁은 화면에서는 간격만 좁힌다
            child: LayoutBuilder(
              builder: (context, constraints) {
                const chipCount = 7;
                final free =
                    constraints.maxWidth - _WeekdayChip.size * chipCount;
                final gap = (free / (chipCount - 1)).clamp(
                  0.0,
                  _weekdayChipGap,
                );
                final step = _WeekdayChip.size + gap;
                final rowWidth =
                    _WeekdayChip.size * chipCount + gap * (chipCount - 1);
                // 칩 한 줄의 실제 시작 x — 가운데 정렬된 만큼 왼쪽 여백이 생긴다
                final rowLeft = (constraints.maxWidth - rowWidth) / 2;

                return SizedBox(
                  height: _WeekdayChip.size,
                  child: Stack(
                    children: [
                      // 고른 범위를 하나로 이어 보이게 칩 사이까지 옅게 깐다.
                      // 칩만 칠하면 3일을 골라도 따로 떨어진 날처럼 읽힌다.
                      //
                      // 주를 넘어가면(일·월·화) 한 줄에서는 양 끝으로 갈라지므로
                      // 조각을 나눠 그린다 — 한 덩어리로 그리면 줄 밖으로 삐져
                      // 나가고 월·화 위에는 깔리지 않는다
                      for (final piece in _rangePieces(range))
                        Positioned(
                          left: rowLeft + (piece.from - 1) * step,
                          width: _WeekdayChip.size + (piece.length - 1) * step,
                          top: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppPalette.lightBlue70.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(
                                _WeekdayChip.radius,
                              ),
                            ),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (
                            var day = DateTime.monday;
                            day <= DateTime.sunday;
                            day++
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                left: day == DateTime.monday ? 0 : gap,
                              ),
                              child: _WeekdayChip(
                                weekday: day,
                                selected: range.contains(day),
                                enabled: range.canSelect(day),
                                onTap: () => setSheetState(
                                  () => range = range.toggle(day),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 모달: 평일 연차, 며칠 쓸까요? (2일·3일 중 선택)
  void _showLeaveStepperSheet(BuildContext context, WidgetRef ref) {
    showAppBottomSheet<void>(
      context,
      builder: (sheetContext) {
        // 정책: 연차만은 최소 2일 ~ 최대 3일 (연차소모 = 총 여행일수)
        // 상한은 잔여 연차일수를 넘지 않는다
        const minDays = 2;
        // 서버가 double로 주고 반차(0.5)가 섞일 수 있다 — 온전한 하루만 센다
        final remaining =
            (ref.read(homeUserProvider).value?['remainingLeaveDays'] as num?)
                ?.floor() ??
            kMaxTripSpanDays + 1;
        final maxDays = remaining.clamp(minDays, kMaxTripSpanDays + 1);
        // 잔여 연차가 2일뿐이면 3일 버튼은 고를 수 없다
        final choices = [
          for (var d = minDays; d <= kMaxTripSpanDays + 1; d++)
            (days: d, enabled: d <= maxDays),
        ];
        // 처음에는 아무것도 고르지 않은 상태로 연다 — 시안의 '완료'가 흐린 이유다
        int? selected = ref.read(courseWizardProvider).leaveDaysToUse;
        if (selected != null && selected > maxDays) selected = null;

        return StatefulBuilder(
          builder: (context, setSheetState) => _SheetScaffold(
            title: '평일 연차, 며칠 쓸까요?',
            confirmEnabled: selected != null,
            onConfirm: () {
              ref
                  .read(courseWizardProvider.notifier)
                  .selectLeaveDays(selected!);
              Navigator.of(sheetContext).pop();
            },
            // 시안: 상한 안내는 늘 보인다 — 버튼만 봐서는 3일이 끝인지 알 수 없다
            footer: AppInlineNotice(
              // 아이콘 원본이 이미 label/assistive와 같은 색이라 그대로 쓴다
              iconAsset: 'assets/icons/ic_circle_exclamation.svg',
              message:
                  '최대 ${kMaxTripSpanDays + 1}일($kMaxTripSpanDays박${kMaxTripSpanDays + 1}일)까지 선택할 수 있어요',
              color: AppColors.labelAssistive,
              minHeight: 44,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in choices) ...[
                  if (c != choices.first) const SizedBox(width: 16),
                  _LeaveDaysButton(
                    days: c.days,
                    selected: selected == c.days,
                    enabled: c.enabled,
                    onTap: () => setSheetState(() => selected = c.days),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 연차 일수 선택 버튼 — '2일 / 1박2일' 처럼 일수와 숙박을 함께 보여준다.
///
/// 잔여 연차가 모자라 고를 수 없는 날은 흐리게 두고 탭을 막는다.
class _LeaveDaysButton extends StatelessWidget {
  const _LeaveDaysButton({
    required this.days,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int days;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 선택 표시는 같은 화면의 기간 카드와 같은 규칙을 쓴다 —
    // 채움을 걷어내고 테두리로 표시한다
    final foreground = switch ((enabled, selected)) {
      (false, _) => AppColors.labelDisable,
      (true, true) => AppColors.primaryNormal,
      (true, false) => AppColors.labelNormal,
    };

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 140,
        // 고정 높이 대신 최소 높이 — 글자 배율을 키워도 넘치지 않는다
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: selected && enabled ? null : AppColors.fillNormal,
          borderRadius: BorderRadius.circular(14),
          border: selected && enabled
              ? Border.all(color: AppColors.primaryNormal)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$days일',
              style: AppTypography.headline2Bold.copyWith(color: foreground),
            ),
            const SizedBox(height: 4),
            Text(
              '${days - 1}박$days일',
              style: AppTypography.caption1Medium.copyWith(
                color: enabled
                    ? AppColors.labelAlternative
                    : AppColors.labelDisable,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 바텀시트 공통 레이아웃 (타이틀 + 내용 + 완료 버튼)
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.child,
    required this.confirmEnabled,
    required this.onConfirm,
    this.subtitle,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool confirmEnabled;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 31, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.heading2Bold.copyWith(
                color: AppColors.labelNormal,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.body2ReadingMedium.copyWith(
                  color: AppColors.labelAlternative,
                ),
              ),
            ],
            const SizedBox(height: 20),
            child,
            // 경고 영역(높이 44)이 있으면 그 자체가 여백이 되므로 덧대지 않는다
            footer ?? const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: confirmEnabled ? onConfirm : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryNormal,
                  disabledBackgroundColor: AppColors.interactionDisable,
                  foregroundColor: AppColors.staticWhite,
                  disabledForegroundColor: AppColors.labelAssistive,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('완료', style: AppTypography.body1NormalBold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 기간 스타일 선택지 카드.
///
/// 고르면 배경 대신 Primary 테두리를 두르고 글자·아이콘까지 Primary로 바뀐다.
class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AppColors.primaryNormal
        : AppColors.labelNormal;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 고정 높이 대신 최소 높이 — 글자 배율을 키워도 넘치지 않는다
        constraints: const BoxConstraints(minHeight: 78),
        // 시안 카드 폭 258 — 화면 가득 늘리면 날짜갈림길 카드와 어긋난다
        width: 258,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          // 선택되면 채움을 걷어내고 테두리로만 표시한다
          color: selected ? null : AppColors.fillNormal,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: AppColors.primaryNormal) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.backgroundNormal,
                borderRadius: BorderRadius.circular(15.556),
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                iconAsset,
                width: 24,
                height: 24,
                // 아이콘마다 원본 색이 달라(타이머는 선택 상태로 뽑혀 있다) 여기서 통일한다.
                // 미선택 색은 반투명 토큰이 아니라 불투명한 같은 색조를 쓴다 —
                // 시계·커피는 SVG 안에 이미 61% 레이어가 있어 반투명끼리 곱해지면
                // 형체가 흐려진다.
                colorFilter: ColorFilter.mode(
                  selected ? AppColors.primaryNormal : AppPalette.coolNeutral25,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.headline2Bold.copyWith(
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.caption1Medium.copyWith(
                      color: selected
                          ? AppColors.primaryNormal
                          : AppColors.labelAlternative,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 요일 한 줄에 띠를 그릴 조각 — `from`(1=월) 에서 `length`칸
typedef _RangePiece = ({int from, int length});

/// 고른 범위를 한 줄에 그릴 조각으로 나눈다.
///
/// 주를 넘어가지 않으면 한 조각이다. 넘어가면(일·월·화) 줄에서 양 끝으로
/// 갈라지므로 두 조각이 된다 — 일요일까지, 그리고 월요일부터.
///
/// 하루만 고른 상태는 빈 목록이다. 칩 하나에 띠를 겹치면 테두리만 번져 보인다.
List<_RangePiece> _rangePieces(WeekdayRange range) {
  final start = range.start;
  if (start == null || range.days < 2) return const [];
  final overflow = start + range.days - 1 - DateTime.sunday;
  if (overflow <= 0) return [(from: start, length: range.days)];
  return [
    (from: start, length: DateTime.sunday - start + 1),
    (from: DateTime.monday, length: overflow),
  ];
}

/// 요일 칩 사이 간격 — 시안 실측. 화면이 좁으면 이 값보다 좁아진다
const _weekdayChipGap = 13.2;

/// 요일 칩 — 시안 실측 39.6×39.6, 반경 15.4.
///
/// 고를 수 없는 요일은 지우지 않고 흐리게 남긴다. 사라지면 한 줄이 흔들려
/// 어느 요일을 보고 있었는지 잃는다.
class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.weekday,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int weekday;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// 시안 실측 — 좁은 화면에서 간격을 계산할 때 쓴다
  static const size = 39.6;
  static const radius = 15.4;
  static const _fontSize = 18.7;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected
            ? AppPalette.lightBlue70
            : AppColors.backgroundNormalAlternative,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        weekdayLabelOf(weekday),
        style: TextStyle(
          fontSize: _fontSize,
          fontWeight: FontWeight.w600,
          height: 1.412,
          color: selected ? AppPalette.offway99 : AppColors.labelAlternative,
        ),
      ),
    );

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      // 시안: 못 고르는 요일은 30%로 흐리다
      child: enabled ? chip : Opacity(opacity: 0.3, child: chip),
    );
  }
}
