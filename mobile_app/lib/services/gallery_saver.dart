import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../widgets/shimmer_loading.dart';
import 'media_service.dart';

/// Downloads (and decrypts) a photo/video and saves it into the phone's
/// gallery. Used by every three-dot menu / viewer that shows media. The
/// decrypted copy only touches a temp file long enough to hand it to the
/// gallery, then that temp file is deleted. See DECISIONS.md.
Future<void> saveMediaToGallery(
  BuildContext context, {
  required String assetId,
  required bool isVideo,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final vmk = context.read<SessionProvider>().vmk;
  if (vmk == null) return;

  // (received, total) in bytes; total <= 0 = unknown / not started yet.
  final progress = ValueNotifier<(int, int)>((0, 0));
  final stage = ValueNotifier<String?>(null);
  var dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(isVideo ? 'ভিডিও ডাউনলোড' : 'ছবি ডাউনলোড'),
        content: ValueListenableBuilder<String?>(
          valueListenable: stage,
          builder: (context, st, _) => ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, p, _) => DownloadProgress(
              received: p.$1,
              total: p.$2,
              color: Theme.of(context).colorScheme.primary,
              doneLabel: st ?? 'প্রস্তুত হচ্ছে...',
            ),
          ),
        ),
      ),
    ),
  ).whenComplete(() {
    dialogOpen = false;
  });

  void closeDialog() {
    if (dialogOpen) navigator.pop();
  }

  File? tmp;
  try {
    final bytes = await MediaService().downloadRaw(
      vmk,
      assetId,
      onProgress: (r, t) => progress.value = (r, t),
    );
    // Downloaded (or it was already cached): show the save stage.
    final p = progress.value;
    final full = p.$2 > 0 ? p.$2 : 1;
    progress.value = (full, full);
    stage.value = 'গ্যালারিতে সেভ হচ্ছে...';
    final dir = await getTemporaryDirectory();
    final ext = isVideo ? 'mp4' : _imageExt(bytes);
    tmp = File('${dir.path}/dl_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await tmp.writeAsBytes(bytes, flush: true);
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      closeDialog();
      messenger.showSnackBar(
        const SnackBar(content: Text('গ্যালারিতে সেভ করার অনুমতি দেওয়া হয়নি')),
      );
      return;
    }
    if (isVideo) {
      await Gal.putVideo(tmp.path);
    } else {
      await Gal.putImage(tmp.path);
    }
    closeDialog();
    messenger.showSnackBar(
      const SnackBar(content: Text('গ্যালারিতে সেভ হয়েছে ✅')),
    );
  } catch (_) {
    closeDialog();
    messenger.showSnackBar(
      const SnackBar(content: Text('ডাউনলোড করা যায়নি, আবার চেষ্টা করুন')),
    );
  } finally {
    try {
      await tmp?.delete();
    } catch (_) {}
  }
}

String _imageExt(Uint8List b) {
  if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    return 'png';
  }
  if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57) {
    return 'webp';
  }
  return 'jpg';
}
