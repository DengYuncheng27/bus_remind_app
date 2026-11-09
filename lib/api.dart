import 'repeat_schedule.dart';
import 'vehicles.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Api {
  final String baseUrl;
  final http.Client client;
  final FlutterSecureStorage storage;
  String? token;
  VoidCallback? onUnauthorized;
  bool get demo => false;
  Api({String? baseUrl, http.Client? client, FlutterSecureStorage? storage})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'https://bus.su7.space',
          ),
      client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();

  String get storageKey => 'session:$baseUrl';
  Future<String?> readHomeReminder(String account) =>
      storage.read(key: 'home-reminder:$baseUrl:$account');
  Future<void> saveHomeReminder(String account, String id) =>
      storage.write(key: 'home-reminder:$baseUrl:$account', value: id);
  Future<void> restore() async {
    token = await storage.read(key: storageKey);
  }

  Future<void> saveToken(String value) async {
    await storage.write(key: storageKey, value: value);
    token = value;
  }

  Future<void> logout() async {
    token = null;
    await storage.delete(key: storageKey);
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    final localProxy =
        kIsWeb &&
        const bool.fromEnvironment('LOCAL_API_PROXY') &&
        baseUrl == 'https://bus.su7.space' &&
        Uri.base.host == '127.0.0.1' &&
        Uri.base.port == 8765 &&
        path.startsWith('/api/');
    final uri =
        (localProxy ? Uri.base.resolve(path) : Uri.parse('$baseUrl$path'))
            .replace(queryParameters: query, fragment: '');
    final local = ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host);
    if (uri.scheme != 'https' && !localProxy && (kReleaseMode || !local)) {
      throw ApiException('服务器地址必须使用 HTTPS');
    }
    final currentToken = token;
    final request = http.Request(method, uri)
      ..headers.addAll({
        if (currentToken != null) 'authorization': 'Bearer $currentToken',
        if (body != null) 'content-type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 20));
      if (response.statusCode == 204) return null;
      dynamic payload;
      try {
        payload = jsonDecode(response.body);
      } catch (_) {
        throw ApiException('服务器暂时无法响应，请稍后重试', response.statusCode);
      }
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 &&
            token == currentToken &&
            currentToken != null) {
          await logout();
          onUnauthorized?.call();
        }
        final error = payload is Map ? payload['error'] : null;
        throw ApiException(
          error is Map && error['message'] is String
              ? error['message'] as String
              : '请求失败',
          response.statusCode,
        );
      }
      final renewed = response.headers['x-session-token'];
      if (renewed != null && token == currentToken) await saveToken(renewed);
      return payload;
    } on TimeoutException {
      throw ApiException('连接超时，请检查网络后重试');
    } on http.ClientException {
      throw ApiException(
        kIsWeb ? '请求未完成，可能是连接中断或服务器访问配置异常，请重试' : '无法连接服务器，请稍后重试',
      );
    }
  }

  Future<dynamic> data(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async =>
      (await request(path, method: method, body: body, query: query))?['data'];
}

bool isOn(dynamic value) => value == true || value == 1;
List<Json> objects(dynamic value) =>
    (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
String scheduleLabel(Json reminder) =>
    RepeatSchedule.fromReminder(reminder).summary;
String timeWindow(Json reminder) => reminder['window_start'] == null
    ? '未设置时段'
    : '${reminder['window_start']}–${reminder['window_end']}';
Json? nearestBus(Json realtime) {
  final buses = upcomingBuses(realtime);
  return buses.isEmpty ? null : buses.first;
}

bool isStale(Json realtime, {DateTime? now}) {
  final fetched = DateTime.tryParse(realtime['fetchedAt']?.toString() ?? '');
  return fetched == null ||
      (now ?? DateTime.now()).difference(fetched) > const Duration(minutes: 2);
}

bool pausedToday(Json reminder) {
  final until = DateTime.tryParse(reminder['paused_until']?.toString() ?? '');
  return until != null && until.isAfter(DateTime.now());
}
