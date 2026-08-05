import 'package:flutter/material.dart';

import '../../widgets/decrypted_media.dart';

/// Full-screen viewer opened by tapping any image/video anywhere in the
/// app (chat bubbles, vault entries, profile photos) -- images are
/// pinch-zoomable and never distorted (BoxFit.contain preserves the real
/// aspect ratio), videos play with their real aspect ratio too (not
/// stretched to fill the screen). See DECISIONS.md.
class MediaViewerScreen extends StatelessWidget {
  final String assetId;
  final String contentType; // photo | video
  const MediaViewerScreen({
    super.key,
    required this.assetId,
    required this.contentType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: contentType == 'video'
            ? DecryptedVideoPlayer(assetId: assetId)
            : DecryptedFullImage(
                assetId: assetId,
                fit: BoxFit.contain,
                zoomable: true,
              ),
      ),
    );
  }
}
