import 'package:flutter/material.dart';

class AppSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool dense;
  final bool filled;
  final Color? fillColor;

  const AppSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.dense = false,
    this.filled = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final border = filled
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          )
        : null;

    return TextField(
      decoration: InputDecoration(
        hintText: hintText,
        labelText: dense ? hintText : null,
        prefixIcon: Icon(Icons.search, size: dense ? 20 : null),
        isDense: dense,
        filled: filled,
        fillColor: fillColor,
        border: border,
      ),
      onChanged: onChanged,
    );
  }
}
