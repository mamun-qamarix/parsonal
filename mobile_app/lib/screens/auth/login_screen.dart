import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/error_helper.dart';
import '../../core/network/server_config.dart';
import '../../core/security/duress_service.dart';
import '../../core/storage/device_name_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_message_box.dart';
import '../../widgets/password_field.dart';
import '../../widgets/shimmer_loading.dart';

/// The ONE way into the app now (DECISIONS.md #54): type the shared master
/// password. An approved phone goes straight in; a new phone lands on the
/// "waiting for approval" screen until the admin panel approves it. No QR,
/// no setup code, no role picking on the phone.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _server;

  @override
  void initState() {
    super.initState();
    ServerConfig.get().then((s) {
      if (!mounted) return;
      setState(() => _server = s);
      if (s != null) ApiClient.instance.configureBaseUrl(s);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'পাসওয়ার্ড দিন');
      return;
    }
    if (_server == null) {
      await _editServer();
      if (_server == null) return;
    }
    if (!mounted) return;
    final session = context.read<SessionProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spouseId = session.spouseId;
      if (spouseId != null && await DuressService.matches(_password.text, spouseId)) {
        session.enterDecoyMode();
        return;
      }
      await ApiClient.instance.configureBaseUrl(_server!);
      final deviceName = await DeviceNameService.detect();
      final result = await AuthService().masterLogin(
        password: _password.text,
        deviceName: deviceName,
      );
      if (result['status'] == 'approved') {
        await session.completeMasterLogin(result);
      } else {
        session.beginAwaitingApproval(
          requestId: result['request_id'] as String,
          pollToken: result['poll_token'] as String,
          code: result['code'] as String,
          deviceName: deviceName,
        );
      }
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: _server ?? 'https://');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('সার্ভারের ঠিকানা'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://vault.example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('সেভ'),
          ),
        ],
      ),
    );
    if (value == null || value.trim().isEmpty) return;
    await ServerConfig.set(value);
    final saved = await ServerConfig.get();
    if (saved != null) await ApiClient.instance.configureBaseUrl(saved);
    if (mounted) setState(() => _server = saved);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'সার্ভার',
                icon: const Icon(Iconsax.setting_2, size: 20, color: Colors.grey),
                onPressed: _loading ? null : _editServer,
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Iconsax.lock_1_copy, size: 32, color: scheme.primary),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('আমাদের ভল্ট', textAlign: TextAlign.center, style: text.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'মাস্টার পাসওয়ার্ড দিয়ে প্রবেশ করুন',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 28),
                    PasswordField(
                      controller: _password,
                      labelText: 'মাস্টার পাসওয়ার্ড',
                      autofocus: true,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 14),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ErrorMessageBox(_error!, textAlign: TextAlign.center),
                      ),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: ShimmerSpinner(size: 16))
                          : const Text('প্রবেশ করুন'),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _server == null
                          ? 'প্রথমবার? উপরের ⚙ থেকে সার্ভারের ঠিকানা দিন'
                          : 'নতুন ফোন হলে অ্যাডমিন প্যানেল থেকে একবার অনুমতি লাগবে',
                      textAlign: TextAlign.center,
                      style: text.labelSmall?.copyWith(color: AppColors.faint),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
