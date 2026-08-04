import 'package:flutter/material.dart';

/// Shown when a duress/panic PIN is entered instead of the real password.
/// No real vault content is ever loaded into memory on this path.
class DecoyHomeScreen extends StatelessWidget {
  const DecoyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _DecoyNote('Grocery list', 'Milk, eggs, bread, rice...'),
          _DecoyNote('Reminder', 'Pay the electricity bill'),
          _DecoyNote('Ideas', 'Weekend plans'),
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
      child: ListTile(title: Text(title), subtitle: Text(subtitle), leading: const Icon(Icons.note_outlined)),
    );
  }
}
