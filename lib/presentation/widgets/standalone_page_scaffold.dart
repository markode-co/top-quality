import 'package:flutter/material.dart';
import 'package:top_quality/presentation/widgets/app_top_controls.dart';

class StandalonePageScaffold extends StatelessWidget {
  const StandalonePageScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          LanguageToggle(),
          SizedBox(width: 8),
          ThemeModeToggle(),
          SizedBox(width: 12),
        ],
      ),
      body: child,
    );
  }
}
