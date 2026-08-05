import '../core/network/api_client.dart';
import '../models/models.dart';

class NotificationService {
  final _dio = ApiClient.instance.dio;

  Future<List<NotificationModel>> list({int limit = 50}) async {
    final res = await _dio.get('/notifications', queryParameters: {'limit': limit});
    return (res.data as List).map((e) => NotificationModel.fromJson(e)).toList();
  }

  Future<int> unreadCount() async {
    final res = await _dio.get('/notifications/unread-count');
    return res.data['unread_count'] as int;
  }

  Future<void> markAllRead() async {
    await _dio.post('/notifications/mark-all-read');
  }
}
