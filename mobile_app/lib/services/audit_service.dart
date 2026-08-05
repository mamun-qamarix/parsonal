import '../core/network/api_client.dart';
import '../models/models.dart';

class AuditService {
  final _dio = ApiClient.instance.dio;

  Future<List<AuditLogEntryModel>> getLog({int limit = 200}) async {
    final res = await _dio.get('/audit/log', queryParameters: {'limit': limit});
    return (res.data as List)
        .map((e) => AuditLogEntryModel.fromJson(e))
        .toList();
  }
}
