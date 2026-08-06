import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/audio/chat_sound_service.dart';
import '../../core/crypto/vault_crypto.dart';
import '../../core/media/video_thumbnail_helper.dart';
import '../../core/network/ws_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/chat_service.dart';
import '../../services/media_service.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/media_viewer_screen.dart';
import 'chat_gallery_screen.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  final _mediaService = MediaService();
  final _textController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _recorder = AudioRecorder();
  List<ChatMessageModel> _messages = [];
  StreamSubscription? _wsSub;
  bool _loading = true;
  bool _sending = false;

  // Infinite-scroll pagination: loads further back in history as the user
  // scrolls up, all the way to the very first message ever exchanged.
  // Previously the backend's `before` param was silently ignored, so
  // "loading more" always re-fetched the same newest 50 messages -- see
  // DECISIONS.md.
  static const _pageSize = 50;
  bool _hasMoreHistory = true;
  bool _loadingMoreHistory = false;

  // Search: since messages are E2E encrypted, the server can't search
  // them -- matching happens entirely on-device against decrypted text,
  // auto-paginating further back through history as needed until a match
  // is found or the very start of the conversation is reached.
  bool _searching = false;
  final _searchController = TextEditingController();
  List<ChatMessageModel> _searchResults = [];
  bool _searchLoading = false;
  String? _searchStatus;

  // Privacy mask: purely local UI state, per DECISIONS.md -- toggling this
  // only affects what THIS device renders, never synced or visible to the
  // other spouse unless they independently toggle their own.
  bool _hidden = false;

  // WhatsApp-style voice recording state.
  bool _recording = false;
  bool _paused = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<double> _waveform = [];

  @override
  void initState() {
    super.initState();
    WsClient.instance.connect();
    _load();
    _wsSub = WsClient.instance.events.listen(_onWsEvent);
    _itemPositionsListener.itemPositions.addListener(_onScrollPositionsChanged);
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final messages = await _chatService.getHistory(vmk, limit: _pageSize);
    if (mounted) {
      setState(() {
        _messages = messages;
        _loading = false;
        _hasMoreHistory = messages.length >= _pageSize;
      });
    }
    _scrollToBottom();
    _markVisibleAsRead();
  }

  /// Triggers loading older history once the top of the currently-loaded
  /// window scrolls into view -- the natural "pull up for more" gesture.
  void _onScrollPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final topIndex = positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    if (topIndex <= 2) _loadMoreHistory();
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMoreHistory || !_hasMoreHistory || _messages.isEmpty) return;
    setState(() => _loadingMoreHistory = true);
    final vmk = context.read<SessionProvider>().vmk!;
    final older = await _chatService.getHistory(
      vmk,
      before: _messages.first.id,
      limit: _pageSize,
    );
    if (!mounted) return;
    final addedCount = older.length;
    setState(() {
      if (addedCount > 0) _messages = [...older, ..._messages];
      _hasMoreHistory = addedCount >= _pageSize;
      _loadingMoreHistory = false;
    });
    // Everything that was on screen just shifted down by `addedCount`
    // slots -- jump straight back to the equivalent index so the view
    // doesn't visibly jump when the older messages are prepended.
    if (addedCount > 0 && _itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: addedCount);
    }
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
        if (i >= 0)
          _messages[i].readAt = DateTime.tryParse(
            data['read_at'] as String? ?? '',
          );
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
          msg.decryptedText = await VaultCrypto.decryptText(
            vmk,
            msg.encPayload!,
          );
        } catch (_) {
          msg.decryptedText = '[ডিক্রিপ্ট করা যায়নি]';
        }
      }
      if (!mounted) return;
      final myId = context.read<SessionProvider>().spouseId;
      final isNewIncoming =
          msg.senderId != myId && !_messages.any((m) => m.id == msg.id);
      setState(() {
        final existingIndex = _messages.indexWhere((m) => m.id == msg.id);
        if (existingIndex >= 0) {
          _messages[existingIndex] = msg;
        } else {
          _messages.add(msg);
        }
      });
      _scrollToBottom();
      if (isNewIncoming) {
        ChatSoundService.playReceived();
        _chatService.markRead(msg.id);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollController.isAttached && _messages.isNotEmpty) {
        _itemScrollController.scrollTo(
          index: _messages.length - 1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Search: on-device only, since messages are E2E encrypted the
  // server never sees plaintext and can't search for us. Matches
  // currently-loaded messages first, then keeps paging further back
  // through history (decrypting as it goes) until either a match turns
  // up or the very start of the conversation is reached. ---

  void _openSearch() {
    setState(() {
      _searching = true;
      _searchResults = [];
      _searchStatus = null;
    });
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
      _searchResults = [];
      _searchStatus = null;
    });
  }

  Future<void> _runSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchStatus = null;
      });
      return;
    }
    setState(() => _searchLoading = true);
    final vmk = context.read<SessionProvider>().vmk!;
    final lower = query.toLowerCase();
    List<ChatMessageModel> matches = _messages
        .where((m) => (m.decryptedText ?? '').toLowerCase().contains(lower))
        .toList();

    // Keep paging further back until we find something, run out of
    // history, or hit a sane safety cap (very long threads shouldn't spin
    // forever on a query that simply doesn't exist).
    var safetyPages = 0;
    while (matches.isEmpty && _hasMoreHistory && safetyPages < 40 && mounted) {
      safetyPages++;
      setState(() => _searchStatus = 'পুরনো মেসেজ খোঁজা হচ্ছে...');
      final older = await _chatService.getHistory(
        vmk,
        before: _messages.first.id,
        limit: 100,
      );
      if (!mounted) return;
      if (older.isEmpty) {
        setState(() => _hasMoreHistory = false);
        break;
      }
      setState(() {
        _messages = [...older, ..._messages];
        _hasMoreHistory = older.length >= 100;
      });
      matches = _messages
          .where((m) => (m.decryptedText ?? '').toLowerCase().contains(lower))
          .toList();
    }

    if (!mounted) return;
    setState(() {
      _searchResults = matches.reversed.toList(); // newest match first
      _searchLoading = false;
      _searchStatus = matches.isEmpty
          ? (_hasMoreHistory ? null : 'কিছু পাওয়া যায়নি।')
          : null;
    });
  }

  void _jumpToSearchResult(ChatMessageModel msg) {
    _closeSearch();
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollController.isAttached) {
        _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.4,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final vmk = context.read<SessionProvider>().vmk!;
    _textController.clear();
    await _chatService.sendTextViaWs(vmk, text);
    ChatSoundService.playSent();
  }

  Future<void> _sendMediaFile(
    String contentType,
    String kind,
    File file,
  ) async {
    setState(() => _sending = true);
    try {
      final vmk = context.read<SessionProvider>().vmk!;
      final bytes = await file.readAsBytes();
      final thumbnailBytes = kind == 'video'
          ? await generateVideoThumbnail(file.path)
          : null;
      final asset = await _mediaService.upload(
        vmk,
        kind: kind,
        bytes: bytes,
        thumbnailBytes: thumbnailBytes,
      );
      final msg = await _chatService.sendMedia(
        contentType: contentType,
        mediaAssetId: asset.id,
      );
      if (mounted) setState(() => _messages.add(msg));
      _scrollToBottom();
      ChatSoundService.playSent();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
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

  // --- Voice recording: start/pause/resume/cancel/send, WhatsApp-style ---

  void _startRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted)
        setState(() => _recordDuration += const Duration(seconds: 1));
    });
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = Directory.systemTemp;
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _waveform.clear();
    _recordDuration = Duration.zero;
    _startRecordTimer();
    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen((amp) {
          // amp.current is dBFS, roughly -45 (quiet) to 0 (loud) in practice.
          final level = ((amp.current + 45) / 45).clamp(0.05, 1.0);
          if (mounted) {
            setState(() {
              _waveform.add(level);
              if (_waveform.length > 40) _waveform.removeAt(0);
            });
          }
        });
    setState(() {
      _recording = true;
      _paused = false;
    });
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _recorder.resume();
      _startRecordTimer();
    } else {
      await _recorder.pause();
      _recordTimer?.cancel();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _resetRecordingState() async {
    _recordTimer?.cancel();
    await _amplitudeSub?.cancel();
    if (mounted) {
      setState(() {
        _recording = false;
        _paused = false;
        _recordDuration = Duration.zero;
        _waveform.clear();
      });
    }
  }

  Future<void> _cancelRecording() async {
    final path = await _recorder.stop();
    await _resetRecordingState();
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _finishAndSendRecording() async {
    final path = await _recorder.stop();
    await _resetRecordingState();
    if (path != null) await _sendMediaFile('voice', 'voice', File(path));
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _itemPositionsListener.itemPositions.removeListener(_onScrollPositionsChanged);
    _searchController.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildSearchResults() {
    if (_searchLoading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    if (_searchController.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('একটা শব্দ বা লাইন লিখে সার্চ করুন।', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(_searchStatus ?? 'কিছু পাওয়া যায়নি।', style: const TextStyle(color: Colors.grey)),
      );
    }
    final query = _searchController.text.trim();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final msg = _searchResults[i];
        final text = msg.decryptedText ?? '';
        final matchIndex = text.toLowerCase().indexOf(query.toLowerCase());
        return ListTile(
          leading: const Icon(Iconsax.message_2),
          title: matchIndex < 0
              ? Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)
              : _highlightedSnippet(text, matchIndex, query.length),
          subtitle: Text(DateFormat.yMMMd().add_jm().format(msg.createdAt.toLocal())),
          onTap: () => _jumpToSearchResult(msg),
        );
      },
    );
  }

  Widget _highlightedSnippet(String text, int matchIndex, int matchLength) {
    const contextChars = 40;
    final start = (matchIndex - contextChars).clamp(0, text.length);
    final end = (matchIndex + matchLength + contextChars).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: '$prefix${text.substring(start, matchIndex)}'),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + matchLength),
            style: const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Color(0x552F9E63)),
          ),
          TextSpan(text: '${text.substring(matchIndex + matchLength, end)}$suffix'),
        ],
      ),
    );
  }

  Widget _seenTick(ChatMessageModel msg) {
    // Always sits on top of "mine"'s primary-colored bubble -- must use
    // onPrimary, not a hardcoded white, or it goes near-invisible in dark
    // mode where primary is a deliberately pale color. See DECISIONS.md.
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    IconData icon;
    Color color;
    if (msg.readAt != null) {
      icon = Iconsax.tick_circle_copy;
      color = Colors.lightBlueAccent;
    } else if (msg.deliveredAt != null) {
      icon = Iconsax.tick_circle_copy;
      color = onPrimary.withValues(alpha: 0.7);
    } else {
      icon = Iconsax.tick_circle;
      color = onPrimary.withValues(alpha: 0.7);
    }
    return Icon(icon, size: 14, color: color);
  }

  Widget _hiddenPlaceholder(bool mine) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Iconsax.lock,
          size: 13,
          color: mine ? onPrimary.withValues(alpha: 0.7) : Colors.grey,
        ),
        const SizedBox(width: 5),
        Text(
          '★ ★ ★ ★',
          style: TextStyle(
            color: mine ? onPrimary : Colors.grey.shade700,
            letterSpacing: 2,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final myId = session.spouseId;
    // The app-wide privacy mask (see DECISIONS.md) masks chat the same
    // way the chat-local eye toggle already did -- either one hides
    // everything (text/photo/video alike) behind the same placeholder.
    final hidden = _hidden || session.privacyMask;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'মেসেজ খুঁজুন...',
                  border: InputBorder.none,
                ),
                onSubmitted: _runSearch,
              )
            : const Text('চ্যাট'),
        leading: _searching
            ? IconButton(icon: const Icon(Iconsax.arrow_left_2), onPressed: _closeSearch)
            : null,
        actions: _searching
            ? [
                IconButton(
                  icon: const Icon(Iconsax.search_normal_1),
                  onPressed: () => _runSearch(_searchController.text),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Iconsax.gallery),
                  tooltip: 'গ্যালারি',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatGalleryScreen()),
                  ),
                ),
                IconButton(icon: const Icon(Iconsax.search_normal_1), onPressed: _openSearch),
                Consumer<SessionProvider>(
                  builder: (context, session, _) => IconButton(
                    icon: Icon(
                      session.intimateMode ? Iconsax.moon_copy : Iconsax.moon,
                      color: session.intimateMode ? AppColors.intimateBlue : null,
                    ),
                    tooltip: session.intimateMode
                        ? 'গোপন মুহূর্তের মোড বন্ধ করুন'
                        : 'গোপন মুহূর্তের মোড চালু করুন',
                    onPressed: session.toggleIntimateMode,
                  ),
                ),
                IconButton(
                  icon: Icon(_hidden ? Iconsax.eye_slash : Iconsax.eye),
                  tooltip: _hidden ? 'মেসেজ দেখান' : 'মেসেজ লুকান (শুধু এই ফোনে)',
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ],
      ),
      body: _searching
          ? _buildSearchResults()
          : Column(
              children: [
                Expanded(
                  child: _loading
                      ? const ShimmerTileList()
                      : ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _itemPositionsListener,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final msg = _messages[i];
                            final mine = msg.senderId == myId;
                            final isMedia =
                                msg.contentType == 'photo' ||
                                msg.contentType == 'video';
                            final showDateDivider =
                                i == 0 ||
                                !_isSameDay(
                                  _messages[i - 1].createdAt.toLocal(),
                                  msg.createdAt.toLocal(),
                                );
                            final bubble = Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.85)
                                : Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hidden)
                                _hiddenPlaceholder(mine)
                              else if (msg.contentType == 'text')
                                Text(
                                  msg.decryptedText ?? '',
                                  style: TextStyle(
                                    color: mine
                                        ? Theme.of(context).colorScheme.onPrimary
                                        : null,
                                  ),
                                )
                              else if (msg.contentType == 'photo' &&
                                  msg.mediaAssetId != null)
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MediaViewerScreen(
                                        assetId: msg.mediaAssetId!,
                                        contentType: 'photo',
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      height: 180,
                                      width: 180,
                                      child: DecryptedFullImage(
                                        assetId: msg.mediaAssetId!,
                                        fit: BoxFit.cover,
                                        zoomable: false,
                                      ),
                                    ),
                                  ),
                                )
                              else if (msg.contentType == 'video' &&
                                  msg.mediaAssetId != null)
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MediaViewerScreen(
                                        assetId: msg.mediaAssetId!,
                                        contentType: 'video',
                                      ),
                                    ),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox(
                                          height: 180,
                                          width: 180,
                                          child: DecryptedThumbnail(
                                            assetId: msg.mediaAssetId!,
                                            hasThumbnail: msg.mediaHasThumbnail,
                                            isVideo: true,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Iconsax.play_circle_copy,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ],
                                  ),
                                )
                              else if (msg.contentType == 'voice' &&
                                  msg.mediaAssetId != null)
                                DecryptedVoicePlayer(
                                  assetId: msg.mediaAssetId!,
                                  color: mine
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.primary,
                                )
                              else
                                Text(
                                  '[${msg.contentType}]',
                                  style: TextStyle(
                                    color: mine
                                        ? Theme.of(context).colorScheme.onPrimary
                                        : null,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    DateFormat.jm().format(
                                      msg.createdAt.toLocal(),
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mine && !isMedia
                                          ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)
                                          : Colors.grey,
                                    ),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 4),
                                    _seenTick(msg),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDateDivider) _DateDivider(date: msg.createdAt.toLocal()),
                          bubble,
                        ],
                      );
                    },
                  ),
          ),
          if (_loadingMoreHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_sending) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: _recording ? _buildRecordingBar() : _buildNormalInputBar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalInputBar() {
    return Row(
      children: [
        PopupMenuButton<String>(
          icon: const Icon(Iconsax.add_circle),
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
          icon: const Icon(Iconsax.microphone),
          onPressed: _startRecording,
        ),
        Expanded(
          child: TextField(
            controller: _textController,
            decoration: const InputDecoration(hintText: 'লিখুন...'),
            onSubmitted: (_) => _sendText(),
          ),
        ),
        IconButton(
          icon: Icon(Iconsax.send, color: Theme.of(context).colorScheme.primary),
          onPressed: _sendText,
        ),
      ],
    );
  }

  Widget _buildRecordingBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Iconsax.trash, color: AppColors.rejected),
          tooltip: 'বাতিল করুন',
          onPressed: _cancelRecording,
        ),
        Expanded(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(21),
            ),
            child: Row(
              children: [
                Icon(
                  Iconsax.record,
                  color: _paused ? Colors.grey : Colors.red,
                  size: 12,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WaveformBars(
                    levels: _waveform,
                    color: _paused ? Colors.grey : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmtDuration(_recordDuration),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            _paused ? Iconsax.play_circle_copy : Iconsax.pause_circle_copy,
            color: Theme.of(context).colorScheme.primary,
          ),
          tooltip: _paused ? 'আবার শুরু করুন' : 'থামান',
          onPressed: _togglePause,
        ),
        IconButton(
          icon: Icon(Iconsax.send, color: Theme.of(context).colorScheme.primary),
          tooltip: 'পাঠান',
          onPressed: _finishAndSendRecording,
        ),
      ],
    );
  }
}

/// A centered pill showing "আজ" / "গতকাল" / the actual date, inserted
/// between messages sent on different days -- makes it possible to tell
/// where you are while scrolling back through a long history. See
/// DECISIONS.md.
class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'আজ';
    if (diff == 1) return 'গতকাল';
    return DateFormat.yMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _label(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

/// Small live waveform made of simple bars driven by the recorder's
/// amplitude stream -- WhatsApp-style visual feedback that recording is
/// actually picking up sound. See DECISIONS.md.
class _WaveformBars extends StatelessWidget {
  final List<double> levels;
  final Color color;
  const _WaveformBars({required this.levels, required this.color});

  @override
  Widget build(BuildContext context) {
    final shown = levels.length > 24
        ? levels.sublist(levels.length - 24)
        : levels;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final level in shown) ...[
          Container(
            width: 3,
            height: 4 + level * 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}
