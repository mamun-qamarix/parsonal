import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/wishlist_service.dart';

class WishlistSection extends StatefulWidget {
  final String ownerRole;
  const WishlistSection({super.key, required this.ownerRole});

  @override
  State<WishlistSection> createState() => _WishlistSectionState();
}

class _WishlistSectionState extends State<WishlistSection> {
  final _service = WishlistService();
  List<WishlistItemModel> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WishlistSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerRole != widget.ownerRole) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vmk = context.read<SessionProvider>().vmk!;
    final items = await _service.list(vmk, ownerRole: widget.ownerRole);
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  bool get _isMine => context.read<SessionProvider>().role == widget.ownerRole;

  Future<void> _add() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add to wishlist'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    final vmk = context.read<SessionProvider>().vmk!;
    await _service.create(vmk, text);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Wishlist', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const Spacer(),
            if (_isMine) IconButton(icon: const Icon(Icons.add_circle_outline, color: AppColors.halalGreen), onPressed: _add),
          ],
        ),
        if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (_items.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Nothing here yet', style: TextStyle(color: Colors.grey)))
        else
          ..._items.map((item) => Card(
                child: ListTile(
                  leading: Icon(item.isFulfilled ? Icons.check_circle : Icons.circle_outlined, color: item.isFulfilled ? AppColors.halalGreen : Colors.grey),
                  title: Text(item.decryptedText ?? '', style: TextStyle(decoration: item.isFulfilled ? TextDecoration.lineThrough : null)),
                  onTap: _isMine
                      ? () async {
                          await _service.toggleFulfilled(item.id, !item.isFulfilled);
                          _load();
                        }
                      : null,
                  trailing: _isMine
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            await _service.delete(item.id);
                            _load();
                          },
                        )
                      : null,
                ),
              )),
      ],
    );
  }
}
