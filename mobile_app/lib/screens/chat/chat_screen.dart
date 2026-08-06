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
import '../../widgets/linkified_text.dart';
import '../../widgets/reaction_bar.dart';
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

  // Shows a floating "jump to latest" button once the user has scrolled up
  // away from the bottom of the conversation. See DECISIONS.md.
  bool _showScrollToBottom = false;

  // Long-press a message -> react to it, WhatsApp/Telegram-style. Reuses
  // the same generic Reaction system vault entries/comments already use
  // (target_type='chat_message' was always a valid type server-side, just
  // never wired up in the chat UI). One GlobalKey per message so its
  // ReactionList can be told to reload after adding one, without
  // rebuilding the whole message list. See DECISIONS.md.
  final Map<String, GlobalKey<ReactionListState>> _reactionKeys = {};
  GlobalKey<ReactionListState> _reactionKeyFor(String messageId) =>
      _reactionKeys.putIfAbsent(messageId, () => GlobalKey<ReactionListState>());

  // Swipe-right-to-reply target -- shown as a preview bar above the input
  // and quoted inside whatever gets sent next. See DECISIONS.md.
  ChatMessageModel? _replyingTo;

  // WhatsApp-style voice recording state.
  bool _recording = false;
  bool _paused = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<double> _waveform = [];

  // Real-time "টাইপ করছেন"/"ভয়েস রেকর্ড করছেন" indicator for the OTHER
  // spouse -- driven by periodic WS pings sent while this device is
  // composing text (throttled) or recording voice, and auto-cleared a few
  // seconds after the last incoming ping if no new one arrives (no
  // explicit "stopped" event needed, same pattern WhatsApp/Telegram use).
  // See DECISIONS.md.
  String? _peerTypingKind; // null | 'text' | 'voice'
  Timer? _peerTypingClearTimer;
  DateTime? _lastTypingPingSentAt;
  Timer? _recordingPingTimer;

  @override
  void initState() {
    super.initState();
    WsClient.instance.connect();
    _load();
    _wsSub = WsClient.instance.events.listen(_onWsEvent);
    _itemPositionsListener.itemPositions.addListener(_onScrollPositionsChanged);
    _textController.addListener(_onComposingChanged);
  }

  /// Pings the other spouse that this device is actively typing --
  /// throttled to at most once every 2 seconds so every keystroke doesn't
  /// spam the WS connection. See DECISIONS.md.
  void _onComposingChanged() {
    if (_textController.text.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingPingSentAt != null &&
        now.difference(_lastTypingPingSentAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastTypingPingSentAt = now;
    WsClient.instance.send({'type': 'typing', 'kind': 'text'});
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
  /// Also tracks whether the very last message is currently on screen, to
  /// show/hide the floating "jump to latest" button. See DECISIONS.md.
  void _onScrollPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final indices = positions.map((p) => p.index);
    final topIndex = indices.reduce((a, b) => a < b ? a : b);
    final bottomIndex = indices.reduce((a, b) => a > b ? a : b);
    if (topIndex <= 2) _loadMoreHistory();
    final atBottom = _messages.isEmpty || bottomIndex >= _messages.length - 1;
    if (atBottom == _showScrollToBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }
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
    if (data['type'] == 'typing') {
      final kind = data['kind'] as String? ?? 'text';
      _peerTypingClearTimer?.cancel();
      if (mounted) setState(() => _peerTypingKind = kind);
      _peerTypingClearTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _peerTypingKind = null);
      });
      return;
    }
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
      // The message just arrived, so whatever "typing"/"recording voice"
      // indicator was showing for them is stale now -- clear it instead
      // of waiting out the timeout.
      if (isNewIncoming) {
        _peerTypingClearTimer?.cancel();
        _peerTypingKind = null;
      }
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
    if (_showScrollToBottom) setState(() => _showScrollToBottom = false);
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
    final replyToId = _replyingTo?.id;
    _textController.clear();
    setState(() => _replyingTo = null);
    await _chatService.sendTextViaWs(vmk, text, replyToId: replyToId);
    ChatSoundService.playSent();
  }

  Future<void> _sendMediaFile(
    String contentType,
    String kind,
    File file,
  ) async {
    final replyToId = _replyingTo?.id;
    setState(() {
      _sending = true;
      _replyingTo = null;
    });
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
        replyToId: replyToId,
      );
      if (mounted) setState(() => _messages.add(msg));
      _scrollToBottom();
      ChatSoundService.playSent();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Swipe-right-to-reply, WhatsApp/Telegram-style -- sets the message
  /// being replied to, which shows a preview bar above the input and gets
  /// quoted inside the next message sent. See DECISIONS.md.
  void _startReply(ChatMessageModel msg) {
    setState(() => _replyingTo = msg);
  }

  /// A short one-line description of a message for the reply preview
  /// bar / quoted-in-bubble snippet -- decrypted text if it's a text
  /// message, otherwise a Bengali label for the content type.
  String _previewFor(ChatMessageModel msg) {
    switch (msg.contentType) {
      case 'text':
        return msg.decryptedText ?? '';
      case 'photo':
        return '📷 ছবি';
      case 'video':
        return '🎥 ভিডিও';
      case 'voice':
        return '🎤 ভয়েস মেসেজ';
      default:
        return '📎 ফাইল';
    }
  }

  /// The message a given reply is quoting, if it's still in the currently
  /// loaded window -- older messages outside the loaded page just show a
  /// generic quote instead of fetching separately, to keep this simple.
  ChatMessageModel? _repliedMessage(String? replyToId) {
    if (replyToId == null) return null;
    for (final m in _messages) {
      if (m.id == replyToId) return m;
    }
    return null;
  }

  void _scrollToMessageId(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
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
    // Let the other spouse know a voice message is being recorded, live --
    // same periodic-ping pattern as text typing, just its own `kind` so
    // the indicator reads differently. See DECISIONS.md.
    WsClient.instance.send({'type': 'typing', 'kind': 'voice'});
    _recordingPingTimer?.cancel();
    _recordingPingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      WsClient.instance.send({'type': 'typing', 'kind': 'voice'});
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
    _recordingPingTimer?.cancel();
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
    _recordingPingTimer?.cancel();
    _peerTypingClearTimer?.cancel();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _itemPositionsListener.itemPositions.removeListener(_onScrollPositionsChanged);
    _textController.removeListener(_onComposingChanged);
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
    // Chat's own local eye toggle has full, independent authority here --
    // deliberately has NO relationship to the home screen's global privacy
    // mask in either direction. See DECISIONS.md.
    final hidden = _hidden;
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
                      : Stack(
                          children: [
                            ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _itemPositionsListener,
                          // Land exactly on the newest message on first
                          // open -- without this the list defaults to
                          // index 0 (the oldest loaded message) for its
                          // very first frame, which was long enough for
                          // `_onScrollPositionsChanged` to see the top of
                          // the list and prematurely trigger
                          // `_loadMoreHistory()` before the animated
                          // scroll-to-bottom in `_load()` ever got a
                          // chance to run -- that history prepend's own
                          // `jumpTo()` then won the race, landing
                          // somewhere in the middle of the conversation
                          // instead of the latest message. See
                          // DECISIONS.md.
                          initialScrollIndex: _messages.isEmpty ? 0 : _messages.length - 1,
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
                        child: GestureDetector(
                        onLongPress: () => openReactionSheet(
                          context,
                          targetType: 'chat_message',
                          targetId: msg.id,
                          onChanged: () => _reactionKeyFor(msg.id).currentState?.reload(),
                        ),
                        // A quick rightward flick anywhere on the bubble
                        // starts a reply to it -- WhatsApp/Telegram-style
                        // swipe-to-reply. See DECISIONS.md.
                        onHorizontalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 250) _startReply(msg);
                        },
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
                              if (!hidden && msg.replyToId != null)
                                _QuotedReply(
                                  message: _repliedMessage(msg.replyToId),
                                  mine: mine,
                                  preview: _repliedMessage(msg.replyToId) != null
                                      ? _previewFor(_repliedMessage(msg.replyToId)!)
                                      : 'মূল মেসেজ',
                                  onTap: () => _scrollToMessageId(msg.replyToId!),
                                ),
                              if (hidden)
                                _hiddenPlaceholder(mine)
                              else if (msg.contentType == 'text')
                                LinkifiedText(
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
                                        forceShow: true,
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
                                            forceShow: true,
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
                        ),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDateDivider) _DateDivider(date: msg.createdAt.toLocal()),
                          bubble,
                          Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: ReactionList(
                                key: _reactionKeyFor(msg.id),
                                targetType: 'chat_message',
                                targetId: msg.id,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                            if (_showScrollToBottom)
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: FloatingActionButton.small(
                                  heroTag: 'scrollToBottom',
                                  onPressed: _scrollToBottom,
                                  child: const Icon(Iconsax.arrow_down_1),
                                ),
                              ),
                          ],
                        ),
          ),
          if (_loadingMoreHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_sending) const LinearProgressIndicator(),
          if (_peerTypingKind != null) _buildPeerTypingIndicator(),
          if (_replyingTo != null) _buildReplyPreviewBar(),
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

  /// Live "সঙ্গী টাইপ করছেন" / "সঙ্গী ভয়েস রেকর্ড করছেন" row, driven by the
  /// periodic WS pings in `_onComposingChanged`/`_startRecording` on the
  /// OTHER device. See DECISIONS.md.
  Widget _buildPeerTypingIndicator() {
    final isVoice = _peerTypingKind == 'voice';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVoice ? Iconsax.microphone : Iconsax.edit_2,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            isVoice ? 'সঙ্গী ভয়েস রেকর্ড করছেন...' : 'সঙ্গী টাইপ করছেন...',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Shows what's about to be replied to, above the input bar, with a way
  /// to cancel it -- the swipe gesture just sets `_replyingTo`, this is
  /// what makes that state visible before actually sending. See
  /// DECISIONS.md.
  Widget _buildReplyPreviewBar() {
    final target = _replyingTo!;
    final myId = context.read<SessionProvider>().spouseId;
    final mine = target.senderId == myId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mine ? 'নিজের মেসেজের উত্তর' : 'সঙ্গীর মেসেজের উত্তর',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  _previewFor(target),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Iconsax.close_circle, size: 20),
            onPressed: () => setState(() => _replyingTo = null),
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
/// The small quoted-message box shown at the top of a bubble that's
/// replying to another one -- tap it to jump back to the original. See
/// DECISIONS.md.
class _QuotedReply extends StatelessWidget {
  final ChatMessageModel? message;
  final String preview;
  final bool mine;
  final VoidCallback onTap;
  const _QuotedReply({
    required this.message,
    required this.preview,
    required this.mine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = mine
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.primary;
    final textColor = mine
        ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.85)
        : Colors.grey.shade700;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: (mine ? Colors.black : Colors.white).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: barColor, width: 3)),
        ),
        child: Text(
          preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: textColor),
        ),
      ),
    );
  }
}

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
