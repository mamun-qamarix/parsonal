import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/chunked_crypto.dart';
import '../../providers/session_provider.dart';
import '../../services/media_service.dart';
import '../../widgets/shimmer_loading.dart';

/// One-time conversion of old videos (single encrypted blob, must be fully
/// downloaded before playing) to the streamable chunked format. Everything
/// happens on this phone: download ciphertext -> decrypt -> re-encrypt in
/// chunks -> upload. The server never sees plaintext, and it keeps the old
/// copy too (media is never deleted). Safe to stop and resume any time --
/// only not-yet-converted videos are listed. See DECISIONS.md.
class VideoMigrationScreen extends StatefulWidget {
  const VideoMigrationScreen({super.key});

  @override
  State<VideoMigrationScreen> createState() => _VideoMigrationScreenState();
}

class _VideoMigrationScreenState extends State<VideoMigrationScreen> {
  final _service = MediaService();
  List<(String, int)>? _pending;
  String? _loadError;
  bool _running = false;
  bool _stopRequested = false;
  int _done = 0;
  int _failed = 0;
  int _index = 0;
  String _stage = '';
  int _received = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final list = await _service.listLegacyVideos();
      if (mounted) setState(() => _pending = list);
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError =
              'তালিকা আনা যায়নি। ইন্টারনেট আছে কিনা, আর সার্ভার আপডেট করা হয়েছে কিনা দেখুন।',
        );
      }
    }
  }

  void _progress(String stage, int received, int total) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _received = received;
      _total = total;
    });
  }

  Future<void> _run() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final list = List.of(_pending ?? const <(String, int)>[]);
    setState(() {
      _running = true;
      _stopRequested = false;
      _done = 0;
      _failed = 0;
    });
    for (var i = 0; i < list.length; i++) {
      if (_stopRequested || !mounted) break;
      final (id, _) = list[i];
      setState(() => _index = i);
      try {
        _progress('ডাউনলোড হচ্ছে', 0, 0);
        // Full download (not range) -- a single range request is capped
        // server-side, and old videos can be up to 1GB.
        final plain = await _service.downloadRaw(
          vmk,
          id,
          onProgress: (r, t) => _progress('ডাউনলোড হচ্ছে', r, t),
        );
        _progress('নতুন ফরম্যাটে এনক্রিপ্ট হচ্ছে...', 1, 1);
        final chunked = await Isolate.run(
          () => ChunkedCrypto.encrypt(vmk, plain),
        );
        try {
          await _service.replaceWithChunked(
            id,
            chunked,
            onSendProgress: (s, t) => _progress('আপলোড হচ্ছে', s, t),
          );
        } on DioException catch (e) {
          // 409 = already converted (e.g. from the other phone) -- fine.
          if (e.response?.statusCode != 409) rethrow;
        }
        _done++;
      } catch (_) {
        _failed++;
      }
    }
    if (!mounted) return;
    setState(() => _running = false);
    await _refresh();
  }

  String _mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final totalBytes = pending?.fold<int>(0, (a, e) => a + e.$2) ?? 0;
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('রূপান্তর চলছে — আগে "থামান" চাপুন'),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ভিডিও স্ট্রিমিং রূপান্তর')),
        body: _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ),
              )
            : pending == null
            ? const ShimmerTileList(count: 3)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'পুরোনো ভিডিওগুলো পুরোটা নামানোর আগে চালু হয় না। একবার রূপান্তর করলে নতুন ভিডিওর মতো সাথে সাথে চলবে। সব কাজ এই ফোনেই হয়, সার্ভার কখনো আসল ভিডিও দেখে না, আর পুরোনো কপিও সার্ভারে রেখে দেওয়া হয়।',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  if (pending.isEmpty && !_running)
                    const ListTile(
                      leading: Icon(Iconsax.tick_circle),
                      title: Text('সব ভিডিও ইতিমধ্যে স্ট্রিমিং-উপযোগী ✅'),
                    )
                  else ...[
                    Text(
                      _running
                          ? 'ভিডিও ${_index + 1} / ${pending.length}'
                          : 'রূপান্তর বাকি: ${pending.length}টি ভিডিও (${_mb(totalBytes)} MB)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_running) ...[
                      DownloadProgress(
                        received: _received,
                        total: _total,
                        color: Theme.of(context).colorScheme.primary,
                        doneLabel: _stage,
                      ),
                      if (_stage == 'আপলোড হচ্ছে' && _total > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'আপলোড ${(_received * 100 ~/ _total)}%',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'সম্পন্ন: $_done   ব্যর্থ: $_failed',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _stopRequested
                            ? null
                            : () => setState(() => _stopRequested = true),
                        child: Text(
                          _stopRequested
                              ? 'এই ভিডিও শেষ হলে থামবে...'
                              : 'থামান',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'শেষ না হওয়া পর্যন্ত অ্যাপ খোলা রাখুন। মাঝপথে বন্ধ হলেও সমস্যা নেই — পরে আবার চালালে বাকিগুলো থেকে শুরু হবে।',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: _run,
                        icon: const Icon(Iconsax.video_play),
                        label: const Text('রূপান্তর শুরু করুন'),
                      ),
                    if (!_running && _failed > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '$_failedটি ভিডিও রূপান্তর হয়নি — আবার চেষ্টা করুন।',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
