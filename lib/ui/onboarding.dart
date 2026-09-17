import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/buttons.dart';
import '../design/chrome.dart';
import '../design/layout.dart';
import '../design/mark.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'keys.dart';
import 'screens/common.dart';

/// First run: the bell flips into a person, then the research, then setup.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.onPreview,
    required this.onAuthenticated,
    this.error,
  });

  final VoidCallback onPreview;
  final Future<void> Function() onAuthenticated;
  final String? error;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool showedUp = false;
  bool research = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => showedUp = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (research) {
      return WhyThisWorksScreen(
        continueLabel: 'Set my first alarm',
        onBack: () => setState(() => research = false),
        onContinue: widget.onAuthenticated,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: ShowdSpace.gutter),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: ShowdSpace.s4),
                    const Wordmark(size: 24),
                    const Spacer(),
                    const SizedBox(height: ShowdSpace.s8),
                    FlippingMark(showedUp: showedUp, size: 132),
                    const SizedBox(height: ShowdSpace.s8),
                    Text(
                      'An alarm you have to show up for.',
                      style: ShowdType.hero,
                    ),
                    const SizedBox(height: ShowdSpace.s3),
                    Text(
                      'It keeps ringing until your phone sees proof: a walk, the gym, an hour with the phone down.',
                      style: ShowdType.bodyL.copyWith(color: ShowdColors.stone),
                    ),
                    const Spacer(),
                    const SizedBox(height: ShowdSpace.s8),
                    if (widget.error != null) ShowdNotice(widget.error!),
                    ShowdButton(
                      label: 'Set my first alarm',
                      onPressed: () => setState(() => research = true),
                    ),
                    const SizedBox(height: ShowdSpace.s2),
                    ShowdButton(
                      key: ShowdKeys.previewEntry,
                      label: 'Look around first',
                      tone: ShowdButtonTone.quiet,
                      onPressed: widget.onPreview,
                    ),
                    const SizedBox(height: ShowdSpace.s4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three published findings, phrased as study results with their sources.
class WhyThisWorksScreen extends StatefulWidget {
  const WhyThisWorksScreen({
    super.key,
    required this.onContinue,
    this.onBack,
    this.continueLabel = 'Got it',
  });

  final Future<void> Function() onContinue;
  final VoidCallback? onBack;
  final String continueLabel;

  @override
  State<WhyThisWorksScreen> createState() => _WhyThisWorksScreenState();
}

class _WhyThisWorksScreenState extends State<WhyThisWorksScreen> {
  bool busy = false;

  static const findings = [
    (
      '57%',
      'A short pause before opening distracting apps cut how often people opened them by 57% over six weeks.',
      'Grüning et al., PNAS, 2023',
      'https://www.pnas.org/doi/10.1073/pnas.2213114120',
    ),
    (
      '51%',
      'People who could only listen to their favourite audiobooks at the gym went 51% more often at first.',
      'Milkman, Minson & Volpp, Management Science, 2014',
      'https://pubsonline.informs.org/doi/10.1287/mnsc.2013.1784',
    ),
    (
      '91%',
      'Of people who planned when and where they would exercise, 91% exercised at least once a week.',
      'Milne, Orbell & Sheeran, British Journal of Health Psychology, 2002',
      'https://bpspsychub.onlinelibrary.wiley.com/doi/abs/10.1348/135910702169420',
    ),
  ];

  Future<void> _continue() async {
    setState(() => busy = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          PushedHeader(
            onBack: widget.onBack,
            trailing: TextButton(
              onPressed: busy ? null : _continue,
              child: const Text('Skip'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                ShowdSpace.gutter,
                ShowdSpace.s2,
                ShowdSpace.gutter,
                ShowdSpace.s6,
              ),
              children: [
                Text('Why this works.', style: ShowdType.titleXL),
                const SizedBox(height: ShowdSpace.s2),
                Text(
                  'Three findings from published studies. ShowdUp is built on them.',
                  style: ShowdType.bodyM,
                ),
                for (final (number, line, source, url) in findings) ...[
                  const SizedBox(height: ShowdSpace.s8),
                  BigNumber(
                    number,
                    style: ShowdType.numeralL,
                    color: ShowdColors.accent,
                  ),
                  Text(line, style: ShowdType.bodyL),
                  const SizedBox(height: ShowdSpace.s1),
                  InkWell(
                    onTap: () async {
                      final opened = await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        showMessage(context, 'Couldn’t open the study.');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        source,
                        style: ShowdType.caption.copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: ShowdColors.graphiteStrong,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShowdSpace.gutter,
              0,
              ShowdSpace.gutter,
              ShowdSpace.s4,
            ),
            child: ShowdButton(
              label: widget.continueLabel,
              busy: busy,
              onPressed: _continue,
            ),
          ),
        ],
      ),
    ),
  );
}
