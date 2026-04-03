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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foregroundColor =
        isArabic
            ? (theme.brightness == Brightness.dark
                ? scheme.primary
                : scheme.onSurface)
            : scheme.onSurfaceVariant;

    return IconButton(
      onPressed: () {
        ref.read(appLocaleProvider.notifier).state = isArabic
            ? const Locale('en', 'US')
            : const Locale('ar', 'EG');
      },
      tooltip: isArabic
          ? context.t(
            en: 'Switch to English',
            ar: 'التحويل إلى الإنجليزية',
          )
          : context.t(
            en: 'Switch to Arabic',
            ar: 'التحويل إلى العربية',
          ),
      style: _topBarToggleStyle(
        context,
        active: isArabic,
      ).copyWith(
        foregroundColor: WidgetStatePropertyAll(foregroundColor),
      ),
      icon: Text(
        isArabic ? 'AR' : 'EN',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: foregroundColor,
        ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foregroundColor =
        dark
            ? scheme.primary
            : (system ? scheme.onSurfaceVariant : scheme.onSurface);

    return IconButton(
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
      style: _topBarToggleStyle(
        context,
        active: dark,
        neutral: system,
      ).copyWith(
        foregroundColor: WidgetStatePropertyAll(foregroundColor),
      ),
      icon: Icon(
        system
            ? Icons.brightness_auto_rounded
            : (dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
        color: foregroundColor,
      ),
    );
  }
}

ButtonStyle _topBarToggleStyle(
  BuildContext context, {
  required bool active,
  bool neutral = false,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final backgroundColor =
      active
          ? scheme.primary.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10,
          )
          : neutral
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.75)
          : scheme.surfaceContainerHigh.withValues(alpha: 0.9);

  return IconButton.styleFrom(
    backgroundColor: backgroundColor,
    foregroundColor: scheme.onSurface,
    minimumSize: const Size.square(42),
    padding: const EdgeInsets.all(10),
    side: BorderSide(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    ),
  );
}
