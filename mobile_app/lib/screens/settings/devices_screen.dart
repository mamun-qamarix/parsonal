import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/device_service.dart';
import '../../widgets/error_message_box.dart';
import '../../widgets/shimmer_loading.dart';
import '../onboarding/welcome_screen.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _service = DeviceService();
  List<DeviceModel> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await _service.list();
      if (mounted)
        setState(() {
          _devices = devices;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = describeApiError(e);
          _loading = false;
        });
    }
  }

  Future<void> _confirmDelete(DeviceModel device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('এই ডিভাইসটা সরিয়ে দেবেন?'),
        content: Text(
          device.isThisDevice
              ? '"${device.deviceName}" — এটা আপনার এই ফোনটাই! সরালে আপনিও সাথে সাথে লগ আউট হয়ে যাবেন, আবার ঢুকতে নতুন করে সেটআপ কোড লাগবে।'
              : '"${device.deviceName}" ডিভাইসটা আর অ্যাপে ঢুকতে পারবে না, যতক্ষণ না আবার নতুন করে সেটআপ কোড দিয়ে যুক্ত করা হয়।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('সরিয়ে দিন'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.delete(device.id);
      if (device.isThisDevice) {
        if (!mounted) return;
        await context.read<SessionProvider>().logoutAndForget();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
        return;
      }
      _load();
    } catch (e) {
      if (mounted) showCopyableErrorSnackBar(context, describeApiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ডিভাইসসমূহ')),
      body: _loading
          ? const ShimmerTileList()
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ErrorMessageBox(_error!),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'আপনাদের দুজনের সব ডিভাইস এখানে দেখা যাচ্ছে। ফোন হারালে বা বদলালে এখান থেকে সেটা সরিয়ে দিন।',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ),
                  Expanded(
                    child: _devices.isEmpty
                        ? const Center(child: Text('কোনো ডিভাইস পাওয়া যায়নি'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _devices.length,
                            itemBuilder: (context, i) {
                              final d = _devices[i];
                              final accent = d.role == 'husband'
                                  ? AppColors.husband
                                  : AppColors.wife;
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: accent,
                                    child: Icon(
                                      d.role == 'husband'
                                          ? Iconsax.man
                                          : Iconsax.woman,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          d.deviceName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (d.isThisDevice) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.halalGreen
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: const Text(
                                            'এই ডিভাইস',
                                            style: TextStyle(
                                              color: AppColors.halalGreen,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${d.role == 'husband' ? 'স্বামী' : 'স্ত্রী'} · সর্বশেষ ব্যবহার ${DateFormat.yMMMd().add_jm().format(d.lastSeenAt.toLocal())}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Iconsax.trash,
                                      color: AppColors.rejected,
                                    ),
                                    onPressed: () => _confirmDelete(d),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
