import '../core/network/api_client.dart';
import '../core/storage/secure_storage_service.dart';
import '../models/models.dart';

class DeviceService {
  final _dio = ApiClient.instance.dio;

  Future<List<DeviceModel>> list() async {
    final currentId = await SecureStorageService.instance.deviceId;
    final res = await _dio.get(
      '/devices',
      queryParameters: {if (currentId != null) 'current_device_id': currentId},
    );
    return (res.data as List).map((e) => DeviceModel.fromJson(e)).toList();
  }

  Future<void> delete(String deviceId) async {
    await _dio.delete('/devices/$deviceId');
  }
}
