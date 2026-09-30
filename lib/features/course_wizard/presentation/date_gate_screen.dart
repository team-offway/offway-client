import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/tokens.dart';
import '../../../core/widgets/app_back_button.dart';
import '../application/course_wizard_provider.dart';
import 'widgets/wizard_choice_step.dart';
import 'widgets/wizard_option_button.dart';

/// O-04-0 · 날짜 갈림길 (STEP 2/5)
/// "가고싶은 날짜가 있어요" → 캘린더 / "아직 안 정했어요" → 기간스타일
class DateGateScreen extends ConsumerWidget {
  const DateGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(
      courseWizardProvider.select((draft) => draft.datePath),
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundNormal,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            const SizedBox(height: kWizardTopGap),
            SvgPicture.asset(
              'assets/icons/ic_calendar_blue.svg',
              width: 48,
              height: 48,
            ),
            // 시안 측정값 — 아이콘과 질문 사이 20
            const SizedBox(height: 20),
            Text(
              '여행 날짜가 있나요?',
              textAlign: TextAlign.center,
              style: AppTypography.title3Bold.copyWith(
                color: AppColors.labelNormal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '날짜를 직접 선택하거나,\n추천부터 받아볼 수 있어요.',
              textAlign: TextAlign.center,
              style: AppTypography.body1NormalMedium.copyWith(
                color: AppColors.labelAlternative,
              ),
            ),
            // 시안 측정값 — 부제와 첫 카드 사이 48
            const SizedBox(height: 48),
            WizardOptionButton(
              label: '가고싶은 날짜가 있어요',
              selected: choice == DatePathChoice.haveDates,
              onTap: () => ref
                  .read(courseWizardProvider.notifier)
                  .selectDatePath(DatePathChoice.haveDates),
            ),
            const SizedBox(height: 16),
            WizardOptionButton(
              label: '아직 안 정했어요',
              selected: choice == DatePathChoice.undecided,
              onTap: () => ref
                  .read(courseWizardProvider.notifier)
                  .selectDatePath(DatePathChoice.undecided),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: choice == null
                      ? null
                      : () {
                          if (choice == DatePathChoice.haveDates) {
                            context.push(AppRoutes.wizardCalendar);
                          } else {
                            context.push(AppRoutes.wizardPeriodStyle);
                          }
                        },
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      // 버튼이 아이콘보다 넓으므로 좌측 여백을 줄여 아이콘 위치를 맞춘다 —
      // 위저드의 다른 단계와 같은 자리에 선다
      padding: const EdgeInsets.fromLTRB(6, 0, 16, 0),
      child: Row(
        children: [
          AppBackButton(
            // 위젯에서 바로 들어오면 스택이 비어 있다
            onTap: () =>
                context.canPop() ? context.pop() : context.go(AppRoutes.home),
          ),
          const Spacer(),
          Text(
            '2/5',
            // 시안: Body 1 Bold + Label/Assistive (하드코딩 색을 쓰고 있었다)
            style: AppTypography.body1NormalBold.copyWith(
              color: AppColors.labelAssistive,
            ),
          ),
        ],
      ),
    );
  }
}
