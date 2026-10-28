import 'dart:async';

import 'package:dio/dio.dart';

import 'api_error.dart';
import 'token_store.dart';

/// Base URL is supplied at build time:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1
/// The default targets a local API from the Android emulator.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000/api/v1');

typedef SessionExpiredCallback = void Function();

/// Turns a server-relative file path (e.g. "/api/v1/files/…?sig=…") into an absolute URL.
String? fileUrl(String? path) => path == null ? null : Uri.parse(apiBaseUrl).resolve(path).toString();

/// HTTP client with bearer auth and single-flight token refresh.
class ApiClient {
  ApiClient({required this.tokens, Dio? dio, String baseUrl = apiBaseUrl})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              contentType: Headers.jsonContentType,
            ),
          ) {
    this.dio.interceptors.add(QueuedInterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final Dio dio;
  final TokenStore tokens;

  /// Interceptor-free twin for refresh and retry, so a failing retry can never
  /// re-enter (and deadlock) the queued error interceptor.
  late final Dio _raw = Dio(dio.options)..httpClientAdapter = dio.httpClientAdapter;
  SessionExpiredCallback? onSessionExpired;
  Future<bool>? _refreshing;

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['auth'] != false) {
      final t = await tokens.read();
      if (t != null) options.headers['Authorization'] = 'Bearer ${t.access}';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final canRefresh = err.response?.statusCode == 401 && request.extra['auth'] != false;
    if (!canRefresh) return handler.next(err);

    // If another request already refreshed while this one was in flight, just retry with the new token.
    final current = await tokens.read();
    final alreadyRefreshed = current != null && request.headers['Authorization'] != 'Bearer ${current.access}';
    final refreshed = alreadyRefreshed || await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    if (!refreshed) {
      onSessionExpired?.call();
      return handler.next(err);
    }
    try {
      final t = await tokens.read();
      request.headers['Authorization'] = 'Bearer ${t!.access}';
      handler.resolve(await _raw.fetch(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _refresh() async {
    final t = await tokens.read();
    if (t == null) return false;
    try {
      final res = await _raw.post<Map<String, dynamic>>('/auth/refresh', data: {'refresh_token': t.refresh});
      await tokens.write(access: res.data!['access_token'] as String, refresh: res.data!['refresh_token'] as String);
      return true;
    } on DioException catch (e) {
      // Only a definitive rejection ends the session; network failures keep tokens for a later retry.
      if (e.response?.statusCode == 401) await tokens.clear();
      return false;
    }
  }

  Future<T> _wrap<T>(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data as T;
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get<dynamic>(path, queryParameters: _clean(query)));

  Future<T> post<T>(String path, {Object? data, bool auth = true}) => _wrap(
    () => dio.post<dynamic>(
      path,
      data: data,
      options: Options(extra: {'auth': auth}),
    ),
  );

  Future<T> patch<T>(String path, {Object? data}) => _wrap(() => dio.patch<dynamic>(path, data: data));

  /// Multipart upload of a single file (e.g. product import).
  Future<T> postFile<T>(
    String path, {
    required String field,
    required String filename,
    required List<int> bytes,
    Map<String, dynamic>? query,
  }) => _wrap(
    () => dio.post<dynamic>(
      path,
      queryParameters: _clean(query),
      data: FormData.fromMap({field: MultipartFile.fromBytes(bytes, filename: filename)}),
      options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
    ),
  );

  /// Raw bytes of a download (e.g. CSV export).
  Future<List<int>> getBytes(String path) =>
      _wrap(() => dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes)));

  Future<Map<String, dynamic>> deleteJson(String path) => _wrap(() => dio.delete<dynamic>(path));

  Future<void> delete(String path) => _wrap<dynamic>(() => dio.delete<dynamic>(path));

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null || v == ''));
}
