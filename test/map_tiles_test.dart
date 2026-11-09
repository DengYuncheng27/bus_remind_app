import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiabanwang/map_tiles.dart';

void main() {
  test('web tiles stay on the page origin including nonstandard ports', () {
    expect(
      mapTileUrlTemplate(
        isWeb: true,
        pageUri: Uri.parse('https://bus.su7.space/'),
      ),
      'https://bus.su7.space/api/map-tiles/{z}/{x}/{y}.png?v=1',
    );
    expect(
      mapTileUrlTemplate(
        isWeb: true,
        pageUri: Uri.parse('http://localhost:8765/build/'),
      ),
      'http://localhost:8765/api/map-tiles/{z}/{x}/{y}.png?v=1',
    );
    expect(
      mapTileUrlTemplate(isWeb: false),
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
  });

  test(
    'timeout is reported and aborts a request waiting for headers',
    () async {
      final aborted = Completer<void>();
      final client = MapTileClient(
        timeout: const Duration(milliseconds: 20),
        inner: _Client((request) {
          (request as http.Abortable).abortTrigger!.then(
            (_) => aborted.complete(),
          );
          return Completer<http.StreamedResponse>().future;
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.parse('https://example.com/tile')),
        throwsA(isA<TimeoutException>()),
      );
      await aborted.future;
    },
  );

  test('timeout covers a stalled body as well as response headers', () async {
    final body = StreamController<List<int>>();
    final aborted = Completer<void>();
    final client = MapTileClient(
      timeout: const Duration(milliseconds: 20),
      inner: _Client((request) async {
        (request as http.Abortable).abortTrigger!.then((_) {
          aborted.complete();
          body.close();
        });
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.get(Uri.parse('https://example.com/tile')),
      throwsA(isA<TimeoutException>()),
    );
    await aborted.future;
  });

  test('successful transfer retains cache metadata and bytes', () async {
    final client = MapTileClient(
      inner: MockClient(
        (_) async => http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'etag': 'tile', 'cache-control': 'max-age=60'},
        ),
      ),
    );
    addTearDown(client.close);
    final response = await client.get(Uri.parse('https://example.com/tile'));
    expect(response.bodyBytes, [1, 2, 3]);
    expect(response.headers['etag'], 'tile');
    expect(response.headers['cache-control'], 'max-age=60');
  });
}

class _Client extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  _Client(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
