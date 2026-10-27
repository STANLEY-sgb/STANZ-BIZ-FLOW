import 'package:dio/dio.dart';

/// A user-presentable error derived from the API's `{"error": {...}}` envelope.
class ApiError implements Exception {
  const ApiError({required this.code, required this.message, this.status, this.details = const {}});

  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> details;

  bool get isNetwork => code == 'network';
  bool get isUnauthorized => status == 401;

  /// Field-level validation messages, keyed by field name.
  Map<String, String> get fieldErrors {
    final fields = details['fields'];
    if (fields is! List) return const {};
    return {for (final f in fields.whereType<Map>()) '${f['field']}'.split('.').last: '${f['message']}'};
  }

  factory ApiError.from(Object error) {
    if (error is ApiError) return error;
    if (error is DioException) {
      final response = error.response;
      final data = response?.data;
      if (data is Map && data['error'] is Map) {
        final e = data['error'] as Map;
        return ApiError(
          code: '${e['code'] ?? 'error'}',
          message: '${e['message'] ?? 'Something went wrong.'}',
          status: response?.statusCode,
          details: (e['details'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      }
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return const ApiError(
            code: 'network',
            message: "Can't reach the server. Check your internet connection and try again.",
          );
        default:
          return ApiError(
            code: 'http_error',
            message: 'Something went wrong. Please try again.',
            status: response?.statusCode,
          );
      }
    }
    return const ApiError(code: 'unknown', message: 'Something went wrong. Please try again.');
  }

  @override
  String toString() => message;
}
