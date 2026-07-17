import 'package:flutter/material.dart';

import 'dialog_action_buttons.dart';
import 'dialog_title_with_close.dart';

class AppConfirmDialog extends StatelessWidget {
  final String titleText;
  final String contentText;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final bool showCancelButton;

  const AppConfirmDialog({
    super.key,
    required this.titleText,
    required this.contentText,
    required this.confirmLabel,
    required this.cancelLabel,
    this.destructive = false,
    this.showCancelButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return DialogEnterSubmit(
      onSubmit: () => Navigator.pop(context, true),
      child: AlertDialog(
        title: DialogTitleWithClose(
          titleText: titleText,
          onClose: () => Navigator.pop(context, false),
        ),
        content: Text(contentText),
        actions: [
          if (showCancelButton)
            DialogCancelButton(
              label: cancelLabel,
              onPressed: () => Navigator.pop(context, false),
            ),
          DialogConfirmButton(
            label: confirmLabel,
            destructive: destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }
}
