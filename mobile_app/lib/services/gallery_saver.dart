import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
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
  final vmk = context.read<SessionProvider>().vmk;
  if (vmk == null) return;
  messenger.showSnackBar(
    const SnackBar(
      content: Text('ডাউনলোড হচ্ছে...'),
      duration: Duration(seconds: 2),
    ),
  );
  File? tmp;
  try {
    final bytes = await MediaService().downloadRaw(vmk, assetId);
    final dir = await getTemporaryDirectory();
    final ext = isVideo ? 'mp4' : _imageExt(bytes);
    tmp = File(
      '${dir.path}/dl_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    if (!await Gal.hasAccess()) {
      if (!await Gal.requestAccess()) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('গ্যালারিতে সেভ করার অনুমতি দেওয়া হয়নি')),
        );
        return;
      }
    }
    if (isVideo) {
      await Gal.putVideo(tmp.path);
    } else {
      await Gal.putImage(tmp.path);
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('গ্যালারিতে সেভ হয়েছে ✅')),
    );
  } catch (_) {
    messenger.hideCurrentSnackBar();
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
