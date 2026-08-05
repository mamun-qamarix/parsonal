import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/media_service.dart';
import '../../services/profile_cache.dart';
import '../../services/profile_service.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/error_message_box.dart';
import '../../widgets/media_viewer_screen.dart';
import '../audit/audit_log_screen.dart';
import '../phrases/phrases_screen.dart';
import '../settings/settings_screen.dart';
import '../wishlist/wishlist_section.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    final myRole = context.read<SessionProvider>().role ?? 'husband';
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: myRole == 'husband' ? 0 : 1,
    );
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
        title: const Text('প্রোফাইল'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.heart),
            tooltip: 'আমাদের প্রিয় লাইন',
            onPressed: () => openPhrasesScreen(context),
          ),
          IconButton(
            icon: const Icon(Iconsax.task_square),
            tooltip: 'অডিট লগ',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AuditLogScreen())),
          ),
          IconButton(
            icon: const Icon(Iconsax.setting_2),
            tooltip: 'সেটিংস',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'স্বামী'),
            Tab(text: 'স্ত্রী'),
          ],
        ),
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
  bool _uploadingPhoto = false;
  String? _error;
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  // Either spouse can edit either profile now -- the shared-trust model
  // used everywhere else in the app. See DECISIONS.md.

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
    await _service.updateRole(
      vmk,
      widget.role,
      name: _nameController.text.trim(),
      bio: _bioController.text.trim(),
    );
    ProfileCache.instance.invalidate(widget.role);
    setState(() => _editing = false);
    _load();
  }

  Future<void> _changePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null) return;
    setState(() {
      _uploadingPhoto = true;
      _error = null;
    });
    try {
      final vmk = context.read<SessionProvider>().vmk!;
      final bytes = await File(file.path).readAsBytes();
      final asset = await MediaService().upload(
        vmk,
        kind: 'image',
        bytes: bytes,
      );
      await _service.updateRole(vmk, widget.role, photoAssetId: asset.id);
      ProfileCache.instance.invalidate(widget.role);
      await _load();
    } catch (e) {
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final accent = widget.role == 'husband'
        ? AppColors.husband
        : AppColors.wife;
    final photoId = _profile?.profilePhotoAssetId;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Stack(
            children: [
              GestureDetector(
                onTap: photoId == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MediaViewerScreen(
                            assetId: photoId,
                            contentType: 'photo',
                          ),
                        ),
                      ),
                child: ClipOval(
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: photoId != null
                        ? DecryptedThumbnail(
                            assetId: photoId,
                            hasThumbnail: false,
                          )
                        : CircleAvatar(
                            radius: 44,
                            backgroundColor: accent,
                            child: Icon(
                              widget.role == 'husband'
                                  ? Iconsax.man
                                  : Iconsax.woman,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  onTap: _uploadingPhoto ? null : _changePhoto,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    child: _uploadingPhoto
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Iconsax.camera,
                            size: 14,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ErrorMessageBox(_error!, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 12),
        if (_editing)
          Column(
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'নাম'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: 'সম্পর্কে কিছু কথা',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _editing = false),
                      child: const Text('বাতিল'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('সংরক্ষণ'),
                    ),
                  ),
                ],
              ),
            ],
          )
        else
          Column(
            children: [
              Text(
                _profile?.decryptedName?.isNotEmpty == true
                    ? _profile!.decryptedName!
                    : (widget.role == 'husband' ? 'স্বামী' : 'স্ত্রী'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (_profile?.decryptedBio?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(_profile!.decryptedBio!, textAlign: TextAlign.center),
              ],
              TextButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Iconsax.edit_2, size: 16),
                  label: const Text('এডিট করুন'),
                ),
            ],
          ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Iconsax.heart_copy, color: AppColors.rejected),
            title: const Text(
              'আমাদের প্রিয় লাইন',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'একে অপরকে লেখা বিশেষ লাইনগুলো — রেটিং দিয়ে জানান কোনটা সবচেয়ে ভালো লাগলো',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Iconsax.arrow_right_3),
            onTap: () => openPhrasesScreen(context),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        WishlistSection(ownerRole: widget.role),
      ],
    );
  }
}
