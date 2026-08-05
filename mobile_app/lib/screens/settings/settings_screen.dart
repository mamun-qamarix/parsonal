import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../core/security/duress_service.dart';
import '../../core/security/icon_disguise_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/error_message_box.dart';
import '../../widgets/password_field.dart';
import '../auth/face_capture_screen.dart';
import '../onboarding/welcome_screen.dart';
import 'add_device_screen.dart';
import 'approve_password_reset_screen.dart';
import 'devices_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profileService = ProfileService();
  final _authService = AuthService();
  bool _favoriteLinesEnabled = true;
  String _identity = 'real';
  final _duressPinController = TextEditingController();
  bool _loading = true;
  bool _faceEnrolled = false;
  bool _faceVerificationEnabled = false;
  bool _faceToggleBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _profileService.getSetting('favorite_lines_enabled', fallback: 'true');
    final identity = await IconDisguiseService.getCurrentIdentity();
    Map<String, dynamic>? me;
    try {
      me = await _authService.getMe();
    } catch (_) {
      // Non-fatal: the face toggle just won't reflect server state until reload.
    }
    if (mounted) {
      setState(() {
        _favoriteLinesEnabled = value == 'true';
        _identity = identity;
        if (me != null) {
          _faceEnrolled = me['face_enrolled'] == true;
          _faceVerificationEnabled = me['face_verification_enabled'] == true;
        }
        _loading = false;
      });
    }
  }

  Future<void> _toggleFaceVerification(bool value) async {
    setState(() => _faceToggleBusy = true);
    try {
      if (value) {
        if (_faceEnrolled) {
          await _authService.enableFace();
        } else {
          final bytes = await Navigator.of(context).push<dynamic>(MaterialPageRoute(
            builder: (_) => const FaceCaptureScreen(title: 'মুখ রেজিস্ট্রেশন', instructions: 'ক্যামেরার দিকে তাকান, তারপর চোখের পলক ফেলুন'),
          ));
          if (bytes == null) {
            setState(() => _faceToggleBusy = false);
            return;
          }
          await _authService.enrollFace(bytes);
          _faceEnrolled = true;
        }
      } else {
        await _authService.disableFace();
      }
      if (mounted) setState(() => _faceVerificationEnabled = value);
    } catch (e) {
      if (mounted) showCopyableErrorSnackBar(context, describeApiError(e));
    } finally {
      if (mounted) setState(() => _faceToggleBusy = false);
    }
  }

  Future<void> _toggleFavoriteLines(bool value) async {
    setState(() => _favoriteLinesEnabled = value);
    await _profileService.setSetting('favorite_lines_enabled', value.toString());
  }

  Future<void> _setDuressPin() async {
    final pin = _duressPinController.text.trim();
    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('পিন কমপক্ষে ৪ সংখ্যার হতে হবে')));
      return;
    }
    final spouseId = context.read<SessionProvider>().spouseId!;
    await DuressService.setLocalPin(pin, spouseId);
    try {
      await _authService.setDuressPin(pin);
    } catch (_) {
      // Local check is what matters at panic time; server copy is best-effort backup.
    }
    _duressPinController.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('বিপদের পিন সেট হয়েছে')));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('এই ডিভাইস থেকে লগ আউট করবেন?'),
        content: const Text('আবার এই ডিভাইস যুক্ত করতে হলে নতুন করে সেটআপ কোড লাগবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('লগ আউট')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await context.read<SessionProvider>().logoutAndForget();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('সেটিংস')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionTitle('চেহারা'),
                SwitchListTile(
                  title: const Text('"Favorite Lines" স্ক্রিন দেখান'),
                  subtitle: const Text('স্বামী-স্ত্রীর একে অপরকে লেখা বিশেষ লাইনগুলোর জন্য আলাদা স্ক্রিন', style: TextStyle(fontSize: 12)),
                  value: _favoriteLinesEnabled,
                  onChanged: _toggleFavoriteLines,
                ),
                const SizedBox(height: 12),
                const _SectionTitle('নিরাপত্তা'),
                SwitchListTile(
                  title: const Text('মুখ ভেরিফিকেশন (ঐচ্ছিক)'),
                  subtitle: const Text(
                    'অন করলে পাসওয়ার্ডের পাশাপাশি প্রতিবার লগইনে মুখ দিয়েও যাচাই করতে হবে — বাড়তি নিরাপত্তার জন্য',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _faceVerificationEnabled,
                  onChanged: _faceToggleBusy ? null : _toggleFaceVerification,
                  secondary: _faceToggleBusy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                ),
                ListTile(
                  title: const Text('নিষ্ক্রিয় থাকলে অটো-লক'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('এত মিনিট কিছু না করলে অ্যাপ নিজে থেকে লক হয়ে যাবে', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Slider(
                        value: session.autoLockMinutes.toDouble(),
                        min: 1,
                        max: 30,
                        divisions: 29,
                        label: '${session.autoLockMinutes} মিনিট',
                        onChanged: (v) => setState(() => session.autoLockMinutesAndPersist = v.round()),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  title: const Text('হোম স্ক্রিনে অ্যাপের নাম'),
                  subtitle: Text('${IconDisguiseService.options[_identity] ?? 'আসল নাম'}\nঅ্যাপটাকে অন্য নাম/আইকনে লুকিয়ে রাখতে চাইলে বদলান', style: const TextStyle(fontSize: 12)),
                  isThreeLine: true,
                  trailing: DropdownButton<String>(
                    value: _identity,
                    items: IconDisguiseService.options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      await IconDisguiseService.setIdentity(v);
                      setState(() => _identity = v);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('বিপদের পিন (Duress PIN)', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Text(
                        'কেউ জোর করে ফোন খুলতে বললে, আসল পাসওয়ার্ডের বদলে এই পিনটা দিলে একটা খালি/ভুয়া স্ক্রিন দেখাবে — আসল কনটেন্ট দেখা যাবে না।',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PasswordField(
                              controller: _duressPinController,
                              labelText: 'নতুন বিপদের পিন',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: _setDuressPin, child: const Text('সেট করুন')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionTitle('অ্যাকাউন্ট'),
                ListTile(
                  leading: const Icon(Icons.devices_outlined, color: AppColors.halalGreen),
                  title: const Text('ডিভাইসসমূহ'),
                  subtitle: const Text('কোন ডিভাইস কার, দেখুন ও হারানো/পুরনো ডিভাইস সরিয়ে দিন', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_2, color: AppColors.halalGreen),
                  title: const Text('নতুন ডিভাইস যোগ করুন'),
                  subtitle: const Text('আপনার নতুন বা দ্বিতীয় ফোনে এই অ্যাকাউন্টটাই যোগ করুন', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddDeviceScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined, color: AppColors.halalGreen),
                  title: const Text('পাসওয়ার্ড রিসেট অনুমোদন করুন'),
                  subtitle: const Text('অন্য ডিভাইসে পাসওয়ার্ড রিসেট শুরু হলে এখান থেকে অনুমোদন দিন', style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApprovePasswordResetScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.rejected),
                  title: const Text('এই ডিভাইস থেকে লগ আউট করুন'),
                  onTap: _logout,
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.halalGreen)),
    );
  }
}
