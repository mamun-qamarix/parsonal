import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/duress_service.dart';
import '../../core/security/icon_disguise_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../onboarding/welcome_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _profileService.getSetting('favorite_lines_enabled', fallback: 'true');
    final identity = await IconDisguiseService.getCurrentIdentity();
    if (mounted) {
      setState(() {
        _favoriteLinesEnabled = value == 'true';
        _identity = identity;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavoriteLines(bool value) async {
    setState(() => _favoriteLinesEnabled = value);
    await _profileService.setSetting('favorite_lines_enabled', value.toString());
  }

  Future<void> _setDuressPin() async {
    final pin = _duressPinController.text.trim();
    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN must be at least 4 digits')));
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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duress PIN set')));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out of this device?'),
        content: const Text('You\'ll need the setup code again to reconnect this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
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
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionTitle('Appearance'),
                SwitchListTile(
                  title: const Text('Show "Favorite Lines" screen'),
                  value: _favoriteLinesEnabled,
                  onChanged: _toggleFavoriteLines,
                ),
                const SizedBox(height: 12),
                const _SectionTitle('Security'),
                ListTile(
                  title: const Text('Auto-lock after inactivity'),
                  subtitle: Slider(
                    value: session.autoLockMinutes.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '${session.autoLockMinutes} min',
                    onChanged: (v) => setState(() => session.autoLockMinutesAndPersist = v.round()),
                  ),
                ),
                ListTile(
                  title: const Text('Home screen name'),
                  subtitle: Text(IconDisguiseService.options[_identity] ?? 'Real'),
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
                      const Text('Duress / panic PIN', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Text('Enter this instead of your password to open a decoy screen with no real content.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _duressPinController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: 'New duress PIN'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: _setDuressPin, child: const Text('Set')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionTitle('Account'),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.rejected),
                  title: const Text('Log out of this device'),
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
