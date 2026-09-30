import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../application/course_wizard_provider.dart';
import '../application/wizard_recommend_provider.dart';
import 'widgets/wizard_choice_step.dart';

/// O-06 · 일정 밀도 (STEP 5/5)
class DensityScreen extends ConsumerWidget {
  const DensityScreen({super.key});

  static const _densities = [ScheduleDensity.packed, ScheduleDensity.relaxed];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = ref.watch(
      courseWizardProvider.select((draft) => draft.scheduleDensity),
    );
    // **후보 추천을 여기서 미리 띄운다**(#391). 추천에 필요한 값(날짜·기간·
    // 이동수단·출발지)은 이 화면에 오기 전에 다 정해졌고, 밀도는 추천에 쓰이지
    // 않는다. 사용자가 밀도를 고르는 사이 가용시간 → 추천 두 왕복이 끝나
    // 후보 화면의 로딩이 짧아진다. 이 화면은 후보 화면 아래 스택에 남아
    // 있어 받아 둔 값이 버려지지 않는다
    ref.listen(wizardRecommendProvider, (_, _) {});

    return WizardChoiceStep(
      stepLabel: '5/5',
      iconAsset: 'assets/icons/ic_route.svg',
      title: '내가 선호하는 여행 스타일은?',
      subtitle: '원하는 스타일을 반영할게요.',
      options: const ['빼곡한 일정', '널널한 일정'],
      selectedIndex: density == null ? null : _densities.indexOf(density),
      onSelect: (i) =>
          ref.read(courseWizardProvider.notifier).selectDensity(_densities[i]),
      onNext: density == null
          ? null
          // 후보지역 화면이 로딩(O-07 디자인)을 직접 보여준다 — 검색이 실제로
          // 끝나는 순간 결과로 바뀌므로 로딩이 두 번 이어지지 않는다
          : () => context.push(AppRoutes.wizardCandidates),
    );
  }
}
