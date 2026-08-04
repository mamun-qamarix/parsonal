import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/audit_service.dart';

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
    if (mounted) setState(() { _log = log; _loading = false; });
  }

  IconData _iconFor(String action) {
    if (action.startsWith('content.view')) return Icons.visibility_outlined;
    if (action.contains('delete')) return Icons.delete_outline;
    if (action.contains('edit')) return Icons.edit_outlined;
    if (action.contains('create')) return Icons.add_circle_outline;
    if (action.startsWith('auth.')) return Icons.lock_outline;
    if (action.startsWith('reaction')) return Icons.favorite_border;
    if (action.startsWith('comment')) return Icons.mode_comment_outlined;
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, i) {
                  final entry = _log[i];
                  return ListTile(
                    leading: Icon(_iconFor(entry.action)),
                    title: Text(entry.action),
                    subtitle: Text(DateFormat.yMMMd().add_jm().format(entry.createdAt.toLocal()) + (entry.detail != null ? ' · ${entry.detail}' : '')),
                  );
                },
              ),
            ),
    );
  }
}
