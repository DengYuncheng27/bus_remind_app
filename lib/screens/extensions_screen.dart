import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../channels.dart';
import '../palette.dart';
import '../ui.dart';

class ExtensionsScreen extends StatefulWidget {
  final Api api;
  const ExtensionsScreen({super.key, required this.api});
  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  List<Json>? channels;
  String? error;
  int? busy;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final all = objects(await widget.api.data('/api/channels'));
      if (mounted) {
        setState(() {
          channels = all
              .where((c) => extensionTypes.contains(c['type']))
              .toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> edit([Json? channel]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChannelEditor(api: widget.api, channel: channel),
      ),
    );
    if (mounted) await load();
  }

  Future<void> operate(Json channel, String action) async {
    if (busy != null) return;
    if (action == 'edit') {
      await edit(channel);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('删除这个扩展？'),
          content: Text('将删除“${channel['label']}”。若仍关联提醒，请先修改提醒的接收渠道。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = channel['id'] as int;
      error = null;
    });
    try {
      final path = '/api/channels/${channel['id']}';
      if (action == 'test') {
        await widget.api.data('$path/test', method: 'POST');
        if (mounted) notice(context, '平台已接受测试通知，请到对应渠道检查是否收到。');
      } else if (action == 'delete') {
        await widget.api.request(path, method: 'DELETE');
      } else {
        await widget.api.data(
          path,
          method: 'PATCH',
          body: {'active': !isOn(channel['active'])},
        );
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('高级扩展')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy == null ? () => edit() : null,
      icon: const Icon(Icons.add),
      label: const Text('添加扩展'),
    ),
    body: pageWidth(
      RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
          children: [
            const Text(
              '把提醒发到你常用的地方',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              '支持钉钉、企业微信、飞书、Telegram 和 Webhook。添加后，在提醒设置中选择接收渠道，可同时选择多个。',
              style: TextStyle(height: 1.7, color: Color(0xFF66756C)),
            ),
            const SizedBox(height: 24),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            if (channels == null && error == null)
              const Center(child: CircularProgressIndicator()),
            if (channels == null && error != null)
              TextButton(onPressed: load, child: const Text('重新加载')),
            if (channels?.isEmpty == true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Column(
                  children: [
                    Icon(Icons.extension_outlined, size: 40, color: green),
                    SizedBox(height: 16),
                    Text('还没有配置扩展'),
                    SizedBox(height: 8),
                    Text(
                      '先添加一个，再发送测试通知。',
                      style: TextStyle(color: Color(0xFF66756C)),
                    ),
                  ],
                ),
              ),
            for (final c in channels ?? <Json>[]) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                title: Text(
                  c['label'],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${channelNames[c['type']] ?? c['type']} · ${isOn(c['active']) ? '已启用' : '已停用'}\n${c['reminderCount'] ?? 0} 条提醒使用',
                ),
                isThreeLine: true,
                leading: const Icon(
                  Icons.notifications_active_outlined,
                  color: green,
                ),
                trailing: busy == c['id']
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        enabled: busy == null,
                        tooltip: '管理扩展',
                        onSelected: (action) => operate(c, action),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('编辑配置与模板'),
                          ),
                          const PopupMenuItem(
                            value: 'test',
                            child: Text('发送测试通知'),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(isOn(c['active']) ? '停用' : '启用'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                        ],
                      ),
                onTap: busy == null ? () => edit(c) : null,
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    ),
  );
}

class ChannelEditor extends StatefulWidget {
  final Api api;
  final Json? channel;
  const ChannelEditor({super.key, required this.api, this.channel});
  @override
  State<ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<ChannelEditor> {
  final form = GlobalKey<FormState>();
  final label = TextEditingController(),
      title = TextEditingController(),
      body = TextEditingController();
  final inputs = <String, TextEditingController>{};
  String type = 'dingtalk';
  bool busy = false, custom = false, templateChanged = false;
  String? error;
  bool get editing => widget.channel != null;
  @override
  void initState() {
    super.initState();
    final c = widget.channel;
    type = c?['type'] ?? 'dingtalk';
    label.text = c?['label'] ?? '';
    final template = c?['template'] as Map?;
    custom = template?['customized'] == true;
    title.text = template?['title'] ?? '{{headline}}';
    body.text = template?['body'] ?? '{{cityName}} · {{lineNo}}路\n距{{targetStopName}}还有{{stationsAway}}站，{{etaText}}';
  }

  @override
  void dispose() {
    for (final c in [label, title, body, ...inputs.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final config = channelConfig(
        type,
        inputs.map((k, c) => MapEntry(k, c.text)),
        editing: editing,
      );
      if (config['headers'] != null) {
        final value = jsonDecode(config['headers'] as String);
        if (value is! Map || value.values.any((v) => v is! String)) {
          throw ApiException('请求头应是字符串键值组成的 JSON 对象');
        }
        config['headers'] = value;
      }
      final payload = <String, dynamic>{
        'label': label.text.trim(),
        if (!editing) 'type': type,
        if (!editing || config.isNotEmpty) 'config': config,
        if (!editing && custom || editing && templateChanged)
          'template': custom
              ? {'title': title.text.trim(), 'body': body.text.trim()}
              : null,
      };
      await widget.api.data(
        editing ? '/api/channels/${widget.channel!['id']}' : '/api/channels',
        method: editing ? 'PATCH' : 'POST',
        body: payload,
      );
      if (mounted) {
        notice(context, '扩展已保存，可发送测试通知检查配置。');
        Navigator.pop(context);
      }
    } on FormatException {
      if (mounted) setState(() => error = '请求头 JSON 格式有误');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(editing ? '编辑扩展' : '添加扩展')),
    bottomNavigationBar: SafeArea(
      child: pageWidth(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? '保存中…' : '保存扩展'),
          ),
        ),
      ),
    ),
    body: pageWidth(
      Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!editing)
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: '推送平台'),
                items: extensionTypes
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(channelNames[t]!),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) {
                        for (final c in inputs.values) {
                          c.clear();
                        }
                        setState(() => type = v!);
                      },
              ),
            if (editing)
              Text(
                channelNames[type]!,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 24),
            TextFormField(
              controller: label,
              maxLength: 60,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：下班提醒群',
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '请填写名称' : null,
            ),
            const SizedBox(height: 16),
            Text(
              editing
                  ? '已保存的凭证不会显示。留空保留原配置，仅填写需要替换的字段。'
                  : type == 'feishu'
                  ? '飞书使用自建应用，需启用机器人并授予发送消息权限。'
                  : type == 'webhook'
                  ? '仅支持公开 HTTPS 地址；若后台配置了域名白名单，需要先添加允许的域名。'
                  : '请在对应平台创建机器人，复制凭证到这里。凭证由服务器加密保存。',
              style: const TextStyle(height: 1.6, color: Color(0xFF66756C)),
            ),
            for (final spec in channelFields[type]!)
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: TextFormField(
                  key: ValueKey('$type-${spec.$1}'),
                  controller: inputs.putIfAbsent(
                    spec.$1,
                    TextEditingController.new,
                  ),
                  enabled: !busy,
                  obscureText: spec.$3,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: spec.$2,
                    hintText: editing
                        ? '留空保留原值'
                        : spec.$1 == 'receiveIdType'
                        ? 'chat_id'
                        : null,
                  ),
                  validator: (v) =>
                      !editing && spec.$4 && (v == null || v.trim().isEmpty)
                      ? '请填写此项'
                      : null,
                ),
              ),
            const SizedBox(height: 24),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自定义通知模板'),
              subtitle: const Text('关闭后使用系统默认内容'),
              value: custom,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      custom = v;
                      templateChanged = true;
                    }),
            ),
            if (custom) ...[
              TextFormField(
                controller: title,
                maxLength: 120,
                decoration: const InputDecoration(labelText: '通知标题'),
                onChanged: (_) => templateChanged = true,
                validator: (v) =>
                    custom && (v?.trim().isEmpty ?? true) ? '请填写标题' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: body,
                minLines: 4,
                maxLines: 10,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: '通知正文'),
                onChanged: (_) => templateChanged = true,
                validator: (v) =>
                    custom && (v?.trim().isEmpty ?? true) ? '请填写正文' : null,
              ),
              const Text(
                '可用变量：{{headline}}、{{lineNo}}、{{cityName}}、{{targetStopName}}、{{stationsAway}}、{{distanceMeters}}、{{etaMinutes}}、{{etaText}}、{{direction}}、{{busId}}、{{thresholdStations}}、{{updatedAt}}、{{occurredAt}}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Color(0xFF66756C),
                ),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}

