import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/vault_service.dart';
import 'entry_detail_screen.dart';

class ConsentRequestsScreen extends StatefulWidget {
  const ConsentRequestsScreen({super.key});

  @override
  State<ConsentRequestsScreen> createState() => _ConsentRequestsScreenState();
}

class _ConsentRequestsScreenState extends State<ConsentRequestsScreen> {
  final _service = VaultService();
  List<ConsentRequestModel> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final requests = await _service.listConsentRequests();
    if (mounted) setState(() { _requests = requests; _loading = false; });
  }

  Future<void> _decide(ConsentRequestModel req, bool approve) async {
    try {
      await _service.decideConsentRequest(req.id, approve);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Could not approve — did you request this yourself?' : 'Could not update the request.')));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<SessionProvider>().spouseId;
    return Scaffold(
      appBar: AppBar(title: const Text('Approval requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('No pending requests'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _requests.length,
                    itemBuilder: (context, i) {
                      final req = _requests[i];
                      final isMine = req.requestedBy == myId;
                      return Card(
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryDetailScreen(entryId: req.entryId))),
                          leading: Icon(req.action == 'delete' ? Icons.delete_outline : Icons.edit_outlined),
                          title: Text('${req.action == 'delete' ? 'Delete' : 'Edit'} request'),
                          subtitle: Text('${isMine ? 'You requested' : 'Your spouse requested'} this on ${DateFormat.yMMMd().add_jm().format(req.createdAt.toLocal())}'),
                          trailing: isMine
                              ? const Text('Waiting...', style: TextStyle(color: Colors.grey))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => _decide(req, true)),
                                    IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => _decide(req, false)),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
