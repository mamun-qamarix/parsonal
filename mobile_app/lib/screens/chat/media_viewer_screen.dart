import 'package:flutter/material.dart';

import '../../widgets/decrypted_media.dart';

/// Full-screen viewer opened by tapping an image/video bubble in chat --
/// images are pinch-zoomable, videos play with their real aspect ratio
/// (not stretched to fill the screen). See DECISIONS.md.
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
