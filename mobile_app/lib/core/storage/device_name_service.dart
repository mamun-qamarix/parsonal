import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// The actual phone model (e.g. "Samsung Galaxy A52", "Redmi Note 11") so
/// the Devices screen shows something recognizable instead of a generic
/// placeholder like "this phone" for every entry.
class DeviceNameService {
  static Future<String> detect() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final manufacturer = android.manufacturer.trim();
        final model = android.model.trim();
        if (model.isEmpty) return 'আমার ফোন';
        // Avoid "Samsung Samsung Galaxy A52" when the model already
        // includes the manufacturer name.
        if (manufacturer.isEmpty || model.toLowerCase().contains(manufacturer.toLowerCase())) {
          return model;
        }
        return '$manufacturer $model';
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.name.isNotEmpty ? ios.name : (ios.utsname.machine.isNotEmpty ? ios.utsname.machine : 'আমার ফোন');
      }
    } catch (_) {
      // Fall through to the generic default below.
    }
    return 'আমার ফোন';
  }
}
