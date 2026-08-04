import 'package:flutter/material.dart';

/// Lets code show a SnackBar that survives a navigation pop happening in
/// the same frame (e.g. popping back to AuthGate right after showing an
/// informational message) -- a Scaffold-local ScaffoldMessenger would be
/// disposed along with the route being popped.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
