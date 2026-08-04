import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/error_helper.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/media_service.dart';
import '../../services/vault_service.dart';
import '../../widgets/error_message_box.dart';

class CreateEntryScreen extends StatefulWidget {
  final String contentType; // text | photo | video
  final List<Category> categories;
  const CreateEntryScreen({super.key, required this.contentType, required this.categories});

  @override
  State<CreateEntryScreen> createState() => _CreateEntryScreenState();
}

class _CreateEntryScreenState extends State<CreateEntryScreen> {
  final _textController = TextEditingController();
  String? _categoryId;
  XFile? _picked;
  bool _saving = false;
  double? _uploadProgress; // 0.0-1.0 while a file is actively uploading
  String? _error;
  late List<Category> _categories = widget.categories;

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('নতুন ক্যাটাগরি'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'যেমন: ভ্রমণের স্মৃতি')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('তৈরি করুন')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final vmk = context.read<SessionProvider>().vmk!;
    final cat = await VaultService().createCategory(vmk, 'vault', name);
    setState(() {
      _categories = [..._categories, cat];
      _categoryId = cat.id;
    });
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final file = widget.contentType == 'photo' ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 90) : await picker.pickVideo(source: ImageSource.gallery);
    if (file != null) setState(() => _picked = file);
  }

  Future<void> _submit() async {
    final session = context.read<SessionProvider>();
    final vmk = session.vmk!;
    if (widget.contentType == 'text' && _textController.text.trim().isEmpty) {
      setState(() => _error = 'আগে কিছু লিখুন।');
      return;
    }
    if (widget.contentType != 'text' && _picked == null) {
      setState(() => _error = 'আগে একটা ফাইল বাছাই করুন।');
      return;
    }
    setState(() {
      _saving = true;
      _uploadProgress = null;
      _error = null;
    });
    try {
      final mediaIds = <String>[];
      if (_picked != null) {
        final bytes = await File(_picked!.path).readAsBytes();
        final asset = await MediaService().upload(
          vmk,
          kind: widget.contentType == 'photo' ? 'image' : 'video',
          bytes: bytes,
          onSendProgress: (sent, total) {
            if (total <= 0 || !mounted) return;
            setState(() => _uploadProgress = sent / total);
          },
        );
        mediaIds.add(asset.id);
      }
      await VaultService().createEntry(
        vmk,
        contentType: widget.contentType,
        text: _textController.text.trim(),
        categoryId: _categoryId,
        mediaAssetIds: mediaIds,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = describeApiError(e));
    } finally {
      if (mounted) setState(() { _saving = false; _uploadProgress = null; });
    }
  }

  String get _typeLabel {
    switch (widget.contentType) {
      case 'photo':
        return 'ছবি';
      case 'video':
        return 'ভিডিও';
      default:
        return 'টেক্সট';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('নতুন $_typeLabel')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.contentType == 'text')
                TextField(controller: _textController, maxLines: 6, decoration: const InputDecoration(hintText: 'সঙ্গীর জন্য কিছু লিখুন...'))
              else ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickMedia,
                  label: Text(_picked == null ? '$_typeLabel বাছাই করুন' : 'বাছাই করা হয়েছে: ${_picked!.name}'),
                ),
                const SizedBox(height: 12),
                TextField(controller: _textController, maxLines: 3, decoration: const InputDecoration(hintText: 'ক্যাপশন লিখুন (ঐচ্ছিক)')),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(labelText: 'ক্যাটাগরি (ঐচ্ছিক)'),
                      items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.decryptedName ?? '...'))).toList(),
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                  IconButton(tooltip: 'নতুন ক্যাটাগরি বানান', icon: const Icon(Icons.add_circle_outline), onPressed: _addCategory),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorMessageBox(_error!)),
              if (_saving && _picked != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(value: _uploadProgress, minHeight: 6),
                ),
                const SizedBox(height: 6),
                Text(
                  _uploadProgress != null ? 'আপলোড হচ্ছে... ${(_uploadProgress! * 100).toStringAsFixed(0)}%' : 'আপলোড শুরু হচ্ছে...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
              ],
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ভল্টে সেভ করুন'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
