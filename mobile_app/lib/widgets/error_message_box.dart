import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows an error in a SnackBar with a "কপি" action so the exact text can
/// be copied and sent for troubleshooting, instead of retyping it.
void showCopyableErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'কপি',
        onPressed: () => Clipboard.setData(ClipboardData(text: message)),
      ),
    ),
  );
}

/// An error/status message with a copy button next to it, so the user can
/// copy the exact text to report a problem instead of retyping/screenshotting it.
class ErrorMessageBox extends StatelessWidget {
  final String message;
  final TextAlign textAlign;
  const ErrorMessageBox(this.message, {super.key, this.textAlign = TextAlign.start});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('কপি হয়েছে'), duration: Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(message, textAlign: textAlign, style: const TextStyle(color: Colors.red)),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _copy(context),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy_outlined, size: 18, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
