import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../storage/secure_storage_service.dart';

class WsClient {
  WsClient._internal();
  static final WsClient instance = WsClient._internal();

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _controller.stream;
  bool _connecting = false;

  Future<void> connect() async {
    if (_channel != null || _connecting) return;
    _connecting = true;
    try {
      final server = await SecureStorageService.instance.server;
      final token = await SecureStorageService.instance.accessToken;
      if (server == null || token == null) return;
      final wsUrl = server.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
      _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/chat?token=$token'));
      _channel!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {}
        },
        onDone: () {
          _channel = null;
          _scheduleReconnect();
        },
        onError: (_) {
          _channel = null;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 5), connect);
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
