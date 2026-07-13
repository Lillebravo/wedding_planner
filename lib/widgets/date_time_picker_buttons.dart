import 'package:flutter/material.dart';

String formatIsoDate(DateTime date) => date.toIso8601String().split('T')[0];

String formatHHmm(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class DatePickerOutlinedButton extends StatelessWidget {
  final DateTime? selectedDate;
  final String pickDateLabel;
  final ValueChanged<DateTime> onPicked;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final EdgeInsetsGeometry? padding;
  final BorderSide? side;

  const DatePickerOutlinedButton({
    super.key,
    required this.selectedDate,
    required this.pickDateLabel,
    required this.onPicked,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.padding,
    this.side,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month),
      label: Text(
        selectedDate == null ? pickDateLabel : formatIsoDate(selectedDate!),
      ),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) {
          onPicked(picked);
        }
      },
      style: OutlinedButton.styleFrom(
        padding: padding,
        side: side,
      ),
    );
  }
}

class TimePickerOutlinedButton extends StatelessWidget {
  final TimeOfDay? selectedTime;
  final String pickTimeLabel;
  final bool required;
  final ValueChanged<TimeOfDay> onPicked;
  final TimeOfDay initialTime;
  final EdgeInsetsGeometry? padding;
  final BorderSide? side;

  const TimePickerOutlinedButton({
    super.key,
    required this.selectedTime,
    required this.pickTimeLabel,
    required this.onPicked,
    required this.initialTime,
    this.required = false,
    this.padding,
    this.side,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedTime == null
        ? required
              ? '$pickTimeLabel *'
              : pickTimeLabel
        : formatHHmm(selectedTime!);

    return OutlinedButton.icon(
      icon: const Icon(Icons.access_time),
      label: Text(label),
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: selectedTime ?? initialTime,
        );
        if (picked != null) {
          onPicked(picked);
        }
      },
      style: OutlinedButton.styleFrom(
        padding: padding,
        side: side,
      ),
    );
  }
}
