// Component-only visual QA. No backend calls, accounts or transit fixture data.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xiabanwang/repeat_schedule.dart';
import 'package:xiabanwang/screens/repeat_sheet.dart';
import 'package:xiabanwang/theme.dart';

void main() => runApp(
  MaterialApp(
    title: '自定义重复 · 组件检查',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: commuteTheme(),
    home: const Preview(),
  ),
);

class Preview extends StatefulWidget {
  const Preview({super.key});
  @override
  State<Preview> createState() => _PreviewState();
}

class _PreviewState extends State<Preview> {
  RepeatSchedule value = RepeatSchedule();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  Future<void> open() async {
    final result = await editRepeat(context, value);
    if (result != null && mounted) setState(() => value = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('重复设置')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: ListTile(
        title: const Text('重复'),
        subtitle: Text(value.summary),
        trailing: const Icon(Icons.chevron_right),
        onTap: open,
      ),
    ),
  );
}
