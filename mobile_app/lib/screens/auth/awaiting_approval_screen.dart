import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';

/// Shown after the right master password on a phone the server doesn't
/// know yet. Polls every few seconds; the moment the admin approves this
/// phone (matching the code on screen), it logs straight in. See
/// DECISIONS.md #54.
class AwaitingApprovalScreen extends StatefulWidget {
  const AwaitingApprovalScreen({super.key});

  @override
  State<AwaitingApprovalScreen> createState() => _AwaitingApprovalScreenState();
}

class _AwaitingApprovalScreenState extends State<AwaitingApprovalScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  bool _busy = false;
  String? _message;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy) return;
    final session = context.read<SessionProvider>();
    final id = session.pendingRequestId, token = session.pendingPollToken;
    if (id == null || token == null) return;
    _busy = true;
    try {
      final res = await AuthService().masterStatus(requestId: id, pollToken: token);
      final status = res['status'];
      if (status == 'approved') {
        _timer?.cancel();
        await session.completeMasterLogin(res);
      } else if (status == 'rejected') {
        _timer?.cancel();
        if (mounted) setState(() => _message = 'অনুরোধটি বাতিল করা হয়েছে।');
      } else if (_message != null && mounted) {
        setState(() => _message = null);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _timer?.cancel();
        session.cancelAwaitingApproval();
      } else if (mounted) {
        setState(() => _message = 'সার্ভারে পৌঁছানো যাচ্ছে না, আবার চেষ্টা হচ্ছে…');
      }
    } on StateError catch (e) {
      _timer?.cancel();
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final text = Theme.of(context).textTheme;
    final rejected = _message == 'অনুরোধটি বাতিল করা হয়েছে।';
    final accent = rejected ? AppColors.rejected : AppColors.pending;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: FadeTransition(
                    opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent.withValues(alpha: 0.35), width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.14),
                        ),
                        child: Icon(
                          rejected ? Iconsax.close_circle_copy : Iconsax.mobile_copy,
                          size: 32,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  rejected ? 'অনুমতি দেওয়া হয়নি' : 'অনুমতির অপেক্ষায়',
                  textAlign: TextAlign.center,
                  style: text.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  rejected
                      ? 'অ্যাডমিন এই ফোনের অনুরোধ বাতিল করেছেন।'
                      : 'পাসওয়ার্ড ঠিক আছে। অ্যাডমিন প্যানেল থেকে এই ফোনটা অনুমোদন দিলেই নিজে থেকে ঢুকে যাবে।',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: AppColors.muted, height: 1.6),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.05),
                    border: Border.all(color: accent.withValues(alpha: 0.2), width: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _row(text, 'ডিভাইস', Text(session.pendingDeviceName ?? '—', style: text.bodyMedium)),
                      const SizedBox(height: 8),
                      _row(
                        text,
                        'মিলিয়ে নেওয়ার কোড',
                        Text(
                          session.pendingCode ?? '—',
                          style: text.titleMedium?.copyWith(
                            color: AppColors.pending,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_message != null && !rejected) ...[
                  const SizedBox(height: 12),
                  Text(_message!, textAlign: TextAlign.center, style: text.labelSmall?.copyWith(color: AppColors.muted)),
                ],
                const SizedBox(height: 22),
                OutlinedButton(
                  onPressed: () {
                    _timer?.cancel();
                    context.read<SessionProvider>().cancelAwaitingApproval();
                  },
                  child: Text(rejected ? 'ফিরে যান' : 'বাতিল করুন'),
                ),
                if (!rejected) ...[
                  const SizedBox(height: 18),
                  Text(
                    'প্রতি ৩ সেকেন্ডে চেক হচ্ছে…',
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(color: AppColors.faint),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(TextTheme text, String label, Widget value) => Row(
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: AppColors.muted)),
          const Spacer(),
          value,
        ],
      );
}
