import 'dart:typed_data';

import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';

/// Grabs a JPEG frame from a local video file to use as its thumbnail.
///
/// Previously nothing generated a thumbnail for videos at all -- every
/// video in the vault feed and chat rendered as an identical blank
/// placeholder box with a play icon, so there was no way to tell which
/// video was which without opening each one. The backend has always
/// supported an optional thumbnail upload alongside the video
/// (`MediaService.upload(thumbnailBytes: ...)`); this just finally
/// produces one. Returns null (never throws) if generation fails for any
/// reason -- a missing thumbnail degrades to the old blank-box look
/// rather than blocking the upload. See DECISIONS.md.
Future<Uint8List?> generateVideoThumbnail(String videoPath) async {
  try {
    return await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 480,
      quality: 70,
    );
  } catch (_) {
    return null;
  }
}
