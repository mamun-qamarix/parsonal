import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../services/profile_cache.dart';
import '../../services/social_service.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/linkified_text.dart';
import '../../widgets/match_celebration_overlay.dart';
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
  final _textController = _MaskableTextController();
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
  // While privacy mode is on, the ids of the individual messages the user
  // has tapped the eye on to show -- everything else stays masked. Cleared
  // every time privacy mode is toggled. See DECISIONS.md #56.
  final Set<String> _revealed = {};

  // Header + pinned message state (DECISIONS.md #56).
  ChatMessageModel? _pinned;
  bool _partnerOnline = false;
  DateTime? _partnerLastSeen;
  String? _partnerName;
  bool _hasText = false;

  // Shows a floating "jump to latest" button once the user has scrolled up
  // away from the bottom of the conversation. See DECISIONS.md.
  bool _showScrollToBottom = false;

  // Long-press a message -> react to it, WhatsApp/Telegram-style. Reuses
  // the same generic Reaction system vault entries/comments already use
  // (target_type='chat_message' was always a valid type server-side, just
  // never wired up in the chat UI). Each message's ReactionList is told to
  // reload after adding one, without rebuilding the whole message list.
  // See DECISIONS.md.
  // A plain notifier per message, NOT a GlobalKey: ScrollablePositionedList
  // renders the same item in two internal lists while scrolling, and a
  // GlobalKey used twice crashed the whole tree (repeating every frame).
  final Map<String, ValueNotifier<int>> _reactionRefresh = {};
  ValueNotifier<int> _reactionRefreshFor(String messageId) =>
      _reactionRefresh.putIfAbsent(messageId, () => ValueNotifier<int>(0));

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
    _textController.addListener(_onTextChanged);
    _loadPin();
    _loadPartnerStatus();
    _loadPartnerName();
  }

  void _onTextChanged() {
    final has = _textController.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
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
    final fetched = await _chatService.getHistory(vmk, limit: _pageSize);
    // Defensive: one entry per message id (see the GlobalKey note in
    // _buildMessageList's reaction row).
    final seen = <String>{};
    final messages = fetched.where((m) => seen.add(m.id)).toList();
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
    final List<ChatMessageModel> older;
    try {
      older = await _chatService.getHistory(
        vmk,
        before: _messages.first.id,
        limit: _pageSize,
      );
    } catch (_) {
      // Offline / transient failure -- let the next scroll to the top retry
      // instead of leaving the "loading older" flag stuck on.
      if (mounted) setState(() => _loadingMoreHistory = false);
      return;
    }
    if (!mounted) return;
    final have = _messages.map((m) => m.id).toSet();
    older.removeWhere((m) => have.contains(m.id));
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
    if (data['type'] == 'presence') {
      if (!mounted) return;
      setState(() {
        _partnerOnline = data['online'] == true;
        if (!_partnerOnline)
          _partnerLastSeen =
              DateTime.tryParse(data['at'] as String? ?? '') ?? DateTime.now();
      });
      return;
    }
    if (data['type'] == 'chat_pin') {
      final id = data['message_id'] as String?;
      if (id == null) {
        if (mounted) setState(() => _pinned = null);
      } else if (_pinned?.id != id) {
        final local = _messages.where((m) => m.id == id);
        if (local.isNotEmpty) {
          if (mounted) setState(() => _pinned = local.first);
        } else {
          _loadPin();
        }
      }
      return;
    }
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
        _partnerOnline = true;
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
      final have = _messages.map((m) => m.id).toSet();
      final fresh = older.where((m) => !have.contains(m.id)).toList();
      setState(() {
        _messages = [...fresh, ..._messages];
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
      if (mounted) {
        // The server's websocket echo of this same message may have
        // already added it -- never list one id twice (duplicate ids
        // share a GlobalKey for the reaction row and crash the build).
        setState(() {
          if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
        });
      }
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
    for (final n in _reactionRefresh.values) {
      n.dispose();
    }
    _wsSub?.cancel();
    _recordTimer?.cancel();
    _recordingPingTimer?.cancel();
    _peerTypingClearTimer?.cancel();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _itemPositionsListener.itemPositions.removeListener(
      _onScrollPositionsChanged,
    );
    _textController.removeListener(_onComposingChanged);
    _textController.removeListener(_onTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildSearchResults() {
    if (_searchLoading) {
      return const ShimmerTileList(count: 5);
    }
    if (_searchController.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'একটা শব্দ বা লাইন লিখে সার্চ করুন।',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _searchStatus ?? 'কিছু পাওয়া যায়নি।',
          style: const TextStyle(color: Colors.grey),
        ),
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
        final shown = _isRevealed(msg);
        return ListTile(
          leading: const Icon(Iconsax.message_2),
          trailing: _hidden
              ? _EyeButton(
                  revealed: shown,
                  color: const Color(0xFFE6EEE9),
                  onTap: () => _toggleReveal(msg.id),
                )
              : null,
          title: !shown
              ? const Text('• • • •')
              : matchIndex < 0
              ? Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)
              : _highlightedSnippet(text, matchIndex, query.length),
          subtitle: Text(
            DateFormat.yMMMd().add_jm().format(msg.createdAt.toLocal()),
          ),
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
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0x552F9E63),
            ),
          ),
          TextSpan(
            text: '${text.substring(matchIndex + matchLength, end)}$suffix',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // "Modern messenger" UI (DECISIONS.md #56): partner header with live
  // presence, a shared pinned message, rounded bubbles grouped by sender,
  // per-message eye buttons in privacy mode, quick replies, a long-press
  // action sheet, and a single pill-shaped composer.
  // ---------------------------------------------------------------------

  Widget _seenTick(ChatMessageModel msg) {
    if (msg.readAt != null) {
      return const Icon(
        Icons.done_all_rounded,
        size: 14,
        color: AppColors.mint,
      );
    }
    return Icon(
      msg.deliveredAt != null ? Icons.done_all_rounded : Icons.done_rounded,
      size: 14,
      color: Colors.white.withValues(alpha: 0.6),
    );
  }

  bool _isRevealed(ChatMessageModel msg) =>
      !_hidden || _revealed.contains(msg.id);

  /// Same reveal state, for things that aren't a message (the partner's
  /// name, a quick-reply chip, a search result) -- keyed by a string.
  bool _isKeyRevealed(String key) => !_hidden || _revealed.contains(key);

  void _toggleReveal(String id) {
    setState(() {
      if (!_revealed.remove(id)) _revealed.add(id);
    });
  }

  void _togglePrivacy() {
    setState(() {
      _hidden = !_hidden;
      _textController.masked = _hidden;
      // Everything starts hidden again each time privacy mode is switched
      // on -- a reveal never "sticks" across sessions.
      _revealed.clear();
    });
  }

  String _lastSeenLabel(DateTime t) {
    final local = t.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'এইমাত্র দেখেছে';
    if (diff.inMinutes < 60) return '${diff.inMinutes} মিনিট আগে দেখেছে';
    if (_isSameDay(local, DateTime.now()))
      return 'আজ ${DateFormat.jm().format(local)} এ দেখেছে';
    return '${DateFormat.MMMd().format(local)} এ দেখেছে';
  }

  Widget _buildHeaderTitle(SessionProvider session) {
    final partnerRole = session.otherRole;
    final partnerColor = partnerRole == 'wife'
        ? AppColors.wife
        : AppColors.husband;
    final name = _partnerName ?? (partnerRole == 'wife' ? 'স্ত্রী' : 'স্বামী');
    String status;
    Color statusColor = AppColors.muted;
    if (_peerTypingKind != null) {
      status = _peerTypingKind == 'voice' ? 'ভয়েস রেকর্ড করছে…' : 'লিখছে…';
      statusColor = AppColors.mint;
    } else if (_partnerOnline) {
      status = 'অনলাইন';
      statusColor = AppColors.mint;
    } else if (_partnerLastSeen != null) {
      status = _lastSeenLabel(_partnerLastSeen!);
    } else {
      status = '';
    }
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: partnerColor,
              child: _isKeyRevealed('name')
                  ? Text(
                      name.characters.first,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : const Icon(
                      Iconsax.lock_1_copy,
                      size: 16,
                      color: Colors.white,
                    ),
            ),
            if (_partnerOnline)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.halalGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _isKeyRevealed('name') ? name : '• • • •',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_hidden)
                    _EyeButton(
                      revealed: _isKeyRevealed('name'),
                      color: const Color(0xFFE6EEE9),
                      onTap: () => _toggleReveal('name'),
                    ),
                ],
              ),
              if (status.isNotEmpty)
                Text(
                  status,
                  maxLines: 1,
                  style: TextStyle(fontSize: 11.5, color: statusColor),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedBar() {
    final pin = _pinned!;
    final shown = _isRevealed(pin) ? _previewFor(pin) : '• • • •';
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => _scrollToMessageId(pin.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.line, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Iconsax.attach_square_copy,
                size: 16,
                color: AppColors.mint,
              ),
              const SizedBox(width: 8),
              const Text(
                'পিন',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mint,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (_hidden)
                _EyeButton(
                  revealed: _isRevealed(pin),
                  color: const Color(0xFFE6EEE9),
                  onTap: () => _toggleReveal(pin.id),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.muted,
                ),
                tooltip: 'আনপিন',
                onPressed: () => _setPin(null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setPin(ChatMessageModel? msg) async {
    final before = _pinned;
    setState(() => _pinned = msg);
    try {
      await _chatService.setPin(msg?.id);
    } catch (_) {
      if (mounted) setState(() => _pinned = before);
    }
  }

  Future<void> _loadPin() async {
    try {
      final vmk = context.read<SessionProvider>().vmk!;
      final p = await _chatService.getPin(vmk);
      if (mounted) setState(() => _pinned = p);
    } catch (_) {}
  }

  Future<void> _loadPartnerStatus() async {
    try {
      final s = await _chatService.partnerStatus();
      if (mounted) {
        setState(() {
          _partnerOnline = s.online;
          _partnerLastSeen = s.lastSeen;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPartnerName() async {
    try {
      final session = context.read<SessionProvider>();
      final p = await ProfileCache.instance.get(
        session.vmk!,
        session.otherRole,
      );
      final n = p?.decryptedName;
      if (mounted && n != null && n.trim().isNotEmpty)
        setState(() => _partnerName = n.trim());
    } catch (_) {}
  }

  /// Long-press menu: one-tap reactions, reply, copy, pin, show/hide.
  void _showMessageActions(ChatMessageModel msg) {
    const quick = ['❤️', '😍', '😂', '👍', '🥰', '😢'];
    final isPinned = _pinned?.id == msg.id;
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final e in quick)
                    InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () async {
                        Navigator.pop(sheetCtx);
                        final matched = await SocialService().addReaction(
                          'chat_message',
                          msg.id,
                          e,
                        );
                        _reactionRefreshFor(msg.id).value++;
                        if (matched && mounted) showMatchCelebration(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      openReactionSheet(
                        context,
                        targetType: 'chat_message',
                        targetId: msg.id,
                        onChanged: () => _reactionRefreshFor(msg.id).value++,
                      );
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(),
              _actionTile(
                sheetCtx,
                Iconsax.undo_copy,
                'উত্তর দিন',
                () => _startReply(msg),
              ),
              if (msg.contentType == 'text' &&
                  (msg.decryptedText ?? '').isNotEmpty &&
                  _isRevealed(msg))
                _actionTile(sheetCtx, Iconsax.copy_copy, 'কপি করুন', () {
                  Clipboard.setData(ClipboardData(text: msg.decryptedText!));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('কপি হয়েছে')));
                }),
              if (msg.contentType == 'text' &&
                  (msg.decryptedText ?? '').isNotEmpty &&
                  _isRevealed(msg))
                _actionTile(
                  sheetCtx,
                  Iconsax.text_block_copy,
                  'সিলেক্ট করে কপি',
                  () => _openSelectableText(msg),
                ),
              _actionTile(
                sheetCtx,
                Iconsax.attach_square_copy,
                isPinned ? 'আনপিন করুন' : 'পিন করুন',
                () => _setPin(isPinned ? null : msg),
              ),
              if (_hidden)
                _actionTile(
                  sheetCtx,
                  _revealed.contains(msg.id)
                      ? Iconsax.eye_slash_copy
                      : Iconsax.eye_copy,
                  _revealed.contains(msg.id)
                      ? 'আবার লুকান'
                      : 'এই মেসেজটা দেখুন',
                  () => _toggleReveal(msg.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the full message text as selectable text, so any part of it can
  /// be selected and copied (long-press on the bubble itself opens the
  /// action menu, so selection lives here instead).
  void _openSelectableText(ChatMessageModel msg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'যতটুকু দরকার চেপে ধরে সিলেক্ট করুন, তারপর কপি করুন',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      msg.decryptedText ?? '',
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: msg.decryptedText ?? ''),
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('পুরোটা কপি হয়েছে')),
                    );
                  },
                  icon: const Icon(Iconsax.copy_copy, size: 18),
                  label: const Text('পুরোটা কপি করুন'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext sheetCtx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      onTap: () {
        Navigator.pop(sheetCtx);
        onTap();
      },
    );
  }

  Widget _maskedText(bool mine, String id) {
    final c = mine ? Colors.white : const Color(0xFFE6EEE9);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Iconsax.lock_1_copy, size: 13, color: c.withValues(alpha: 0.65)),
        const SizedBox(width: 6),
        Text(
          '• • • •',
          style: TextStyle(
            color: c.withValues(alpha: 0.85),
            letterSpacing: 2,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 4),
        _EyeButton(revealed: false, color: c, onTap: () => _toggleReveal(id)),
      ],
    );
  }

  Widget _maskedMedia(ChatMessageModel msg) {
    final label = switch (msg.contentType) {
      'photo' => 'ছবি লুকানো',
      'video' => 'ভিডিও লুকানো',
      _ => 'লুকানো',
    };
    return GestureDetector(
      onTap: () => _toggleReveal(msg.id),
      child: Container(
        width: 180,
        height: 130,
        decoration: BoxDecoration(
          color: const Color(0xFF24332B),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    msg.contentType == 'video'
                        ? Iconsax.video_slash_copy
                        : Iconsax.gallery_slash_copy,
                    color: AppColors.muted,
                    size: 26,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: _EyeButton(
                revealed: false,
                color: Colors.white,
                filled: true,
                onTap: () => _toggleReveal(msg.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaContent(ChatMessageModel msg) {
    final isVideo = msg.contentType == 'video';
    final media = GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            assetId: msg.mediaAssetId!,
            contentType: msg.contentType,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 200,
          width: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              isVideo
                  ? DecryptedThumbnail(
                      assetId: msg.mediaAssetId!,
                      hasThumbnail: msg.mediaHasThumbnail,
                      isVideo: true,
                      fit: BoxFit.cover,
                      forceShow: true,
                    )
                  : DecryptedFullImage(
                      assetId: msg.mediaAssetId!,
                      fit: BoxFit.cover,
                      zoomable: false,
                      forceShow: true,
                    ),
              if (isVideo)
                const Center(
                  child: Icon(
                    Iconsax.play_circle_copy,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!_hidden) return media;
    return Stack(
      children: [
        media,
        Positioned(
          top: 6,
          right: 6,
          child: _EyeButton(
            revealed: true,
            color: Colors.white,
            filled: true,
            onTap: () => _toggleReveal(msg.id),
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(
    ChatMessageModel msg, {
    required bool mine,
    required bool groupedWithPrev,
    required Color mineColor,
  }) {
    final revealed = _isRevealed(msg);
    final isMedia =
        (msg.contentType == 'photo' || msg.contentType == 'video') &&
        msg.mediaAssetId != null;
    final fg = mine ? Colors.white : const Color(0xFFE6EEE9);
    final metaColor = mine
        ? Colors.white.withValues(alpha: 0.65)
        : AppColors.muted;

    Widget content;
    if (!revealed) {
      content = isMedia ? _maskedMedia(msg) : _maskedText(mine, msg.id);
    } else if (msg.contentType == 'text') {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: LinkifiedText(
              msg.decryptedText ?? '',
              style: TextStyle(color: fg, fontSize: 14.5, height: 1.35),
            ),
          ),
          if (_hidden) ...[
            const SizedBox(width: 4),
            _EyeButton(
              revealed: true,
              color: fg,
              onTap: () => _toggleReveal(msg.id),
            ),
          ],
        ],
      );
    } else if (isMedia) {
      content = _mediaContent(msg);
    } else if (msg.contentType == 'voice' && msg.mediaAssetId != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: DecryptedVoicePlayer(
              assetId: msg.mediaAssetId!,
              color: mine ? Colors.white : AppColors.mint,
            ),
          ),
          if (_hidden)
            _EyeButton(
              revealed: true,
              color: fg,
              onTap: () => _toggleReveal(msg.id),
            ),
        ],
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.document_copy, size: 18, color: fg),
          const SizedBox(width: 6),
          Text('ফাইল', style: TextStyle(color: fg)),
        ],
      );
    }

    final radius = BorderRadius.only(
      topLeft: Radius.circular(!mine && groupedWithPrev ? 6 : 18),
      topRight: Radius.circular(mine && groupedWithPrev ? 6 : 18),
      bottomLeft: Radius.circular(mine ? 18 : 6),
      bottomRight: Radius.circular(mine ? 6 : 18),
    );
    final quoted = _repliedMessage(msg.replyToId);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.selectionClick();
          _showMessageActions(msg);
        },
        // Quick rightward flick = reply, WhatsApp/Telegram-style.
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 250) _startReply(msg);
        },
        child: Container(
          margin: EdgeInsets.only(top: groupedWithPrev ? 2 : 8),
          padding: isMedia && revealed
              ? const EdgeInsets.all(4)
              : const EdgeInsets.fromLTRB(12, 8, 12, 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          decoration: BoxDecoration(
            color: mine ? mineColor : AppColors.bubbleTheirs,
            borderRadius: radius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (revealed && msg.replyToId != null)
                _QuotedReply(
                  mine: mine,
                  preview: quoted != null ? _previewFor(quoted) : 'মূল মেসেজ',
                  onTap: () => _scrollToMessageId(msg.replyToId!),
                ),
              content,
              Padding(
                padding: EdgeInsets.only(
                  top: 3,
                  right: isMedia && revealed ? 6 : 0,
                  bottom: isMedia && revealed ? 2 : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_pinned?.id == msg.id) ...[
                      Icon(
                        Iconsax.attach_square_copy,
                        size: 11,
                        color: metaColor,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      DateFormat.jm().format(msg.createdAt.toLocal()),
                      style: TextStyle(fontSize: 10.5, color: metaColor),
                    ),
                    if (mine) ...[const SizedBox(width: 3), _seenTick(msg)],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final myId = session.spouseId;
    final mineColor = session.intimateMode
        ? AppColors.bubbleMineIntimate
        : AppColors.bubbleMine;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 0,
        shape: const Border(
          bottom: BorderSide(color: AppColors.line, width: 0.5),
        ),
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'মেসেজ খুঁজুন…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onSubmitted: _runSearch,
              )
            : _buildHeaderTitle(session),
        leading: _searching
            ? IconButton(
                icon: const Icon(Iconsax.arrow_left_2),
                onPressed: _closeSearch,
              )
            : (Navigator.of(context).canPop() ? const BackButton() : null),
        actions: _searching
            ? [
                IconButton(
                  icon: const Icon(Iconsax.search_normal_1_copy),
                  onPressed: () => _runSearch(_searchController.text),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Iconsax.gallery_copy, size: 21),
                  tooltip: 'চ্যাট গ্যালারি',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ChatGalleryScreen(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _hidden ? Iconsax.eye_slash_copy : Iconsax.eye_copy,
                    size: 21,
                    color: _hidden ? AppColors.mint : null,
                  ),
                  tooltip: _hidden
                      ? 'প্রাইভেসি মোড বন্ধ করুন'
                      : 'প্রাইভেসি মোড (শুধু এই ফোনে)',
                  onPressed: _togglePrivacy,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) {
                    if (v == 'search') _openSearch();
                    if (v == 'intimate') session.toggleIntimateMode();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'search',
                      child: Row(
                        children: [
                          Icon(Iconsax.search_normal_1_copy, size: 18),
                          SizedBox(width: 10),
                          Text('মেসেজ খুঁজুন'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'intimate',
                      child: Row(
                        children: [
                          Icon(
                            session.intimateMode
                                ? Iconsax.moon_copy
                                : Iconsax.moon,
                            size: 18,
                            color: session.intimateMode
                                ? AppColors.intimateBlue
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            session.intimateMode
                                ? 'গোপন মুহূর্ত বন্ধ'
                                : 'গোপন মুহূর্তের মোড',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: _searching
          ? _buildSearchResults()
          : Column(
              children: [
                if (_pinned != null) _buildPinnedBar(),
                if (_hidden)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    color: AppColors.mint.withValues(alpha: 0.08),
                    child: const Text(
                      'প্রাইভেসি মোড চালু — প্রতিটা মেসেজের চোখে চাপ দিয়ে দেখুন',
                      style: TextStyle(fontSize: 11.5, color: AppColors.mint),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const ShimmerTileList()
                      : Stack(
                          children: [
                            ScrollablePositionedList.builder(
                              itemScrollController: _itemScrollController,
                              itemPositionsListener: _itemPositionsListener,
                              // Land on the newest message on the very first
                              // frame (see DECISIONS.md #40).
                              initialScrollIndex: _messages.isEmpty
                                  ? 0
                                  : _messages.length - 1,
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                              itemCount: _messages.length,
                              itemBuilder: (context, i) {
                                final msg = _messages[i];
                                final mine = msg.senderId == myId;
                                final prev = i > 0 ? _messages[i - 1] : null;
                                final newDay =
                                    prev == null ||
                                    !_isSameDay(
                                      prev.createdAt.toLocal(),
                                      msg.createdAt.toLocal(),
                                    );
                                final grouped =
                                    !newDay &&
                                    prev.senderId == msg.senderId &&
                                    msg.createdAt
                                            .difference(prev.createdAt)
                                            .inMinutes
                                            .abs() <
                                        3;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (newDay)
                                      _DateDivider(
                                        date: msg.createdAt.toLocal(),
                                      ),
                                    _buildBubble(
                                      msg,
                                      mine: mine,
                                      groupedWithPrev: grouped,
                                      mineColor: mineColor,
                                    ),
                                    if (_isRevealed(msg))
                                      Align(
                                        alignment: mine
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: ReactionList(
                                          key: ValueKey('rx-${msg.id}'),
                                          targetType: 'chat_message',
                                          targetId: msg.id,
                                          refresh: _reactionRefreshFor(msg.id),
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
                                child: Material(
                                  color: AppColors.surfaceHigh,
                                  shape: const CircleBorder(
                                    side: BorderSide(
                                      color: AppColors.line,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _scrollToBottom,
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(
                                        Iconsax.arrow_down_1_copy,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                if (_loadingMoreHistory)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Center(child: ShimmerSpinner(size: 16)),
                  ),
                if (_sending) const LinearProgressIndicator(minHeight: 2),
                if (_replyingTo != null) _buildReplyPreviewBar(),
                if (!_recording && !_hasText && _replyingTo == null)
                  _buildQuickReplies(myId),
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      top: BorderSide(color: AppColors.line, width: 0.5),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: _recording
                          ? _buildRecordingBar()
                          : _buildNormalInputBar(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// One-tap replies, offered when the last message is from your partner
  /// and you haven't started typing.
  Widget _buildQuickReplies(String? myId) {
    if (_messages.isEmpty || _messages.last.senderId == myId)
      return const SizedBox.shrink();
    const replies = ['ঠিক আছে', 'আসছি', 'ইনশাআল্লাহ', 'মাশাআল্লাহ', '❤️'];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        itemCount: replies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final key = 'quick-$i';
          final shown = _isKeyRevealed(key);
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              if (!shown) {
                _toggleReveal(key);
                return;
              }
              final vmk = context.read<SessionProvider>().vmk!;
              await _chatService.sendTextViaWs(vmk, replies[i]);
              ChatSoundService.playSent();
            },
            child: Container(
              padding: EdgeInsets.only(left: 12, right: _hidden ? 4 : 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x24FFFFFF), width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shown ? replies[i] : '• • • •',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (_hidden)
                    _EyeButton(
                      revealed: shown,
                      color: const Color(0xFFE6EEE9),
                      onTap: () => _toggleReveal(key),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReplyPreviewBar() {
    final target = _replyingTo!;
    final myId = context.read<SessionProvider>().spouseId;
    final mine = target.senderId == myId;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mine ? 'নিজের মেসেজের উত্তর' : 'সঙ্গীর মেসেজের উত্তর',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mint,
                  ),
                ),
                Text(
                  _isRevealed(target) ? _previewFor(target) : '• • • •',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (_hidden)
            _EyeButton(
              revealed: _isRevealed(target),
              color: AppColors.muted,
              onTap: () => _toggleReveal(target.id),
            ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.muted,
            ),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  void _openAttachSheet() {
    Widget tile(
      BuildContext ctx,
      IconData icon,
      String label,
      Color color,
      VoidCallback onTap,
    ) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              tile(
                ctx,
                Iconsax.gallery_copy,
                'ছবি',
                AppColors.mint,
                _pickImage,
              ),
              tile(
                ctx,
                Iconsax.video_copy,
                'ভিডিও',
                AppColors.wife,
                _pickVideo,
              ),
              tile(
                ctx,
                Iconsax.camera_copy,
                'ক্যামেরা',
                AppColors.pending,
                _takePhoto,
              ),
              tile(
                ctx,
                Iconsax.document_copy,
                'ফাইল',
                AppColors.husband,
                _pickFile,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (file != null) await _sendMediaFile('photo', 'image', File(file.path));
  }

  Widget _roundAction({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalInputBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    // While chat privacy is on, what's being typed is DRAWN
                    // as dots by _MaskableTextController -- NOT obscureText,
                    // which switches Android to an English-only password
                    // keyboard (no Bangla). See DECISIONS.md #57.
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'মেসেজ…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Iconsax.paperclip_2,
                    size: 21,
                    color: AppColors.muted,
                  ),
                  tooltip: 'সংযুক্ত করুন',
                  onPressed: _openAttachSheet,
                ),
                if (!_hasText)
                  IconButton(
                    icon: const Icon(
                      Iconsax.camera,
                      size: 21,
                      color: AppColors.muted,
                    ),
                    tooltip: 'ক্যামেরা',
                    onPressed: _takePhoto,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _hasText
            ? _roundAction(
                icon: Iconsax.send_1_copy,
                onTap: _sendText,
                tooltip: 'পাঠান',
              )
            : _roundAction(
                icon: Iconsax.microphone_2_copy,
                onTap: _startRecording,
                tooltip: 'ভয়েস মেসেজ',
              ),
      ],
    );
  }

  Widget _buildRecordingBar() {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Iconsax.trash_copy, color: AppColors.rejected),
          tooltip: 'বাতিল করুন',
          onPressed: _cancelRecording,
        ),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.fiber_manual_record_rounded,
                  color: _paused ? Colors.grey : Colors.redAccent,
                  size: 12,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WaveformBars(
                    levels: _waveform,
                    color: _paused ? Colors.grey : AppColors.mint,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmtDuration(_recordDuration),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            _paused ? Iconsax.play_circle_copy : Iconsax.pause_circle_copy,
            color: primary,
          ),
          tooltip: _paused ? 'আবার শুরু করুন' : 'থামান',
          onPressed: _togglePause,
        ),
        _roundAction(
          icon: Iconsax.send_1_copy,
          onTap: _finishAndSendRecording,
          tooltip: 'পাঠান',
        ),
      ],
    );
  }
}

/// Draws its text as dots while [masked] is on, without touching the
/// real value (which is still what gets encrypted and sent) and without
/// obscureText -- so the keyboard stays the user's normal one (Bangla
/// included) instead of Android's English-only password keyboard. One dot
/// per UTF-16 unit keeps cursor/selection offsets identical. DECISIONS.md #57.
class _MaskableTextController extends TextEditingController {
  bool _masked = false;
  bool get masked => _masked;
  set masked(bool v) {
    if (v == _masked) return;
    _masked = v;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_masked) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(style: style, text: '\u2022' * text.length);
  }
}

/// Small eye toggle shown on every message while privacy mode is on --
/// tap to show just that one message, tap again to hide it.
class _EyeButton extends StatelessWidget {
  final bool revealed;
  final Color color;
  final bool filled;
  final VoidCallback onTap;
  const _EyeButton({
    required this.revealed,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      revealed ? Iconsax.eye_slash_copy : Iconsax.eye_copy,
      size: 15,
      color: color.withValues(alpha: 0.85),
    );
    return Semantics(
      button: true,
      label: revealed ? 'মেসেজ লুকান' : 'মেসেজ দেখুন',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: filled
            ? Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Center(child: icon),
              )
            : Padding(padding: const EdgeInsets.all(5), child: icon),
      ),
    );
  }
}

/// The quoted-message box at the top of a reply bubble -- tap it to jump
/// back to the original.
class _QuotedReply extends StatelessWidget {
  final String preview;
  final bool mine;
  final VoidCallback onTap;
  const _QuotedReply({
    required this.preview,
    required this.mine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: (mine ? Colors.black : Colors.white).withValues(
            alpha: mine ? 0.18 : 0.06,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 2.5,
              height: 18,
              decoration: BoxDecoration(
                color: mine ? Colors.white70 : AppColors.mint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "আজ" / "গতকাল" / the date, between messages sent on different days.
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
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _label(),
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
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
