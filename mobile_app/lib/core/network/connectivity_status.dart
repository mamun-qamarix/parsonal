import 'package:flutter/foundation.dart';

/// App-wide "are we currently showing possibly-stale cached data" signal.
/// Read-path services flip this to true when a network call fails and
/// they fall back to [LocalCache]; the next call that succeeds against
/// the live network flips it back to false. Purely informational -- it
/// never affects what's cached or how -- screens use it to show a small
/// "অফলাইন" banner so the user knows they're looking at saved data, not a
/// live feed. See DECISIONS.md.
class ConnectivityStatus {
  ConnectivityStatus._();
  static final instance = ConnectivityStatus._();
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);
}
