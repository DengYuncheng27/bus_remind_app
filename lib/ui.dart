import 'package:flutter/material.dart';

void notice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
Widget pageWidth(Widget child) => Center(
  heightFactor: 1,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 600),
    child: child,
  ),
);

class ErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const ErrorNotice(this.message, this.retry, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 32),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('重新试试')),
      ],
    ),
  );
}
