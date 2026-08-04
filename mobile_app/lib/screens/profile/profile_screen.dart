import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/profile_service.dart';
import '../audit/audit_log_screen.dart';
import '../phrases/phrases_screen.dart';
import '../settings/settings_screen.dart';
import '../wishlist/wishlist_section.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    final myRole = context.read<SessionProvider>().role ?? 'husband';
    _tab = TabController(length: 2, vsync: this, initialIndex: myRole == 'husband' ? 0 : 1);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(icon: const Icon(Icons.favorite_border), tooltip: 'Our phrases', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhrasesScreen()))),
          IconButton(icon: const Icon(Icons.fact_check_outlined), tooltip: 'Audit log', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuditLogScreen()))),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Husband'), Tab(text: 'Wife')]),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _ProfileView(role: 'husband'),
          _ProfileView(role: 'wife'),
        ],
      ),
    );
  }
}

class _ProfileView extends StatefulWidget {
  final String role;
  const _ProfileView({required this.role});

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  final _service = ProfileService();
  ProfileModel? _profile;
  bool _loading = true;
  bool _editing = false;
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  bool get _isMine => context.read<SessionProvider>().role == widget.role;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final profile = await _service.get(vmk, widget.role);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _nameController.text = profile.decryptedName ?? '';
      _bioController.text = profile.decryptedBio ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final vmk = context.read<SessionProvider>().vmk!;
    await _service.updateMine(vmk, name: _nameController.text.trim(), bio: _bioController.text.trim());
    setState(() => _editing = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final accent = widget.role == 'husband' ? AppColors.husband : AppColors.wife;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: CircleAvatar(radius: 44, backgroundColor: accent, child: Icon(widget.role == 'husband' ? Icons.man : Icons.woman, size: 44, color: Colors.white)),
        ),
        const SizedBox(height: 12),
        if (_editing)
          Column(
            children: [
              TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Display name')),
              const SizedBox(height: 8),
              TextField(controller: _bioController, decoration: const InputDecoration(labelText: 'About'), maxLines: 3),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
                ],
              ),
            ],
          )
        else
          Column(
            children: [
              Text(_profile?.decryptedName?.isNotEmpty == true ? _profile!.decryptedName! : '${widget.role[0].toUpperCase()}${widget.role.substring(1)}', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              if (_profile?.decryptedBio?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(_profile!.decryptedBio!, textAlign: TextAlign.center),
              ],
              if (_isMine)
                TextButton.icon(onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.edit, size: 16), label: const Text('Edit')),
            ],
          ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        WishlistSection(ownerRole: widget.role),
      ],
    );
  }
}
