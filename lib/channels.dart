import 'api.dart';

const channelNames = {
  'webpush': '网页通知',
  'mobilepush': '手机通知',
  'dingtalk': '钉钉',
  'wecom': '企业微信',
  'feishu': '飞书',
  'telegram': 'Telegram',
  'webhook': 'Webhook',
};
const extensionTypes = ['dingtalk', 'wecom', 'feishu', 'telegram', 'webhook'];
const channelFields = <String, List<(String, String, bool, bool)>>{
  'dingtalk': [
    ('accessToken', '机器人 Webhook 地址或 Access Token', true, true),
    ('secret', '加签 Secret（可选）', true, false),
  ],
  'wecom': [('key', '群机器人 Webhook 地址或 Key', true, true)],
  'feishu': [
    ('appId', '应用 App ID', false, true),
    ('appSecret', '应用 App Secret', true, true),
    ('receiveId', '接收人或群 ID', false, true),
    (
      'receiveIdType',
      'ID 类型：chat_id / open_id / user_id / union_id / email',
      false,
      true,
    ),
  ],
  'telegram': [
    ('botToken', 'Bot Token', true, true),
    ('chatId', 'Chat ID（群组通常为负数）', false, true),
    ('proxyUrl', '服务端代理地址（可选）', false, false),
  ],
  'webhook': [
    ('url', 'HTTPS 回调地址', true, true),
    ('headers', '请求头 JSON（可选）', true, false),
  ],
};

Json channelConfig(
  String type,
  Map<String, String> fields, {
  required bool editing,
}) {
  final config = <String, dynamic>{};
  for (final spec in channelFields[type] ?? <(String, String, bool, bool)>[]) {
    var value = (fields[spec.$1] ?? '').trim();
    if (value.isEmpty) {
      if (spec.$4 && !editing) throw ApiException('请填写${spec.$2}');
      continue;
    }
    if (type == 'dingtalk' &&
        spec.$1 == 'accessToken' &&
        value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri?.host != 'oapi.dingtalk.com') {
        throw ApiException('请填写钉钉机器人的 Webhook 地址');
      }
      value = uri?.queryParameters['access_token'] ?? '';
      if (value.isEmpty) throw ApiException('钉钉地址缺少 access_token');
    }
    if (type == 'wecom' && spec.$1 == 'key' && value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri?.host != 'qyapi.weixin.qq.com') {
        throw ApiException('请填写企业微信群机器人的 Webhook 地址');
      }
      value = uri?.queryParameters['key'] ?? '';
      if (value.isEmpty) throw ApiException('企业微信地址缺少 key');
    }
    if (spec.$1 == 'chatId') {
      final number = int.tryParse(value);
      if (number == null || number.abs() > 9007199254740991) {
        throw ApiException('Chat ID 必须是有效整数');
      }
      config[spec.$1] = number;
    } else {
      config[spec.$1] = value;
    }
  }
  return config;
}
