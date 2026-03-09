import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';

class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    final isArabic = locale.languageCode.toLowerCase() == 'ar';

    return IconButton.filledTonal(
      onPressed: () {
        ref.read(appLocaleProvider.notifier).state = isArabic
            ? const Locale('en', 'US')
            : const Locale('ar', 'EG');
      },
      tooltip: isArabic
          ? context.t(en: 'Switch to English', ar: 'التبديل إلى الإنجليزية')
          : context.t(en: 'Switch to Arabic', ar: 'التبديل إلى العربية'),
      icon: Text(
        isArabic ? 'AR' : 'EN',
        style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4),
      ),
    );
  }
}

class ThemeModeToggle extends ConsumerWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    final dark = mode == ThemeMode.dark;

    return IconButton.filledTonal(
      onPressed: () {
        ref.read(appThemeModeProvider.notifier).state = dark
            ? ThemeMode.light
            : ThemeMode.dark;
      },
      tooltip: dark
          ? context.t(
              en: 'Switch to light mode',
              ar: 'التبديل إلى الوضع الفاتح',
            )
          : context.t(
              en: 'Switch to dark mode',
              ar: 'التبديل إلى الوضع الداكن',
            ),
      icon: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
    );
  }
}
