import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'api.dart';

@JS('busPush.reason')
external JSString _reason();
@JS('busPush.permission')
external JSPromise<JSString> _permission();
@JS('busPush.current')
external JSPromise<JSString> _current();
@JS('busPush.subscribe')
external JSPromise<JSString> _subscribe(JSString key);
@JS('busPush.hash')
external JSPromise<JSString> _hash(JSString endpoint);
@JS('busPush.disconnect')
external JSPromise<JSString> _disconnect();
@JS('busPush.refreshWorker')
external JSPromise<JSString> _refreshWorker();

class PhonePush {
  final Api api;
  PhonePush(this.api);
  bool get isWeb => true;
  bool get supported => _reason().toDart.isEmpty;
  String? get unavailableReason => supported ? null : _reason().toDart;
  int? _opened;
  set onOpen(void Function(int)? callback) {
    final id = int.tryParse(Uri.base.queryParameters['reminder'] ?? '');
    if (callback != null && id != null && id > 0 && id != _opened) {
      _opened = id;
      scheduleMicrotask(() => callback(id));
    }
  }

  Future<Json?> subscription() async {
    if (!supported) return null;
    final value = jsonDecode((await _current().toDart).toDart);
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<int?> get deviceId async {
    if (api.demo) return null;
    final sub = await subscription();
    if (sub == null) return null;
    final hash = (await _hash((sub['endpoint'] as String).toJS).toDart).toDart;
    final devices = objects(await api.data('/api/web-push/devices'));
    for (final d in devices) {
      if (d['endpointHash'] == hash && isOn(d['active'])) return d['id'] as int;
    }
    return null;
  }

  Future<int> connect() async {
    if (api.demo) throw ApiException('演示模式不会连接通知');
    if (!supported) throw ApiException(unavailableReason!);
    try {
      await _permission().toDart;
      final config = await api.data('/api/web-push/config') as Json;
      if (config['enabled'] != true) throw ApiException('网页通知暂未启用');
      final channels = objects(await api.data('/api/channels'));
      final webChannels = channels.where((c) => c['type'] == 'webpush');
      if (webChannels.isEmpty) {
        await api.data(
          '/api/channels',
          method: 'POST',
          body: {
            'type': 'webpush',
            'label': '网页通知',
            'config': <String, dynamic>{},
          },
        );
      } else if (!isOn(webChannels.first['active'])) {
        await api.data(
          '/api/channels/${webChannels.first['id']}',
          method: 'PATCH',
          body: {'active': true},
        );
      }
      final sub = Map<String, dynamic>.from(
        jsonDecode(
          (await _subscribe(
            (config['publicKey'] as String).toJS,
          ).toDart).toDart,
        ) as Map,
      );
      await api.data('/api/web-push/subscription', method: 'PUT', body: sub);
      final id = await deviceId;
      if (id == null) throw ApiException('设备登记尚未完成，请重试连接');
      return id;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString().replaceFirst('Error: ', ''));
    }
  }

  Future<void> restore() async {
    if (api.demo || !supported) return;
    await _refreshWorker().toDart;
    // Never silently transfer an existing browser subscription to another user.
    final id = await deviceId;
    if (id != null) {
      final sub = await subscription();
      if (sub != null) {
        await api.data('/api/web-push/subscription', method: 'PUT', body: sub);
      }
    }
  }

  Future<void> test() async {
    final id = await deviceId;
    if (id == null) throw ApiException('请先连接本机通知');
    await api.data('/api/web-push/devices/$id/test', method: 'POST');
  }

  Future<void> disconnect() async {
    if (api.demo || !supported) return;
    final sub = await subscription();
    if (sub == null) return;
    await api.request(
      '/api/web-push/subscription',
      method: 'DELETE',
      body: {'endpoint': sub['endpoint']},
    );
    await _disconnect().toDart;
  }
}
