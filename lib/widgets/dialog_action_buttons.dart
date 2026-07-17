import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DialogEnterSubmit extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSubmit;
  final bool autofocus;

  const DialogEnterSubmit({
    super.key,
    required this.child,
    required this.onSubmit,
    this.autofocus = true,
  });

  @override
  Widget build(BuildContext context) {
    if (onSubmit == null) {
      return child;
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              onSubmit!.call();
              return null;
            },
          ),
        },
        child: Focus(autofocus: autofocus, child: child),
      ),
    );
  }
}

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
