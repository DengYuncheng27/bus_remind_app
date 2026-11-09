import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

String mapTileUrlTemplate({bool isWeb = kIsWeb, Uri? pageUri}) => isWeb
    ? '${(pageUri ?? Uri.base).origin}/api/map-tiles/{z}/{x}/{y}.png'
    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

// Bound the entire transfer, including a response whose headers arrive but
// whose body stalls. A timeout must be an error, not a silent transparent tile.
class MapTileClient extends http.BaseClient {
  final http.Client _inner;
  final Duration timeout;
  MapTileClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 12),
  }) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abort = Completer<void>();
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    if (request is http.Abortable) request.abortTrigger?.then((_) => cancel());
    final bounded = http.AbortableRequest(
      request.method,
      request.url,
      abortTrigger: abort.future,
    )..headers.addAll(request.headers);
    bounded.bodyBytes = await request.finalize().toBytes();
    final response = await _inner
        .send(bounded)
        .then(http.Response.fromStream)
        .timeout(
          timeout,
          onTimeout: () {
            cancel();
            throw TimeoutException('地图加载超时', timeout);
          },
        );
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      contentLength: response.bodyBytes.length,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

class BusMapTileProvider extends NetworkTileProvider {
  final MapTileClient _client;
  BusMapTileProvider() : this._(MapTileClient());
  BusMapTileProvider._(this._client)
    : super(httpClient: _client, attemptDecodeOfHttpErrorResponses: false);

  @override
  Future<void> dispose() async {
    _client.close();
    await super.dispose();
  }
}

class BusMapTiles extends StatefulWidget {
  final VoidCallback onError;
  const BusMapTiles({super.key, required this.onError});

  @override
  State<BusMapTiles> createState() => _BusMapTilesState();
}

class _BusMapTilesState extends State<BusMapTiles> {
  final provider = BusMapTileProvider();

  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: mapTileUrlTemplate(),
    tileProvider: provider, // TileLayer disposes it when this layer is removed.
    userAgentPackageName: 'space.su7.xiabanwang',
    panBuffer: 0,
    maxNativeZoom: 19,
    errorTileCallback: (_, _, _) => widget.onError(),
  );
}
