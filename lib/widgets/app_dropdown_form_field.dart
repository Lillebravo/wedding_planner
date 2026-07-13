import 'package:flutter/material.dart';

class AppDropdownFormField<T> extends StatelessWidget {
  final T? initialValue;
  final String labelText;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final bool isDense;

  const AppDropdownFormField({
    super.key,
    required this.initialValue,
    required this.labelText,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.isDense = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      decoration: InputDecoration(labelText: labelText),
      items: items,
      onChanged: onChanged,
      isExpanded: isExpanded,
      isDense: isDense,
    );
  }
}
