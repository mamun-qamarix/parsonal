import 'package:flutter/material.dart';

/// A password/PIN text field with a show/hide (eye) toggle, used
/// everywhere a password or PIN is entered so the user can check what
/// they typed before submitting.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final TextInputType? keyboardType;
  final void Function(String)? onSubmitted;
  final bool autofocus;

  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.keyboardType,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        suffixIcon: IconButton(
          icon: Icon(_obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          tooltip: _obscured ? 'পাসওয়ার্ড দেখান' : 'পাসওয়ার্ড লুকান',
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}
