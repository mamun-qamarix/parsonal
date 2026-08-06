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
    final primary = Theme.of(context).colorScheme.primary;

    // Everything -- icon, title, and the countdown itself -- fits on one
    // compact line now, per request: no separate row for the boxes below,
    // no colons between them (the boxes themselves are separator enough).
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _pick,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Iconsax.profile_2user_copy, color: primary, size: 18),
              const SizedBox(width: 6),
              const Text(
                'কবে দেখা হবে',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: target == null
                        ? const Text(
                            'তারিখ ঠিক করতে ট্যাপ করুন',
                            style: TextStyle(color: Colors.grey, fontSize: 11),
                          )
                        : (remaining != null && remaining.isNegative)
                        ? Text(
                            'এই তো, একদম কাছে! 💚',
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          )
                        : remaining != null
                        ? _CompactCountdown(remaining: remaining, color: primary)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Days/hours/minutes/seconds as small boxes in a single row -- the unit
/// letter sits inside each box next to the number instead of a separate
/// label underneath, and there's no colon between boxes (the boxes
/// themselves already read as distinct). See DECISIONS.md.
class _CompactCountdown extends StatelessWidget {
  final Duration remaining;
  final Color color;
  const _CompactCountdown({required this.remaining, required this.color});

  @override
  Widget build(BuildContext context) {
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _box(days, 'দি'),
        const SizedBox(width: 3),
        _box(hours, 'ঘ'),
        const SizedBox(width: 3),
        _box(minutes, 'মি'),
        const SizedBox(width: 3),
        _box(seconds, 'সে'),
      ],
    );
  }

  Widget _box(int value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${value.toString().padLeft(2, '0')}$unit',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
