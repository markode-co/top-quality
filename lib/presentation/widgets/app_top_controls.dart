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
          ? context.t(en: 'Switch to English', ar: 'التحويل إلى الإنجليزية')
          : context.t(en: 'Switch to Arabic', ar: 'التحويل إلى العربية'),
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
    final system = mode == ThemeMode.system;

    return IconButton.filledTonal(
      onPressed: () {
        final next = switch (mode) {
          ThemeMode.system => ThemeMode.light,
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
        };
        ref.read(appThemeModeProvider.notifier).state = next;
      },
      tooltip: switch (mode) {
        ThemeMode.system => context.t(
            en: 'Theme follows system (tap for light mode)',
            ar: 'المظهر يتبع النظام (اضغط للانتقال إلى الفاتح)',
          ),
        ThemeMode.light => context.t(
            en: 'Light mode active (tap for dark mode)',
            ar: 'الوضع الفاتح مفعل (اضغط للانتقال إلى الداكن)',
          ),
        ThemeMode.dark => context.t(
            en: 'Dark mode active (tap for system mode)',
            ar: 'الوضع الداكن مفعل (اضغط للانتقال إلى التلقائي)',
          ),
      },
      icon: Icon(
        system
            ? Icons.brightness_auto_rounded
            : (dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
      ),
    );
  }
}
