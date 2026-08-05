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
import '../../widgets/shimmer_loading.dart';
import 'media_viewer_screen.dart';

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
    _markVisibleAsRead();
  }

  /// Any message from the OTHER spouse that isn't marked read yet gets
  /// marked read now, since the chat screen being open means it's being
  /// looked at. Fire-and-forget -- a failed mark-read just means the
  /// "seen" tick shows up a bit later than it should, not a real problem.
  void _markVisibleAsRead() {
    final myId = context.read<SessionProvider>().spouseId;
    for (final m in _messages) {
      if (m.senderId != myId && m.readAt == null) {
        _chatService.markRead(m.id);
      }
    }
  }

  void _onWsEvent(Map<String, dynamic> data) async {
    if (data['type'] == 'chat_read') {
      final messageId = data['message_id'] as String?;
      if (messageId == null || !mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == messageId);
        if (i >= 0) _messages[i].readAt = DateTime.tryParse(data['read_at'] as String? ?? '');
      });
      return;
    }
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
      final myId = context.read<SessionProvider>().spouseId;
      if (msg.senderId != myId) _chatService.markRead(msg.id);
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

  Widget _seenTick(ChatMessageModel msg) {
    IconData icon;
    Color color;
    if (msg.readAt != null) {
      icon = Icons.done_all;
      color = Colors.lightBlueAccent;
    } else if (msg.deliveredAt != null) {
      icon = Icons.done_all;
      color = Colors.white70;
    } else {
      icon = Icons.done;
      color = Colors.white70;
    }
    return Icon(icon, size: 14, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<SessionProvider>().spouseId;
    return Scaffold(
      appBar: AppBar(title: const Text('চ্যাট')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const ShimmerTileList()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final msg = _messages[i];
                      final mine = msg.senderId == myId;
                      final isMedia = msg.contentType == 'photo' || msg.contentType == 'video';
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
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => MediaViewerScreen(assetId: msg.mediaAssetId!, contentType: 'photo'),
                                  )),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(height: 180, width: 180, child: DecryptedFullImage(assetId: msg.mediaAssetId!, fit: BoxFit.cover, zoomable: false)),
                                  ),
                                )
                              else if (msg.contentType == 'video' && msg.mediaAssetId != null)
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => MediaViewerScreen(assetId: msg.mediaAssetId!, contentType: 'video'),
                                  )),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox(
                                          height: 180,
                                          width: 180,
                                          child: DecryptedThumbnail(assetId: msg.mediaAssetId!, hasThumbnail: false, fit: BoxFit.cover),
                                        ),
                                      ),
                                      const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                                    ],
                                  ),
                                )
                              else if (msg.contentType == 'voice' && msg.mediaAssetId != null)
                                DecryptedVoicePlayer(assetId: msg.mediaAssetId!, color: mine ? Colors.white : AppColors.halalGreen)
                              else
                                Text('[${msg.contentType}]', style: TextStyle(color: mine ? Colors.white : null, fontStyle: FontStyle.italic)),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    DateFormat.jm().format(msg.createdAt.toLocal()),
                                    style: TextStyle(fontSize: 10, color: mine && !isMedia ? Colors.white70 : Colors.grey),
                                  ),
                                  if (mine) ...[const SizedBox(width: 4), _seenTick(msg)],
                                ],
                              ),
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
                      PopupMenuItem(value: 'image', child: Text('ছবি')),
                      PopupMenuItem(value: 'video', child: Text('ভিডিও')),
                      PopupMenuItem(value: 'file', child: Text('ফাইল')),
                    ],
                  ),
                  IconButton(
                    icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none, color: _recording ? Colors.red : null),
                    onPressed: _toggleRecording,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(hintText: 'লিখুন...'),
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
