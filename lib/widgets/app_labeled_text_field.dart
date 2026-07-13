import 'package:flutter/material.dart';

class AppLabeledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  const AppLabeledTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.onChanged,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: labelText),
    );
  }
}
