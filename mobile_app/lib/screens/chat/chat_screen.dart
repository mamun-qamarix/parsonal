import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/crypto/vault_crypto.dart';
import '../../core/network/ws_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/chat_service.dart';
import '../../services/media_service.dart';
import '../../widgets/decrypted_media.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  final _mediaService = MediaService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  List<ChatMessageModel> _messages = [];
  StreamSubscription? _wsSub;
  bool _loading = true;
  bool _recording = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WsClient.instance.connect();
    _load();
    _wsSub = WsClient.instance.events.listen(_onWsEvent);
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final messages = await _chatService.getHistory(vmk);
    if (mounted) setState(() { _messages = messages; _loading = false; });
    _scrollToBottom();
  }

  void _onWsEvent(Map<String, dynamic> data) async {
    if (data['type'] == 'chat_message' || data['type'] == 'chat_ack') {
      final raw = data['message'] as Map<String, dynamic>?;
      if (raw == null) return;
      final msg = ChatMessageModel.fromJson(raw);
      final vmk = context.read<SessionProvider>().vmk!;
      if (msg.encPayload != null) {
        try {
          msg.decryptedText = await VaultCrypto.decryptText(vmk, msg.encPayload!);
        } catch (_) {
          msg.decryptedText = '[unable to decrypt]';
        }
      }
      if (!mounted) return;
      setState(() {
        final existingIndex = _messages.indexWhere((m) => m.id == msg.id);
        if (existingIndex >= 0) {
          _messages[existingIndex] = msg;
        } else {
          _messages.add(msg);
        }
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final vmk = context.read<SessionProvider>().vmk!;
    _textController.clear();
    await _chatService.sendTextViaWs(vmk, text);
  }

  Future<void> _sendMediaFile(String contentType, String kind, File file) async {
    setState(() => _sending = true);
    try {
      final vmk = context.read<SessionProvider>().vmk!;
      final bytes = await file.readAsBytes();
      final asset = await _mediaService.upload(vmk, kind: kind, bytes: bytes);
      final msg = await _chatService.sendMedia(contentType: contentType, mediaAssetId: asset.id);
      if (mounted) setState(() => _messages.add(msg));
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null) await _sendMediaFile('photo', 'image', File(file.path));
  }

  Future<void> _pickVideo() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file != null) await _sendMediaFile('video', 'video', File(file.path));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      await _sendMediaFile('file', 'file', File(result.files.single.path!));
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path != null) await _sendMediaFile('voice', 'voice', File(path));
    } else {
      if (await _recorder.hasPermission()) {
        final dir = Directory.systemTemp;
        final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
        setState(() => _recording = true);
      }
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<SessionProvider>().spouseId;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final msg = _messages[i];
                      final mine = msg.senderId == myId;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                          decoration: BoxDecoration(
                            color: mine ? AppColors.halalGreen.withValues(alpha: 0.85) : Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.contentType == 'text')
                                Text(msg.decryptedText ?? '', style: TextStyle(color: mine ? Colors.white : null))
                              else if (msg.contentType == 'photo' && msg.mediaAssetId != null)
                                ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(height: 180, width: 180, child: DecryptedFullImage(assetId: msg.mediaAssetId!)))
                              else if (msg.contentType == 'video' && msg.mediaAssetId != null)
                                SizedBox(height: 200, width: 220, child: DecryptedVideoPlayer(assetId: msg.mediaAssetId!))
                              else
                                Text('[${msg.contentType}]', style: TextStyle(color: mine ? Colors.white : null, fontStyle: FontStyle.italic)),
                              const SizedBox(height: 4),
                              Text(DateFormat.jm().format(msg.createdAt.toLocal()), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : Colors.grey)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_sending) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.add_circle_outline),
                    onSelected: (v) {
                      if (v == 'image') _pickImage();
                      if (v == 'video') _pickVideo();
                      if (v == 'file') _pickFile();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'image', child: Text('Photo')),
                      PopupMenuItem(value: 'video', child: Text('Video')),
                      PopupMenuItem(value: 'file', child: Text('File')),
                    ],
                  ),
                  IconButton(
                    icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none, color: _recording ? Colors.red : null),
                    onPressed: _toggleRecording,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(hintText: 'Message...'),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send, color: AppColors.halalGreen), onPressed: _sendText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
