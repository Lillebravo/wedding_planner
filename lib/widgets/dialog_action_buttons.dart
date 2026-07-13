import 'package:flutter/material.dart';

class DialogCancelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const DialogCancelButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class DialogConfirmButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  const DialogConfirmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: destructive
          ? ElevatedButton.styleFrom(backgroundColor: Colors.red)
          : null,
      onPressed: onPressed,
      child: Text(
        label,
        style: destructive ? const TextStyle(color: Colors.white) : null,
      ),
    );
  }
}
