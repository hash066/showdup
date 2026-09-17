import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mark.dart';
import 'sensory.dart';
import 'svg_path.dart';
import 'tokens.dart';

/// Motion switches. Endless animations (loaders, shimmer, ringing) never run
/// in widget tests or when the person turned animations off.
class Motion {
  Motion._();

  static final bool _testing = () {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }();

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static bool loops(BuildContext context) => !_testing && !reduced(context);
}

/// Pushes a screen with ShowdUp's fade-through.
Future<T?> pushShowd<T>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push<T>(ShowdRoute<T>(builder: builder));

/// A fade-through route: the old screen fades out and lifts, the new one
/// fades in and settles. Plays the page cue when it opens.
class ShowdRoute<T> extends PageRouteBuilder<T> {
  ShowdRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: _fadeThrough,
      );

  @override
  TickerFuture didPush() {
    Sensory.play(Cue.page);
    return super.didPush();
  }

  static Widget _fadeThrough(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    final inFade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.2, 1, curve: Curves.easeOut),
    );
    final inScale = Tween(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    final outFade = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: secondary,
        curve: const Interval(0, 0.4, curve: Curves.easeIn),
      ),
    );
    final outScale = Tween(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: secondary, curve: Curves.easeInCubic));
    return FadeTransition(
      opacity: outFade,
      child: ScaleTransition(
        scale: outScale,
        child: FadeTransition(
          opacity: inFade,
          child: ScaleTransition(scale: inScale, child: child),
        ),
      ),
    );
  }
}

/// Fades and rises its child in once, after [delay]. Use in lists with a
/// growing delay for a stagger. No timers, so it is safe in tests.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 18,
    this.duration = const Duration(milliseconds: 520),
  });

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMilliseconds /
          (widget.delay + widget.duration).inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: Offset(0, widget.offset * (1 - _curve.value)),
        child: child,
      ),
    ),
  );
}

/// Staggers [children] in with [Reveal].
List<Widget> staggered(
  List<Widget> children, {
  Duration start = Duration.zero,
  Duration step = const Duration(milliseconds: 55),
}) => [
  for (final (i, child) in children.indexed)
    Reveal(delay: start + step * i, child: child),
];

/// Shrinks a little under the finger, then springs back.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.96,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  var _pressed = false;

  void _set(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: Duration(milliseconds: _pressed ? 90 : 260),
      curve: _pressed ? Curves.easeOut : Curves.elasticOut,
      child: widget.child,
    ),
  );
}

/// A number whose digits roll when it changes, like a departure board.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return Text(text, style: style, maxLines: 1);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final (i, char) in text.characters.indexed)
            ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  final incoming = child.key == ValueKey('$i$char');
                  final slide = Tween(
                    begin: Offset(0, incoming ? 0.7 : -0.7),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.center,
                  children: [...previous, ?current],
                ),
                child: Text(
                  char,
                  key: ValueKey('$i$char'),
                  style: style,
                  maxLines: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Counts from zero up to [value] when it first appears.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.style,
    this.format,
    this.duration = const Duration(milliseconds: 1100),
  });

  final num value;
  final TextStyle style;
  final String Function(num value)? format;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: Motion.reduced(context) ? Duration.zero : duration,
    curve: Curves.easeOutCubic,
    builder: (context, current, _) => Text(
      format?.call(current) ?? current.round().toString(),
      style: style,
      maxLines: 1,
    ),
  );
}

/// ShowdUp's loader: the dot drops into the U, squashes, and bounces back up.
class ShowdLoader extends StatefulWidget {
  const ShowdLoader({super.key, this.size = 56});
  final double size;

  @override
  State<ShowdLoader> createState() => _ShowdLoaderState();
}

class _ShowdLoaderState extends State<ShowdLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.loops(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = .5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) =>
            CustomPaint(painter: _LoaderPainter(_controller.value)),
      ),
    ),
  );
}

class _LoaderPainter extends CustomPainter {
  const _LoaderPainter(this.t);
  final double t;

  static const _cup = 'M28 46V56a20 20 0 0 0 40 0V46';

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 96, size.height / 96);
    // Height of the bounce: 0 at the landing, 1 at the top.
    final height = 1 - math.pow(2 * t - 1, 2).toDouble();
    final landing = 1 - height;
    final squash = landing > 0.85 ? (landing - 0.85) / 0.15 : 0.0;
    final dip = squash * 3;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..color = ShowdColors.paper;
    canvas.save();
    canvas.translate(0, dip);
    canvas.drawPath(svgPath(_cup), line);
    canvas.restore();
    final y = 40 - height * 30;
    canvas.save();
    canvas.translate(48, y + dip);
    canvas.scale(1 + squash * 0.28, 1 - squash * 0.24);
    canvas.drawCircle(Offset.zero, 10, Paint()..color = ShowdColors.accent);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LoaderPainter old) => old.t != t;
}

