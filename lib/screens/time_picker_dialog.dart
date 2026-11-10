import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<TimeOfDay?> pickReminderTime(
  BuildContext context, {
  required TimeOfDay initialTime,
  required String title,
}) => showDialog<TimeOfDay>(
  context: context,
  builder: (_) => _TimePickerDialog(initialTime: initialTime, title: title),
);

class _TimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final String title;
  const _TimePickerDialog({required this.initialTime, required this.title});

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late final hour = FixedExtentScrollController(
    initialItem: widget.initialTime.hour,
  );
  late final minute = FixedExtentScrollController(
    initialItem: widget.initialTime.minute,
  );
  final hourFocus = FocusNode();
  final minuteFocus = FocusNode();
  late int selectedMinute = widget.initialTime.minute;

  static String digits(int value) => value.toString().padLeft(2, '0');

  @override
  void dispose() {
    hour.dispose();
    minute.dispose();
    hourFocus.dispose();
    minuteFocus.dispose();
    super.dispose();
  }

  Widget wheel({
    required String name,
    required String label,
    required FixedExtentScrollController controller,
    required FocusNode focus,
    required int count,
    required double extent,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Focus(
            focusNode: focus,
            onFocusChange: (_) => setState(() {}),
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              final next = switch (event.logicalKey) {
                LogicalKeyboardKey.arrowUp => controller.selectedItem - 1,
                LogicalKeyboardKey.arrowDown => controller.selectedItem + 1,
                LogicalKeyboardKey.home => 0,
                LogicalKeyboardKey.end => count - 1,
                _ => null,
              };
              if (next == null) return KeyEventResult.ignored;
              controller.jumpToItem(next.clamp(0, count - 1));
              return KeyEventResult.handled;
            },
            child: Listener(
              onPointerDown: (_) => focus.requestFocus(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: focus.hasFocus ? colors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: SizedBox(
                  height: extent * 3,
                  child: Semantics(
                    label: label,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.invertedStylus,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: CupertinoPicker.builder(
                        key: ValueKey('time-$name'),
                        scrollController: controller,
                        itemExtent: extent,
                        childCount: count,
                        selectionOverlay:
                            CupertinoPickerDefaultSelectionOverlay(
                              background: colors.primary.withValues(
                                alpha: 0.10,
                              ),
                            ),
                        onSelectedItemChanged: (value) {
                          if (name == 'minute') {
                            setState(() => selectedMinute = value);
                          }
                        },
                        itemBuilder: (_, value) => Center(
                          child: Text(
                            digits(value),
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 440;
          final extent = MediaQuery.textScalerOf(context).scale(30) + 18;
          return Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          namesRoute: true,
                          header: true,
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '24 小时制 · 北京时间',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: compact ? 12 : 20),
                        Row(
                          children: [
                            wheel(
                              name: 'hour',
                              label: '小时',
                              controller: hour,
                              focus: hourFocus,
                              count: 24,
                              extent: extent,
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(8, 24, 8, 0),
                              child: Text(':', style: TextStyle(fontSize: 30)),
                            ),
                            wheel(
                              name: 'minute',
                              label: '分钟',
                              controller: minute,
                              focus: minuteFocus,
                              count: 60,
                              extent: extent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('快捷分钟', style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final value in [0, 15, 30, 45])
                              Semantics(
                                label: '$value 分钟',
                                child: ChoiceChip(
                                  label: Text(digits(value)),
                                  showCheckmark: false,
                                  selected: selectedMinute == value,
                                  onSelected: (_) {
                                    minute.jumpToItem(value);
                                    setState(() => selectedMinute = value);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: compact ? 12 : 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          context,
                          TimeOfDay(
                            hour: hour.selectedItem,
                            minute: minute.selectedItem,
                          ),
                        ),
                        child: const Text('确定'),
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
}
