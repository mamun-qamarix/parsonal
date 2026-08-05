import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../screens/vault/video_trim_screen.dart';
import '../../services/media_service.dart';
import '../../services/vault_service.dart';
import 'video_thumbnail_helper.dart';

/// Opens the trim UI on an already-decrypted local video file, then
/// uploads whatever range the user picks as a brand-new video vault
/// entry -- the original entry is left untouched, so a bad trim never
/// risks the source. Shared between the vault entry detail screen and
/// Reel, since both browse the same video entries. See DECISIONS.md.
Future<void> handleVideoTrimRequested(
  BuildContext context, {
  required String localVideoPath,
  required Uint8List vmk,
  String? categoryId,
}) async {
  final trimmedBytes = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => VideoTrimScreen(sourceVideoPath: localVideoPath),
    ),
  );
  if (trimmedBytes == null || !context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('ক্লিপ আপলোড হচ্ছে...'), duration: Duration(seconds: 2)),
  );
  try {
    final tempThumbFile = File(
      '${(await getTemporaryDirectory()).path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await tempThumbFile.writeAsBytes(trimmedBytes, flush: true);
    final thumbnailBytes = await generateVideoThumbnail(tempThumbFile.path);
    await tempThumbFile.delete().catchError((_) => tempThumbFile);

    final asset = await MediaService().upload(
      vmk,
      kind: 'video',
      bytes: trimmedBytes,
      thumbnailBytes: thumbnailBytes,
    );
    await VaultService().createEntry(
      vmk,
      contentType: 'video',
      text: '',
      categoryId: categoryId,
      mediaAssetIds: [asset.id],
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('নতুন ক্লিপ ভল্টে সেভ হয়েছে।')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ক্লিপ সেভ করা যায়নি, আবার চেষ্টা করুন।')));
    }
  }
}
