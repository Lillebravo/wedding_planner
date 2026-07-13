import 'package:flutter/material.dart';

class DialogTitleWithClose extends StatelessWidget {
  final String titleText;
  final VoidCallback onClose;

  const DialogTitleWithClose({
    super.key,
    required this.titleText,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(titleText)),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}
