import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

String silisiliDecodeData(String encryptData) {
  if (encryptData.length <= 9) return '';
  try {
    final params1 = encryptData.substring(9);
    final params2 = encryptData.substring(0, 9);
    final digest = md5.convert(utf8.encode(params2)).toString();
    final ivText = digest.substring(0, 16);
    final keyText = digest.substring(16);
    final iv = Uint8List.fromList(utf8.encode(ivText));
    final key = KeyParameter(Uint8List.fromList(utf8.encode(keyText)));
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    cipher.init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(key, iv),
        null,
      ),
    );
    final decoded = base64Decode(params1);
    final result = cipher.process(Uint8List.fromList(decoded));
    return utf8.decode(result);
  } catch (_) {
    return '';
  }
}

String silisiliExtractPlayUrl(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic>) {
      return decoded['url'] as String? ?? '';
    }
  } catch (_) {}
  return '';
}

String silisiliExtractFenjiHtml(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic>) {
      return decoded['fenjihtml'] as String? ?? '';
    }
  } catch (_) {}
  return '';
}
