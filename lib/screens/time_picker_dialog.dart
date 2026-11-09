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
  final form = GlobalKey<FormState>();
  final hourFocus = FocusNode();
  final minuteFocus = FocusNode();
  late final hour = TextEditingController(
    text: digits(widget.initialTime.hour),
  );
  late final minute = TextEditingController(
    text: digits(widget.initialTime.minute),
  );

  static String digits(int value) => value.toString().padLeft(2, '0');

  @override
  void dispose() {
    hour.dispose();
    minute.dispose();
    hourFocus.dispose();
    minuteFocus.dispose();
    super.dispose();
  }

  void confirm() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(
      context,
      TimeOfDay(hour: int.parse(hour.text), minute: int.parse(minute.text)),
    );
  }

  Widget field({
    required String label,
    required TextEditingController controller,
    required FocusNode focus,
    required int maximum,
    required bool last,
  }) => Expanded(
    child: TextFormField(
      key: ValueKey(last ? 'time-minute' : 'time-hour'),
      controller: controller,
      focusNode: focus,
      keyboardType: TextInputType.number,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: '00–$maximum',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      validator: (text) {
        final value = int.tryParse(text ?? '');
        return value == null || value < 0 || value > maximum
            ? '请输入 00–$maximum'
            : null;
      },
      onTap: () => controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      ),
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: (_) => last ? confirm() : minuteFocus.requestFocus(),
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 440;
          return Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          SizedBox(height: compact ? 16 : 28),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              field(
                                label: '小时',
                                controller: hour,
                                focus: hourFocus,
                                maximum: 23,
                                last: false,
                              ),
                              const Padding(
                                padding: EdgeInsets.fromLTRB(12, 16, 12, 0),
                                child: Text(
                                  ':',
                                  style: TextStyle(fontSize: 32),
                                ),
                              ),
                              field(
                                label: '分钟',
                                controller: minute,
                                focus: minuteFocus,
                                maximum: 59,
                                last: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!compact) ...[
                            const Text('快捷分钟', style: TextStyle(fontSize: 13)),
                            const SizedBox(height: 6),
                          ],
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
                                    selected:
                                        int.tryParse(minute.text) == value,
                                    onSelected: (_) => setState(() {
                                      minute.text = digits(value);
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
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
                        onPressed: confirm,
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
