import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_updates.dart';
import '../palette.dart';
import '../ui.dart';

Future<void> openUpdateLink(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Keep download failures local to the update screen.
  }
  if (context.mounted) notice(context, '无法打开下载页面，请稍后重试。');
}

class UpdateScreen extends StatefulWidget {
  final AppUpdates? updates;
  const UpdateScreen({super.key, this.updates});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  late final updates = widget.updates ?? AppUpdates.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) updates.check();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('检查更新')),
    body: ListenableBuilder(
      listenable: updates,
      builder: (context, _) => pageWidth(
        ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.system_update_outlined, color: green, size: 48),
            const SizedBox(height: 16),
            Text(
              updates.versionLabel,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (updates.checking) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            if (updates.hasNewPackage) ...[
              Text('新版本 ${updates.latest!.version} 可下载'),
              const Text('下载后打开 APK 覆盖安装，无需卸载当前应用。'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    openUpdateLink(context, updates.latest!.downloadUrl),
                child: const Text('下载新版 APK'),
              ),
            ] else if (updates.latest != null && updates.packageError == null)
              const Text('当前已是最新安装包版本。'),
            if (updates.latest != null)
              TextButton(
                onPressed: () =>
                    openUpdateLink(context, updates.latest!.notesUrl),
                child: const Text('查看更新说明'),
              ),
            if (updates.packageError != null) Text(updates.packageError!),
            const Divider(height: 32),
            if (updates.restartRequired)
              const Text('小更新已准备好，完全关闭并重新打开应用后生效。')
            else if (updates.downloadingPatch)
              const Text('正在后台下载小更新，你可以继续使用应用。')
            else if (updates.patchError != null)
              Text(updates.patchError!)
            else if (updates.patchAvailable && !updates.checking)
              const Text('当前小更新已是最新。')
            else if (!updates.checking)
              const Text('当前安装包暂不支持小更新，请通过完整安装包更新。'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: updates.checking ? null : updates.check,
              child: const Text('重新检查'),
            ),
            const SizedBox(height: 12),
            const Text('日常修复会在后台更新。需要完整升级时，安装包由 GitHub 提供。'),
          ],
        ),
      ),
    ),
  );
}

/// The app starts immediately; a dismissible notice appears only after a check.
class UpdateNotice extends StatefulWidget {
  final Widget child;
  final AppUpdates? updates;
  const UpdateNotice({super.key, required this.child, this.updates});
  @override
  State<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<UpdateNotice> {
  bool dismissed = false;
  late final updates = widget.updates ?? AppUpdates.instance;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updates,
    builder: (context, _) {
      return Column(
        children: [
          if (!dismissed && (updates.hasNewPackage || updates.restartRequired))
            MaterialBanner(
              content: Text(
                updates.hasNewPackage
                    ? '新版本 ${updates.latest!.version} 可下载'
                    : '小更新已准备好，下次重新启动应用后生效。',
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => dismissed = true),
                  child: const Text('稍后'),
                ),
                if (updates.hasNewPackage)
                  TextButton(
                    onPressed: () =>
                        openUpdateLink(context, updates.latest!.downloadUrl),
                    child: const Text('下载'),
                  ),
              ],
            ),
          Expanded(child: widget.child),
        ],
      );
    },
  );
}
