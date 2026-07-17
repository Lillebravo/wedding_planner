import 'package:flutter/material.dart';

import 'app_dropdown_form_field.dart';
import 'app_labeled_text_field.dart';
import 'dialog_action_buttons.dart';
import 'dialog_title_with_close.dart';

class TableFormDialog extends StatelessWidget {
  final String titleText;
  final String nameLabelText;
  final String seatsLabelText;
  final String shapeLabelText;
  final String saveLabelText;
  final TextEditingController nameController;
  final TextEditingController seatsController;
  final String selectedShape;
  final List<DropdownMenuItem<String>> shapeItems;
  final ValueChanged<String> onShapeChanged;
  final VoidCallback onSubmit;
  final ValueChanged<String>? onSeatsChanged;
  final bool canSubmit;
  final Widget? extraContent;
  final bool scrollable;

  const TableFormDialog({
    super.key,
    required this.titleText,
    required this.nameLabelText,
    required this.seatsLabelText,
    required this.shapeLabelText,
    required this.saveLabelText,
    required this.nameController,
    required this.seatsController,
    required this.selectedShape,
    required this.shapeItems,
    required this.onShapeChanged,
    required this.onSubmit,
    this.onSeatsChanged,
    this.canSubmit = true,
    this.extraContent,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final contentColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppLabeledTextField(
          controller: nameController,
          labelText: nameLabelText,
          onSubmitted: (_) => onSubmit(),
        ),
        AppLabeledTextField(
          controller: seatsController,
          labelText: seatsLabelText,
          keyboardType: TextInputType.number,
          onChanged: onSeatsChanged,
          onSubmitted: (_) => onSubmit(),
        ),
        AppDropdownFormField<String>(
          initialValue: selectedShape,
          labelText: shapeLabelText,
          items: shapeItems,
          onChanged: (value) => onShapeChanged(value ?? selectedShape),
        ),
        if (extraContent != null) ...[
          const SizedBox(height: 16),
          extraContent!,
        ],
      ],
    );

    return DialogEnterSubmit(
      onSubmit: canSubmit ? onSubmit : null,
      child: AlertDialog(
        title: DialogTitleWithClose(
          titleText: titleText,
          onClose: () => Navigator.pop(context),
        ),
        content: scrollable ? SingleChildScrollView(child: contentColumn) : contentColumn,
        actions: [
          DialogConfirmButton(
            label: saveLabelText,
            onPressed: canSubmit ? onSubmit : null,
          ),
        ],
      ),
    );
  }
}
