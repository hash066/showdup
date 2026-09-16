import 'package:flutter/widgets.dart';

import '../models/enums.dart';

/// Stable widget keys for tests. Copy and layout can change freely during the
/// redesign; tests find widgets by these keys instead of visible text.
class ShowdKeys {
  ShowdKeys._();

  static const previewEntry = ValueKey('welcome.preview');
  static const previewBanner = ValueKey('shell.previewBanner');

  static const navAlarms = ValueKey('nav.alarms');
  static const navCommitments = ValueKey('nav.commitments');
  static const navHistory = ValueKey('nav.history');
  static const navBattle = ValueKey('nav.battle');
  static const navSettings = ValueKey('nav.settings');

  static const createFirstCommitment = ValueKey('today.createFirst');

  static const endToday = ValueKey('attempt.endToday');
  static ValueKey<String> attemptOutcome(AttemptState state) =>
      ValueKey('attempt.outcome.${state.wire}');

  static ValueKey<String> wizardStep(int page) => ValueKey('wizard.step.$page');
  static ValueKey<String> wizardPreset(CommitmentKind kind) =>
      ValueKey('wizard.preset.${kind.wire}');
  static const wizardNext = ValueKey('wizard.next');
}
