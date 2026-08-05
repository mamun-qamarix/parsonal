import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/audit_service.dart';
import '../../widgets/shimmer_loading.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<AuditLogEntryModel> _log = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await AuditService().getLog();
    if (mounted)
      setState(() {
        _log = log;
        _loading = false;
      });
  }

  IconData _iconFor(String action) {
    if (action.startsWith('content.view')) return Iconsax.eye;
    if (action.contains('delete')) return Iconsax.trash;
    if (action.contains('edit')) return Iconsax.edit_2;
    if (action.contains('create')) return Iconsax.add_circle;
    if (action.startsWith('auth.')) return Iconsax.lock;
    if (action.startsWith('reaction')) return Iconsax.heart;
    if (action.startsWith('comment')) return Iconsax.message_2;
    return Iconsax.info_circle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: _loading
          ? const ShimmerTileList()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, i) {
                  final entry = _log[i];
                  return ListTile(
                    leading: Icon(_iconFor(entry.action)),
                    title: Text(entry.action),
                    subtitle: Text(
                      DateFormat.yMMMd().add_jm().format(
                            entry.createdAt.toLocal(),
                          ) +
                          (entry.detail != null ? ' · ${entry.detail}' : ''),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
