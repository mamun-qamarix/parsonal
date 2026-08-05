import 'dart:async';

import 'package:flutter/material.dart';

import '../services/profile_service.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class CountdownCard extends StatefulWidget {
  const CountdownCard({super.key});

  @override
  State<CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<CountdownCard> {
  final _service = ProfileService();
  DateTime? _target;
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _load() async {
    final data = await _service.getCountdown();
    if (mounted) {
      setState(() {
        _target = data != null
            ? DateTime.parse(data['target_datetime']).toLocal()
            : null;
        _loading = false;
      });
    }
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      initialDate: _target ?? now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_target ?? now),
    );
    if (time == null) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await _service.setCountdown(combined);
    setState(() => _target = combined);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final target = _target;
    final remaining = target?.difference(DateTime.now());

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _pick,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Iconsax.profile_2user_copy,
                    color: Theme.of(context).colorScheme.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'কবে দেখা হবে',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Iconsax.calendar_edit, color: Colors.grey, size: 18),
                ],
              ),
              if (target == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'তারিখ ঠিক করতে ট্যাপ করুন',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else if (remaining != null && remaining.isNegative)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'এই তো, একদম কাছে! 💚',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (remaining != null) ...[
                const SizedBox(height: 12),
                _CountdownBoxes(remaining: remaining),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A standard digital-countdown look -- separate boxes for days/hours/
/// minutes/seconds -- replacing the old single line of running text. See
/// DECISIONS.md.
class _CountdownBoxes extends StatelessWidget {
  final Duration remaining;
  const _CountdownBoxes({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;
    return Row(
      children: [
        Expanded(child: _CountdownBox(value: days, label: 'দিন')),
        const _Colon(),
        Expanded(child: _CountdownBox(value: hours, label: 'ঘণ্টা')),
        const _Colon(),
        Expanded(child: _CountdownBox(value: minutes, label: 'মিনিট')),
        const _Colon(),
        Expanded(child: _CountdownBox(value: seconds, label: 'সেকেন্ড')),
      ],
    );
  }
}

class _CountdownBox extends StatelessWidget {
  final int value;
  final String label;
  const _CountdownBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Text(
        ':',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
      ),
    );
  }
}
