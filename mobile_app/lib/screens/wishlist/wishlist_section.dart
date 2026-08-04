import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/vault_service.dart';
import '../../services/wishlist_service.dart';

/// A plain wishlist -- NOT a task/checklist. No checkbox, no
/// mark-as-done, no strikethrough; items just live in the list until you
/// delete them. Each item can optionally have a category (created
/// on-the-fly, same mechanism as vault categories but scope="wishlist").
/// See DECISIONS.md.
class WishlistSection extends StatefulWidget {
  final String ownerRole;
  const WishlistSection({super.key, required this.ownerRole});

  @override
  State<WishlistSection> createState() => _WishlistSectionState();
}

class _WishlistSectionState extends State<WishlistSection> {
  final _service = WishlistService();
  List<WishlistItemModel> _items = [];
  List<Category> _categories = [];
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
    final results = await Future.wait([
      _service.list(vmk, ownerRole: widget.ownerRole),
      VaultService().listCategories(vmk, 'wishlist'),
    ]);
    if (mounted) {
      setState(() {
        _items = results[0] as List<WishlistItemModel>;
        _categories = results[1] as List<Category>;
        _loading = false;
      });
    }
  }

  bool get _isMine => context.read<SessionProvider>().role == widget.ownerRole;

  String? _categoryName(String? categoryId) {
    if (categoryId == null) return null;
    for (final c in _categories) {
      if (c.id == categoryId) return c.decryptedName;
    }
    return null;
  }

  Future<void> _add() async {
    final result = await showDialog<_NewWishlistItem>(
      context: context,
      builder: (_) => _AddWishlistItemDialog(categories: _categories),
    );
    if (result == null || result.text.isEmpty) return;
    final vmk = context.read<SessionProvider>().vmk!;
    if (result.newCategoryName != null) {
      final cat = await VaultService().createCategory(vmk, 'wishlist', result.newCategoryName!);
      await _service.create(vmk, result.text, categoryId: cat.id);
    } else {
      await _service.create(vmk, result.text, categoryId: result.categoryId);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('উইশলিস্ট', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const Spacer(),
            if (_isMine) IconButton(icon: const Icon(Icons.add_circle_outline, color: AppColors.halalGreen), onPressed: _add),
          ],
        ),
        if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (_items.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('এখনো কিছু নেই', style: TextStyle(color: Colors.grey)))
        else
          ..._items.map((item) {
            final categoryName = _categoryName(item.categoryId);
            return Card(
              child: ListTile(
                leading: const Icon(Icons.card_giftcard_outlined, color: AppColors.halalGreen),
                title: Text(item.decryptedText ?? ''),
                subtitle: categoryName != null ? Text(categoryName, style: const TextStyle(fontSize: 12)) : null,
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
            );
          }),
      ],
    );
  }
}

class _NewWishlistItem {
  final String text;
  final String? categoryId;
  final String? newCategoryName;
  _NewWishlistItem({required this.text, this.categoryId, this.newCategoryName});
}

class _AddWishlistItemDialog extends StatefulWidget {
  final List<Category> categories;
  const _AddWishlistItemDialog({required this.categories});

  @override
  State<_AddWishlistItemDialog> createState() => _AddWishlistItemDialogState();
}

class _AddWishlistItemDialogState extends State<_AddWishlistItemDialog> {
  final _textController = TextEditingController();
  final _newCategoryController = TextEditingController();
  String? _categoryId;
  bool _creatingCategory = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('উইশলিস্টে যোগ করুন'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _textController, autofocus: true, decoration: const InputDecoration(hintText: 'কী চান লিখুন')),
          const SizedBox(height: 12),
          if (!_creatingCategory) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'ক্যাটাগরি (ঐচ্ছিক)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('কোনোটি না')),
                      ...widget.categories.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.decryptedName ?? '...'))),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                IconButton(
                  tooltip: 'নতুন ক্যাটাগরি বানান',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _creatingCategory = true),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: _newCategoryController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'নতুন ক্যাটাগরির নাম',
                suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _creatingCategory = false)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল')),
        FilledButton(
          onPressed: () {
            final text = _textController.text.trim();
            if (text.isEmpty) return;
            final newCategoryName = _creatingCategory ? _newCategoryController.text.trim() : null;
            Navigator.pop(
              context,
              _NewWishlistItem(
                text: text,
                categoryId: _categoryId,
                newCategoryName: (newCategoryName != null && newCategoryName.isNotEmpty) ? newCategoryName : null,
              ),
            );
          },
          child: const Text('যোগ করুন'),
        ),
      ],
    );
  }
}
