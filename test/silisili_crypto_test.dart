import 'package:flutter_test/flutter_test.dart';
import 'package:chinobox/src/features/content/data/silisili_crypto.dart';

void main() {
  test('decodes Silisili AES payload', () {
    const encrypted =
        '123456789ckFZzZMTHTQBjDrRonr34t6LjURRPCxjz9yusgTCfMN4uuZz80XRQeypyGqbEM9pLqKM5E5yXOTTmKmUyXUTzv1zLsGClbLa7kapwibrAmw=';

    final decoded = silisiliDecodeData(encrypted);

    expect(silisiliExtractPlayUrl(decoded), 'https://example.com/a.m3u8');
    expect(silisiliExtractFenjiHtml(decoded), '<a href=/play/1>1</a>');
  });
}
