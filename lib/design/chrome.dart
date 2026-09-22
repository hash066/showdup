import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'buttons.dart';
import 'icons.dart';
import 'mark.dart';
import 'sensory.dart';
import 'tokens.dart';
import 'type.dart';

class ShowdNavItem {
  const ShowdNavItem({
    required this.key,
    required this.icon,
    required this.label,
  });
  final Key key;
  final ShowdIcons icon;
  final String label;
}

/// Bottom tabs: icon plus label, the selected tab gets the accent and a dot.
class ShowdNavBar extends StatelessWidget {
  const ShowdNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<ShowdNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ShowdColors.ink,
        border: Border(top: BorderSide(color: ShowdColors.graphite)),
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                for (final (i, item) in items.indexed)
                  Expanded(
                    child: Semantics(
                      key: item.key,
                      selected: i == index,
                      button: true,
                      label: item.label,
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: () {
                          if (i != index) Sensory.play(Cue.page);
                          onSelect(i);
                        },
                        radius: 40,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: i == index ? 1.12 : 1,
                              duration: const Duration(milliseconds: 360),
                              curve: Curves.elasticOut,
                              child: ShowdIcon(
                                item.icon,
                                color: i == index
                                    ? ShowdColors.accent
                                    : ShowdColors.stone,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: ShowdType.caption.copyWith(
                                fontSize: 12,
                                fontWeight: i == index
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: i == index
                                    ? ShowdColors.paper
                                    : ShowdColors.stone,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark next to the name.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.size = 28,
    this.color = ShowdColors.paper,
    this.dotColor = ShowdColors.accent,
  });

  final double size;
  final Color color;
  final Color dotColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ShowdUp',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShowdMark(
          state: MarkState.showedUp,
          size: size,
          lineColor: color,
          dotColor: dotColor,
        ),
        SizedBox(width: size * .25),
        Text(
          'ShowdUp',
          style: ShowdType.titleM.copyWith(
            fontSize: size * .72,
            color: color,
            letterSpacing: -.4,
          ),
        ),
      ],
    ),
  );
}

/// A bottom sheet with the drag handle, gutters and keyboard inset handled.
Future<T?> showShowdSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  Sensory.play(Cue.page);
  return _sheet<T>(context, builder: builder);
}

Future<T?> _sheet<T>(BuildContext context, {required WidgetBuilder builder}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          ShowdSpace.gutter,
          0,
          ShowdSpace.gutter,
          ShowdSpace.s6 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(child: builder(sheetContext)),
      ),
    );

/// A thin segmented progress line for multi-step flows.
class StepLine extends StatelessWidget {
  const StepLine({super.key, required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step ${index + 1} of $count',
    excludeSemantics: true,
    child: Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: AnimatedContainer(
              duration: ShowdMotion.quick,
              height: 3,
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: i <= index ? ShowdColors.accent : ShowdColors.graphite,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Type an exact number instead of dragging a slider. Returns the value,
/// kept between [min] and [max], or null when dismissed.
Future<double?> showNumberEntry(
  BuildContext context, {
  required String title,
  required double value,
  required double min,
  required double max,
  String? unit,
  int decimals = 0,
}) => showShowdSheet<double>(
  context,
  builder: (_) => _NumberEntry(
    title: title,
    value: value,
    min: min,
    max: max,
    unit: unit,
    decimals: decimals,
  ),
);

class _NumberEntry extends StatefulWidget {
  const _NumberEntry({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    this.unit,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final String? unit;

  @override
  State<_NumberEntry> createState() => _NumberEntryState();
}

class _NumberEntryState extends State<_NumberEntry> {
  late final controller = TextEditingController(text: _format(widget.value))
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: _format(widget.value).length,
    );

  String _format(double v) => widget.decimals == 0
      ? v.round().toString()
      : v.toStringAsFixed(widget.decimals);

  double? get _parsed =>
      double.tryParse(controller.text.trim().replaceAll(',', ''));

  bool get _valid {
    final v = _parsed;
    return v != null && v >= widget.min && v <= widget.max;
  }

  void _save() {
    if (!_valid) {
      Sensory.play(Cue.error);
      return;
    }
    Sensory.play(Cue.select);
    final v = _parsed!;
    Navigator.pop(context, widget.decimals == 0 ? v.roundToDouble() : v);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = '${_format(widget.min)}–${_format(widget.max)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: ShowdType.titleL),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.decimals > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(widget.decimals > 0 ? r'[0-9.,]' : r'[0-9,]'),
                  ),
                ],
                style: ShowdType.numeralM.copyWith(color: ShowdColors.accent),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  helperText: _valid ? range : null,
                  errorText: controller.text.isEmpty || _valid
                      ? null
                      : 'Between $range',
                ),
              ),
            ),
            if (widget.unit != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Text(widget.unit!, style: ShowdType.label),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        ShowdButton(label: 'Done', onPressed: _valid ? _save : null),
      ],
    );
  }
}