Future<Set<int>?> selectDelivery(
  BuildContext context,
  Api api,
  Set<int> selected,
) => showModalBottomSheet<Set<int>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => DeliverySheet(api: api, selected: selected),
);

class DeliverySheet extends StatefulWidget {
  final Api api;
  final Set<int> selected;
  const DeliverySheet({super.key, required this.api, required this.selected});
  @override
  State<DeliverySheet> createState() => _DeliverySheetState();
}

class _DeliverySheetState extends State<DeliverySheet> {
  late final selected = {...widget.selected};
  List<Json>? channels;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final list = objects(await widget.api.data('/api/channels'));
      if (mounted) {
        setState(() {
          channels = list;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        channels != null &&
        selected.isNotEmpty &&
        selected.every(
          (id) => channels!.any(
            (c) => c['id'] == id && isOn(c['active']) && c['ready'] == true,
          ),
        );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: pageWidth(
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '提醒发送到',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text('可同时选择多个接收渠道。'),
                const SizedBox(height: 16),
                Expanded(
                  child: channels == null
                      ? error == null
                            ? const Center(child: CircularProgressIndicator())
                            : ErrorNotice(error!, load)
                      : ListView(
                          children: [
                            if (channels!.isEmpty)
                              const Text('暂无可用渠道。请先在“我的”连接通知或添加高级扩展。'),
                            for (final c in channels!)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(c['label']),
                                subtitle: Text(
                                  '${channelNames[c['type']] ?? c['type']}${!isOn(c['active'])
                                      ? ' · 已停用'
                                      : c['ready'] != true
                                      ? ' · 尚未连接'
                                      : ''}',
                                ),
                                value: selected.contains(c['id']),
                                onChanged:
                                    (isOn(c['active']) && c['ready'] == true) ||
                                        selected.contains(c['id'])
                                    ? (v) => setState(() {
                                        if (v == true) {
                                          selected.add(c['id'] as int);
                                        } else {
                                          selected.remove(c['id']);
                                        }
                                      })
                                    : null,
                              ),
                          ],
                        ),
                ),
                FilledButton(
                  onPressed: valid
                      ? () => Navigator.pop(context, selected)
                      : null,
                  child: Text('使用这 ${selected.length} 个渠道'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
