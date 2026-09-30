import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../application/course_wizard_provider.dart';
import 'widgets/wizard_choice_step.dart';

/// O-05 · 이동수단 (STEP 4/5)
class TransportScreen extends ConsumerWidget {
  const TransportScreen({super.key});

  static const _modes = [TransportMode.publicTransit, TransportMode.car];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      courseWizardProvider.select((draft) => draft.transportMode),
    );

    return WizardChoiceStep(
      stepLabel: '4/5',
      iconAsset: 'assets/icons/ic_car.svg',
      title: '어떻게 이동하세요?',
      subtitle: '이동수단을 선택해주세요.',
      options: const ['대중교통', '자차'],
      selectedIndex: mode == null ? null : _modes.indexOf(mode),
      onSelect: (i) =>
          ref.read(courseWizardProvider.notifier).selectTransport(_modes[i]),
      onNext: mode == null ? null : () => context.push(AppRoutes.wizardDensity),
    );
  }
}
