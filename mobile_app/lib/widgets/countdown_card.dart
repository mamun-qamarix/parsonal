import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/profile_service.dart';

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
        _target = data != null ? DateTime.parse(data['target_datetime']).toLocal() : null;
        _loading = false;
      });
    }
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 3650)), initialDate: _target ?? now.add(const Duration(days: 7)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_target ?? now));
    if (time == null) return;
    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
          child: Row(
            children: [
              const Icon(Icons.favorite, color: AppColors.halalGreen, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Next time together', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    if (target == null)
                      const Text('Tap to set a date', style: TextStyle(color: Colors.grey))
                    else if (remaining != null && remaining.isNegative)
                      const Text('It\'s (almost) here! 💚')
                    else if (remaining != null)
                      Text(_formatDuration(remaining), style: const TextStyle(color: AppColors.halalGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Icon(Icons.edit_calendar_outlined, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (days > 0) return '$days d ${hours}h ${minutes}m';
    return '${hours}h ${minutes}m ${seconds}s';
  }
}