/// A soft light that sweeps across skeleton blocks while content loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.loops(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final x = -1.5 + _controller.value * 3;
      return ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment(x - 1, -0.3),
          end: Alignment(x + 1, 0.3),
          colors: const [
            ShowdColors.graphite,
            ShowdColors.graphiteStrong,
            ShowdColors.graphite,
          ],
          stops: const [0.35, 0.5, 0.65],
        ).createShader(rect),
        child: child,
      );
    },
  );
}

/// A grey placeholder shape inside a [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = ShowdRadius.control,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(
      color: ShowdColors.graphite,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

/// Placeholder rows: a circle and two lines each.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ShowdSpace.s3),
            child: Row(
              children: [
                const SkeletonBox(height: 36, circle: true),
                const SizedBox(width: ShowdSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.75 - i % 2 * 0.2,
                        child: const SkeletonBox(height: 16, radius: 8),
                      ),
                      const SizedBox(height: ShowdSpace.s2),
                      const FractionallySizedBox(
                        widthFactor: 0.4,
                        child: SkeletonBox(height: 12, radius: 6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// The mark that rings: a bell that rocks in bursts with sound waves around
/// it, or the calm person when [ringing] is false.
class RingingMark extends StatefulWidget {
  const RingingMark({
    super.key,
    this.size = 96,
    this.ringing = true,
    this.state,
    this.waves = true,
  });

  final double size;
  final bool ringing;
  final MarkState? state;
  final bool waves;

  @override
  State<RingingMark> createState() => _RingingMarkState();
}

class _RingingMarkState extends State<RingingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RingingMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.ringing && Motion.loops(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state =
        widget.state ??
        (widget.ringing ? MarkState.ringing : MarkState.showedUp);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // Rock hard for the first 40% of each cycle, then rest.
          final burst = (t / 0.4).clamp(0.0, 1.0);
          final angle = t < 0.4
              ? math.sin(burst * math.pi * 6) * 0.22 * (1 - burst)
              : 0.0;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (widget.waves && widget.ringing && t < 0.7)
                CustomPaint(
                  size: Size.square(widget.size * 1.9),
                  painter: _WavesPainter(t / 0.7),
                ),
              Transform.rotate(
                angle: angle,
                alignment: const Alignment(0, 0.06),
                child: ShowdMark(state: state, size: widget.size),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  const _WavesPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (t - i * 0.18).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final radius = size.width * (0.28 + p * 0.22);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.018
        ..strokeCap = StrokeCap.round
        ..color = ShowdColors.accent.withValues(alpha: (1 - p) * 0.7);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, -math.pi * 0.85, math.pi * 0.35, false, paint);
      canvas.drawArc(rect, -math.pi * 0.5, math.pi * 0.35, false, paint);
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.t != t;
}

/// Dots that burst out from the centre once, when [play] turns true.
class DotBurst extends StatefulWidget {
  const DotBurst({
    super.key,
    required this.play,
    this.size = 260,
    this.color = ShowdColors.ink,
    this.count = 18,
  });

  final bool play;
  final double size;
  final Color color;
  final int count;

  @override
  State<DotBurst> createState() => _DotBurstState();
}

class _DotBurstState extends State<DotBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(DotBurst old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play && !Motion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.play) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !Motion.reduced(context)) _controller.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _BurstPainter(_controller.value, widget.color, widget.count),
      ),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t, this.color, this.count);
  final double t;
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final center = size.center(Offset.zero);
    final random = math.Random(42);
    final eased = Curves.easeOutCubic.transform(t);
    for (var i = 0; i < count; i++) {
      final angle = i / count * math.pi * 2 + random.nextDouble() * 0.35;
      final reach = size.width * (0.28 + random.nextDouble() * 0.22);
      final radius = 2.5 + random.nextDouble() * 4.5;
      final position =
          center + Offset(math.cos(angle), math.sin(angle)) * (reach * eased);
      canvas.drawCircle(
        position,
        radius * (1 - t * 0.6),
        Paint()..color = color.withValues(alpha: (1 - t).clamp(0, 1)),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// A gentle breathing scale, for the companion and calm states.
class Breathe extends StatefulWidget {
  const Breathe({super.key, required this.child, this.amount = 0.04});
  final Widget child;
  final double amount;

  @override
  State<Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<Breathe> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.loops(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => Transform.scale(
      scale: 1 + Curves.easeInOut.transform(_controller.value) * widget.amount,
      child: child,
    ),
  );
}

/// Page dots drawn as tiny marks: the current page stands up as a person.
class MarkDots extends StatelessWidget {
  const MarkDots({super.key, required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Page ${index + 1} of $count',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: ShowdMotion.quick,
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index
                  ? ShowdColors.accent
                  : ShowdColors.graphiteStrong,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    ),
  );
}
