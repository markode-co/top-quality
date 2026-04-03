import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';
import 'package:top_quality/presentation/widgets/preferences_controls.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final locale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    if (user == null) {
      return EmptyPlaceholder(
        title: context.t(en: 'No active session', ar: 'لا توجد جلسة نشطة'),
        subtitle: context.t(
          en: 'Please sign in again to manage branch settings.',
          ar: 'يرجى تسجيل الدخول مرة أخرى لإدارة إعدادات الفرع.',
        ),
        icon: Icons.lock_outline,
      );
    }

    return ResponsiveListView(
      children: [
        SectionHeader(
          title: context.t(en: 'Branch settings', ar: 'إعدادات الفرع'),
          subtitle: context.t(
            en: 'Control language, theme, and workspace preferences for this branch.',
            ar: 'تحكم في اللغة والمظهر وتفضيلات مساحة العمل لهذا الفرع.',
          ),
        ),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'Profile summary', ar: 'ملخص الحساب'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(user.name),
                subtitle: Text(
                  context.t(en: 'User name', ar: 'اسم المستخدم'),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined),
                title: Text(user.email),
                subtitle: Text(
                  context.t(en: 'Email address', ar: 'البريد الإلكتروني'),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.apartment_outlined),
                title: Text(
                  (user.companyName ?? '').trim().isEmpty
                      ? context.t(
                          en: 'No branch assigned',
                          ar: 'لا يوجد فرع محدد',
                        )
                      : user.companyName!,
                ),
                subtitle: Text(
                  context.t(
                    en: 'Branch / organization',
                    ar: 'الفرع / المؤسسة',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'Display and language', ar: 'العرض واللغة'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              _ThemeModeSummary(themeMode: themeMode),
              const SizedBox(height: 14),
              PreferenceChoiceGroup<ThemeMode>(
                title: context.t(en: 'Theme mode', ar: 'وضع المظهر'),
                subtitle: context.t(
                  en: 'Changes apply immediately across the whole app.',
                  ar: 'يتم تطبيق التغيير مباشرة على جميع صفحات التطبيق.',
                ),
                value: themeMode,
                options: [
                  PreferenceOption(
                    value: ThemeMode.system,
                    label: context.t(en: 'System', ar: 'النظام'),
                    icon: Icons.brightness_auto_rounded,
                    description: context.t(
                      en: 'Follow the device or browser theme automatically.',
                      ar: 'يتبع مظهر الجهاز أو المتصفح تلقائيًا.',
                    ),
                  ),
                  PreferenceOption(
                    value: ThemeMode.light,
                    label: context.t(en: 'Light', ar: 'فاتح'),
                    icon: Icons.light_mode_rounded,
                    description: context.t(
                      en: 'Use the light palette for all pages and controls.',
                      ar: 'استخدم الألوان الفاتحة في جميع الصفحات والعناصر.',
                    ),
                  ),
                  PreferenceOption(
                    value: ThemeMode.dark,
                    label: context.t(en: 'Dark', ar: 'داكن'),
                    icon: Icons.dark_mode_rounded,
                    description: context.t(
                      en: 'Use the dark palette for all pages and controls.',
                      ar: 'استخدم الألوان الداكنة في جميع الصفحات والعناصر.',
                    ),
                  ),
                ],
                onChanged: (value) {
                  ref.read(appThemeModeProvider.notifier).state = value;
                },
              ),
              const SizedBox(height: 20),
              PreferenceChoiceGroup<Locale>(
                title: context.t(en: 'Language', ar: 'اللغة'),
                subtitle: context.t(
                  en: 'Choose the primary app language.',
                  ar: 'اختر لغة التطبيق الأساسية.',
                ),
                value: locale,
                options: const [
                  PreferenceOption(
                    value: Locale('en', 'US'),
                    label: 'English',
                    icon: Icons.translate_rounded,
                    description: 'Use English labels and messages.',
                  ),
                  PreferenceOption(
                    value: Locale('ar', 'EG'),
                    label: 'العربية',
                    icon: Icons.translate_rounded,
                    description: 'استخدام العربية في النصوص والرسائل.',
                  ),
                ],
                onChanged: (value) {
                  ref.read(appLocaleProvider.notifier).state = value;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(
                  en: 'Notifications and support',
                  ar: 'الإشعارات والدعم',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(
                  context.t(
                    en: 'Notification language',
                    ar: 'لغة الإشعارات',
                  ),
                ),
                subtitle: Text(
                  context.t(
                    en: 'Notifications follow your selected app language.',
                    ar: 'الإشعارات تتبع لغة التطبيق المحددة.',
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.support_agent_outlined),
                title: Text(
                  context.t(en: 'Contact support', ar: 'التواصل مع الدعم'),
                ),
                subtitle: Text(
                  context.t(
                    en: 'support@topquality.app',
                    ar: 'support@topquality.app',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
                icon: const Icon(Icons.logout_outlined),
                label: Text(
                  context.t(en: 'Sign out', ar: 'تسجيل الخروج'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeModeSummary extends StatelessWidget {
  const _ThemeModeSummary({required this.themeMode});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (themeMode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };
    final title = switch (themeMode) {
      ThemeMode.system => context.t(
          en: 'System theme',
          ar: 'مظهر النظام',
        ),
      ThemeMode.light => context.t(
          en: 'Light theme',
          ar: 'المظهر الفاتح',
        ),
      ThemeMode.dark => context.t(
          en: 'Dark theme',
          ar: 'المظهر الداكن',
        ),
    };
    final subtitle = switch (themeMode) {
      ThemeMode.system => context.t(
          en: 'The app matches your device setting.',
          ar: 'التطبيق يطابق إعداد الجهاز.',
        ),
      ThemeMode.light => context.t(
          en: 'Bright surfaces and darker text are active.',
          ar: 'الأسطح الفاتحة والنصوص الداكنة مفعلة الآن.',
        ),
      ThemeMode.dark => context.t(
          en: 'Dark surfaces and brighter icons are active.',
          ar: 'الأسطح الداكنة والأيقونات الأوضح مفعلة الآن.',
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.14),
          child: Icon(icon, color: scheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
