import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/buttons.dart';
import '../design/icons.dart';
import '../design/layout.dart';
import '../design/mark.dart';
import '../design/motion.dart';
import '../design/sensory.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'keys.dart';
import 'screens/common.dart';

/// First run. The logo tells the story before any words do: the bell rings,
/// flips into a person, and the name arrives. Then four swipeable pages, one
/// idea each, then setup.
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

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  bool story = false;
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_played) return;
    _played = true;
    if (Motion.reduced(context)) {
      _intro.value = 1;
      return;
    }
    Sensory.play(Cue.intro);
    _intro
      ..addListener(_landCue)
      ..forward();
  }

  var _landed = false;
  void _landCue() {
    if (!_landed && _intro.value > 0.49) {
      _landed = true;
      Sensory.play(Cue.land, sound: false);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (story) {
      return StoryScreen(
        onBack: () => setState(() => story = false),
        onDone: widget.onAuthenticated,
      );
    }
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_intro.isAnimating) _intro.value = 1;
        },
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _intro,
            builder: (context, _) {
              final t = _intro.value * 2800;
              double span(double from, double to) =>
                  ((t - from) / (to - from)).clamp(0.0, 1.0);
              final appear = Curves.easeOutBack.transform(span(0, 420));
              final rock = t < 1000
                  ? math.sin(span(250, 1000) * math.pi * 7) *
                        0.26 *
                        (1 - span(250, 1000))
                  : 0.0;
              final flip = Curves.easeOutBack.transform(span(1000, 1450));
              final lift = Curves.easeInOutCubic.transform(span(1500, 1950));
              final name = span(1650, 2200);
              final words = span(2050, 2700);
              final actions = span(2350, 2800);
              return LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment(0, -0.18 - lift * 0.3),
                        child: Transform.rotate(
                          angle: rock,
                          alignment: const Alignment(0, 0.06),
                          child: Transform.scale(
                            scale: (0.4 + appear * 0.6) * (1 - lift * 0.22),
                            child: Opacity(
                              opacity: span(0, 200),
                              child: SizedBox.square(
                                dimension: 150,
                                child: CustomPaint(
                                  painter: MarkPainter(
                                    state: MarkState.ringing,
                                    turn: 1 - flip,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (t >= 1150)
                      const Positioned.fill(
                        child: Align(
                          alignment: Alignment(0, -0.18),
                          child: DotBurst(
                            play: true,
                            color: ShowdColors.accent,
                            size: 300,
                          ),
                        ),
                      ),
                    Positioned(
                      left: ShowdSpace.gutter,
                      right: ShowdSpace.gutter,
                      top: box.maxHeight * 0.44,
                      child: Column(
                        children: [
                          _LetterReveal(
                            text: 'ShowdUp',
                            progress: name,
                            style: ShowdType.hero.copyWith(fontSize: 52),
                          ),
                          const SizedBox(height: ShowdSpace.s3),
                          _WordReveal(
                            text: 'An alarm you have to show up for.',
                            progress: words,
                            style: ShowdType.bodyL.copyWith(
                              color: ShowdColors.stone,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: ShowdSpace.gutter,
                      right: ShowdSpace.gutter,
                      bottom: ShowdSpace.s4,
                      child: Opacity(
                        opacity: actions,
                        child: Transform.translate(
                          offset: Offset(0, 24 * (1 - actions)),
                          child: Column(
                            children: [
                              if (widget.error != null)
                                ShowdNotice(widget.error!),
                              ShowdButton(
                                label: 'Get started',
                                onPressed: actions < 1
                                    ? null
                                    : () => setState(() => story = true),
                              ),
                              const SizedBox(height: ShowdSpace.s2),
                              ShowdButton(
                                key: ShowdKeys.previewEntry,
                                label: 'Look around first',
                                tone: ShowdButtonTone.quiet,
                                onPressed: actions < 1
                                    ? null
                                    : widget.onPreview,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LetterReveal extends StatelessWidget {
  const _LetterReveal({
    required this.text,
    required this.progress,
    required this.style,
  });

  final String text;
  final double progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final letters = text.characters.toList();
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (i, letter) in letters.indexed)
            Builder(
              builder: (context) {
                final local = ((progress * (letters.length + 2) - i) / 3).clamp(
                  0.0,
                  1.0,
                );
                final eased = Curves.easeOutCubic.transform(local);
                return Opacity(
                  opacity: eased,
                  child: Transform.translate(
                    offset: Offset(0, 22 * (1 - eased)),
                    child: Text(letter, style: style),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _WordReveal extends StatelessWidget {
  const _WordReveal({
    required this.text,
    required this.progress,
    required this.style,
  });

  final String text;
  final double progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final words = text.split(' ');
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final (i, word) in words.indexed)
            Opacity(
              opacity: ((progress * (words.length + 1) - i)).clamp(0.0, 1.0),
              child: Text('$word ', style: style),
            ),
        ],
      ),
    );
  }
}

/// Four pages, one idea each, told mostly by animation.
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key, required this.onDone, this.onBack});

  final Future<void> Function() onDone;
  final VoidCallback? onBack;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  final _pages = PageController();
  var index = 0;
  var busy = false;

  static const _count = 4;

  Future<void> _finish() async {
    setState(() => busy = true);
    try {
      await widget.onDone();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _next() {
    if (index == _count - 1) {
      _finish();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          PushedHeader(
            onBack: index == 0
                ? widget.onBack
                : () => _pages.previousPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                  ),
            trailing: TextButton(
              onPressed: busy ? null : _finish,
              child: const Text('Skip'),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (value) {
                Sensory.play(Cue.page);
                setState(() => index = value);
              },
              children: [
                _RingPage(active: index == 0),
                _ProvePage(active: index == 1),
                _ReleasePage(active: index == 2),
                _ResearchPage(active: index == 3),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShowdSpace.gutter,
              ShowdSpace.s2,
              ShowdSpace.gutter,
              ShowdSpace.s4,
            ),
            child: Column(
              children: [
                MarkDots(count: _count, index: index),
                const SizedBox(height: ShowdSpace.s4),
                ShowdButton(
                  label: index == _count - 1 ? 'Set my first alarm' : 'Next',
                  busy: busy,
                  cue: index == _count - 1 ? Cue.toggleOn : Cue.tap,
                  onPressed: _next,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// One story page: a big moving picture, a few words under it.
class _Page extends StatelessWidget {
  const _Page({required this.art, required this.title, required this.line});
  final Widget art;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ShowdSpace.gutter),
    child: Column(
      children: [
        Expanded(child: Center(child: art)),
        Text(title, textAlign: TextAlign.center, style: ShowdType.hero),
        const SizedBox(height: ShowdSpace.s2),
        Text(
          line,
          textAlign: TextAlign.center,
          style: ShowdType.bodyL.copyWith(color: ShowdColors.stone),
        ),
        const SizedBox(height: ShowdSpace.s6),
      ],
    ),
  );
}

/// Runs a one-shot controller each time a page becomes active.
mixin _PageClock<T extends StatefulWidget>
    on State<T>, TickerProviderStateMixin<T> {
  late final AnimationController clock = AnimationController(
    vsync: this,
    duration: clockDuration,
  );

  Duration get clockDuration;
  bool get active;
  void onStart() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (active && clock.value == 0 && !clock.isAnimating) _start();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (active && !clock.isAnimating && clock.value == 0) _start();
    if (!active && clock.value > 0) clock.value = 0;
  }

  void _start() {
    if (Motion.reduced(context)) {
      clock.value = 1;
      return;
    }
    onStart();
    clock.forward(from: 0);
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }
}

class _RingPage extends StatefulWidget {
  const _RingPage({required this.active});
  final bool active;

  @override
  State<_RingPage> createState() => _RingPageState();
}

class _RingPageState extends State<_RingPage>
    with TickerProviderStateMixin, _PageClock {
  @override
  Duration get clockDuration => const Duration(milliseconds: 900);
  @override
  bool get active => widget.active;
  @override
  void onStart() => Sensory.play(Cue.ding);

  @override
  Widget build(BuildContext context) => _Page(
    title: 'It rings.',
    line: 'At the time you pick.',
    art: AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final appear = Curves.easeOutBack.transform(clock.value);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.6 + appear * 0.4,
              child: RingingMark(size: 150, ringing: widget.active),
            ),
            const SizedBox(height: ShowdSpace.s6),
            Opacity(
              opacity: clock.value,
              child: BigNumber(
                '06:30',
                style: ShowdType.numeralL,
                align: Alignment.center,
                roll: false,
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ProvePage extends StatefulWidget {
  const _ProvePage({required this.active});
  final bool active;

  @override
  State<_ProvePage> createState() => _ProvePageState();
}

class _ProvePageState extends State<_ProvePage>
    with TickerProviderStateMixin, _PageClock {
  static const _proofs = [
    (ShowdIcons.steps, 'Steps'),
    (ShowdIcons.focus, 'Phone down'),
    (ShowdIcons.tagScan, 'Scan a tag'),
    (ShowdIcons.gym, 'Gym'),
    (ShowdIcons.code, 'LeetCode'),
  ];

  @override
  Duration get clockDuration => const Duration(milliseconds: 3200);
  @override
  bool get active => widget.active;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Until you show up.',
    line: 'Your phone checks. No “done” button.',
    art: AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final t = clock.value;
        final which = math.min(
          _proofs.length - 1,
          (t * _proofs.length).floor(),
        );
        final fill = Curves.easeInOutCubic.transform(t);
        final (icon, name) = _proofs[which];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Column(
                key: ValueKey(name),
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      color: ShowdColors.carbon,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: ShowdIcon(
                        icon,
                        size: 52,
                        color: ShowdColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: ShowdSpace.s3),
                  Text(name, style: ShowdType.titleM),
                ],
              ),
            ),
            const SizedBox(height: ShowdSpace.s8),
            SizedBox(width: 240, child: ProofBar(progress: fill)),
            const SizedBox(height: ShowdSpace.s2),
            Text(
              '${(fill * 100).round()}%',
              style: ShowdType.numeralM.copyWith(
                color: fill >= 1 ? ShowdColors.accent : ShowdColors.paper,
                fontSize: 44,
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ReleasePage extends StatefulWidget {
  const _ReleasePage({required this.active});
  final bool active;

  @override
  State<_ReleasePage> createState() => _ReleasePageState();
}

class _ReleasePageState extends State<_ReleasePage>
    with TickerProviderStateMixin, _PageClock {
  var _released = false;

  @override
  Duration get clockDuration => const Duration(milliseconds: 1600);
  @override
  bool get active => widget.active;

  @override
  void onStart() {
    _released = false;
    Sensory.play(Cue.caught);
    clock
      ..removeListener(_watch)
      ..addListener(_watch);
  }

  void _watch() {
    if (!_released && clock.value > 0.45) {
      _released = true;
      Sensory.play(Cue.release);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Then it lets go.',
    line: 'The app you reach for opens again.',
    art: AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final t = clock.value;
        final released = t > 0.45 || Motion.reduced(context);
        final pop = Curves.elasticOut.transform(
          ((t - 0.45) / 0.55).clamp(0, 1),
        );
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              DotBurst(play: released, color: ShowdColors.accent, size: 300),
              Transform.scale(
                scale: released ? 0.9 + pop * 0.1 : 0.9,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    color: released ? ShowdColors.accent : ShowdColors.carbon,
                    borderRadius: BorderRadius.circular(44),
                    border: Border.all(
                      color: released
                          ? ShowdColors.accent
                          : ShowdColors.graphiteStrong,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: FlippingMark(
                      showedUp: released,
                      cue: false,
                      size: 104,
                      lineColor: released ? ShowdColors.ink : ShowdColors.paper,
                      dotColor: released ? ShowdColors.ink : ShowdColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The three study results, counting up. Sources are one tap away.
class _ResearchPage extends StatefulWidget {
  const _ResearchPage({required this.active});
  final bool active;

  @override
  State<_ResearchPage> createState() => _ResearchPageState();
}

class _ResearchPageState extends State<_ResearchPage> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ShowdSpace.gutter),
    child: ResearchNumbers(active: widget.active),
  );
}

class ResearchNumbers extends StatelessWidget {
  const ResearchNumbers({super.key, required this.active});
  final bool active;

  static const findings = [
    (
      57,
      'fewer app opens after a short pause',
      'Grüning et al., PNAS 2023',
      'https://www.pnas.org/doi/10.1073/pnas.2213114120',
    ),
    (
      51,
      'more gym visits with a reward only there',
      'Milkman et al., Management Science 2014',
      'https://pubsonline.informs.org/doi/10.1287/mnsc.2013.1784',
    ),
    (
      91,
      'exercised weekly after planning when and where',
      'Milne et al., Br J Health Psychology 2002',
      'https://bpspsychub.onlinelibrary.wiley.com/doi/abs/10.1348/135910702169420',
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Backed by research.', style: ShowdType.hero),
      const SizedBox(height: ShowdSpace.s6),
      for (final (i, (number, line, source, url)) in findings.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: ShowdSpace.s4),
          child: active
              ? Reveal(
                  delay: Duration(milliseconds: 120 + i * 160),
                  child: _Finding(
                    number: number,
                    line: line,
                    source: source,
                    url: url,
                  ),
                )
              : Opacity(
                  opacity: 0,
                  child: _Finding(
                    number: number,
                    line: line,
                    source: source,
                    url: url,
                  ),
                ),
        ),
    ],
  );
}

class _Finding extends StatelessWidget {
  const _Finding({
    required this.number,
    required this.line,
    required this.source,
    required this.url,
  });

  final int number;
  final String line;
  final String source;
  final String url;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      Sensory.play(Cue.tap);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        showMessage(context, 'Couldn’t open the study.');
      }
    },
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 108,
          child: CountUp(
            value: number,
            format: (v) => '${v.round()}%',
            style: ShowdType.numeralL.copyWith(
              color: ShowdColors.accent,
              fontSize: 64,
            ),
          ),
        ),
        const SizedBox(width: ShowdSpace.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line, style: ShowdType.bodyL),
              Text(
                source,
                style: ShowdType.caption.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: ShowdColors.graphiteStrong,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The research on its own, reachable from Settings.
class WhyThisWorksScreen extends StatelessWidget {
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
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          PushedHeader(onBack: onBack),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ShowdSpace.gutter),
              child: ResearchNumbers(active: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShowdSpace.gutter,
              0,
              ShowdSpace.gutter,
              ShowdSpace.s4,
            ),
            child: ShowdButton(label: continueLabel, onPressed: onContinue),
          ),
        ],
      ),
    ),
  );
}
