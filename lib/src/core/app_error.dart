import 'dart:typed_data';

class AppError implements Exception {
  const AppError(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class SearchCaptchaRequired extends AppError {
  const SearchCaptchaRequired({
    required this.imageUrl,
    required this.imageBytes,
    this.sourceId = '',
    String message = '请输入验证码后继续搜索',
  }) : super(message);

  final String imageUrl;
  final Uint8List imageBytes;
  final String sourceId;
}
