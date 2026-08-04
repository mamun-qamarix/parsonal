import 'package:dio/dio.dart';

import '../storage/secure_storage_service.dart';

class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 30)));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await SecureStorageService.instance.accessToken;
        if (token != null && !options.path.contains('/auth/login') && !options.path.contains('/auth/setup')) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && !_isAuthPath(error.requestOptions.path)) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final clone = await _retry(error.requestOptions);
            return handler.resolve(clone);
          }
        }
        handler.next(error);
      },
    ));
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;
  Dio get dio => _dio;

  bool _isAuthPath(String path) => path.contains('/auth/login') || path.contains('/auth/refresh') || path.contains('/auth/setup');

  Future<void> configureBaseUrl(String server) async {
    _dio.options.baseUrl = server;
  }

  Future<void> ensureConfigured() async {
    final server = await SecureStorageService.instance.server;
    if (server != null) {
      _dio.options.baseUrl = server;
    }
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await SecureStorageService.instance.refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await _dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
      final newAccess = response.data['access_token'] as String;
      await SecureStorageService.instance.saveAccessToken(newAccess);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) async {
    final token = await SecureStorageService.instance.accessToken;
    final options = Options(method: requestOptions.method, headers: {...requestOptions.headers, 'Authorization': 'Bearer $token'});
    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}
