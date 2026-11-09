import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';
import '../repeat_schedule.dart';

Future<RepeatSchedule?> editRepeat(
  BuildContext context,
  RepeatSchedule value,
) => showModalBottomSheet<RepeatSchedule>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 600),
  builder: (_) => RepeatSheet(value: value),
);

class RepeatSheet extends StatefulWidget {
  final RepeatSchedule value;
  const RepeatSheet({super.key, required this.value});
  @override
  State<RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<RepeatSheet> {
  late final TextEditingController interval;
  late Set<int> days;
  late DateTime anchor;
  late bool skipHolidays;
  String? error;
  @override
  void initState() {
    super.initState();
    final value = widget.value;
    interval = TextEditingController(text: '${value.intervalWeeks}');
    days =
        (value.mode == 'daily'
                ? [1, 2, 3, 4, 5, 6, 7]
                : value.mode == 'china_workday'
                ? [1, 2, 3, 4, 5]
                : value.weekdays)
            .toSet();
    anchor = value.anchor;
    skipHolidays = value.skipHolidays;
  }

  @override
  void dispose() {
    interval.dispose();
    super.dispose();
  }

  Widget weekdays(Set<int> selected, String label, String keyPrefix) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 2,
          runSpacing: 4,
          children: [
            for (var day = 1; day <= 7; day++)
              SizedBox(
                width: (constraints.maxWidth - 12) / 7,
                height: 48,
                child: Semantics(
                  button: true,
                  selected: selected.contains(day),
                  label: '$label 周${weekdayNames[day - 1]}',
                  child: Tooltip(
                    message: '$label 周${weekdayNames[day - 1]}',
                    excludeFromSemantics: true,
                    child: InkWell(
                      key: ValueKey('$keyPrefix-$day'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => setState(() {
                        selected.contains(day)
                            ? selected.remove(day)
                            : selected.add(day);
                        error = null;
                      }),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected.contains(day)
                                ? green
                                : Colors.transparent,
                          ),
                          child: ExcludeSemantics(
                            child: Text(
                              weekdayNames[day - 1],
                              style: TextStyle(
                                color: selected.contains(day)
                                    ? Colors.white
                                    : ink,
                                fontSize: 16,
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
      ),
    ],
  );

  void confirm() {
    final weeks = int.tryParse(interval.text);
    if (weeks == null || weeks < 1 || weeks > 52) {
      setState(() => error = '请输入 1–52 之间的周数');
      return;
    }
    if (days.isEmpty) {
      setState(() => error = '至少选择一个星期');
      return;
    }
    Navigator.pop(
      context,
      RepeatSchedule(
        intervalWeeks: weeks,
        weekdays: days.toList()..sort(),
        anchor: anchor,
        skipHolidays: skipHolidays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('自定义重复', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('每', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: const ValueKey('repeat-interval'),
                    controller: interval,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: (_) => setState(() => error = null),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('周', style: TextStyle(fontSize: 17)),
              ],
            ),
            const SizedBox(height: 20),
            weekdays(days, '提醒星期', 'weekday'),
            CheckboxListTile(
              key: const ValueKey('skip-holidays'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('跳过法定节假日'),
              value: skipHolidays,
              onChanged: (v) => setState(() => skipHolidays = v!),
            ),
            const Divider(height: 24),
            ListTile(
              key: const ValueKey('repeat-anchor'),
              contentPadding: EdgeInsets.zero,
              title: const Text('开始日期'),
              subtitle: Text(dateText(anchor)),
              trailing: const Icon(Icons.calendar_today_outlined, size: 22),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: anchor,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: '选择开始日期',
                );
                if (selected != null && mounted) {
                  setState(
                    () => anchor = DateTime.utc(
                      selected.year,
                      selected.month,
                      selected.day,
                    ),
                  );
                }
              },
            ),
            Text(
              int.tryParse(interval.text) == 1
                  ? '从开始日期起，按所选星期提醒。'
                  : '开始日期所在周为提醒周，之后按间隔重复。',
              style: const TextStyle(color: Color(0xFF66756C), fontSize: 13),
            ),
            if (widget.value.mode == 'china_workday')
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  '确认后改为按星期重复，不再自动跟随调休补班。',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
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
      ),
    ),
  );
}
