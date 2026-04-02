import 'package:dio/dio.dart';

/// Reads `error` string from typical JSON error bodies on [DioException].
String apiErrorMessageFrom(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['error'] as String?;
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
  }
  return '';
}
