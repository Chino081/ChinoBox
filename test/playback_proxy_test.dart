import 'dart:convert';
import 'dart:io';

import 'package:chinobox/src/core/network/playback_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwards configured headers and range requests', () async {
    final seenReferers = <String>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      seenReferers.add(request.headers.value(HttpHeaders.refererHeader) ?? '');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final bytes = utf8.encode('playback-proxy');
      if (range == 'bytes=0-3') {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentTypeHeader, 'video/mp4')
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers
              .set(HttpHeaders.contentRangeHeader, 'bytes 0-3/${bytes.length}')
          ..contentLength = 4
          ..add(bytes.take(4).toList());
      } else {
        request.response
          ..headers.set(HttpHeaders.contentTypeHeader, 'video/mp4')
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = bytes.length
          ..add(bytes);
      }
      await request.response.close();
    });

    final target =
        'http://${InternetAddress.loopbackIPv4.address}:${upstream.port}/video.mp4';
    final proxied = await PlaybackProxy.instance.proxiedUrl(target, const {
      'Referer': 'https://www.libvio.run/',
    });
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(proxied));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(
        response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-3/14');
    expect(body, 'play');
    expect(seenReferers.single, 'https://www.libvio.run/');

    client.close(force: true);
    await upstream.close(force: true);
  });
}
