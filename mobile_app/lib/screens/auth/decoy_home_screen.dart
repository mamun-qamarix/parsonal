import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Shown when a duress/panic PIN is entered instead of the real password.
/// No real vault content is ever loaded into memory on this path.
class DecoyHomeScreen extends StatelessWidget {
  const DecoyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('নোট')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _DecoyNote('বাজারের তালিকা', 'দুধ, ডিম, রুটি, চাল...'),
          _DecoyNote('রিমাইন্ডার', 'বিদ্যুৎ বিল দিতে হবে'),
          _DecoyNote('পরিকল্পনা', 'সাপ্তাহিক ছুটির পরিকল্পনা'),
        ],
      ),
    );
  }
}

class _DecoyNote extends StatelessWidget {
  final String title;
  final String subtitle;
  const _DecoyNote(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        leading: const Icon(Iconsax.note),
      ),
    );
  }
}
