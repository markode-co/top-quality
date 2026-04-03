import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';
import 'package:top_quality/presentation/widgets/preferences_controls.dart';

class SystemSettingsPage extends ConsumerWidget {
  const SystemSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final locale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    if (user == null) {
      return EmptyPlaceholder(
        title: context.t(en: 'Restricted', ar: 'مقيد'),
        subtitle: context.t(
          en: 'Sign in to view system settings.',
          ar: 'سجل الدخول لعرض إعدادات النظام.',
        ),
        icon: Icons.settings_outlined,
      );
    }

    return ResponsiveListView(
      children: [
        SectionHeader(
          title: context.t(en: 'System settings', ar: 'إعدادات النظام'),
          subtitle: context.t(
            en: 'Update account details, language and support preferences.',
            ar: 'حدّث تفاصيل الحساب واللغة وتفضيلات الدعم.',
          ),
        ),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'User profile', ar: 'الملف الشخصي'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(user.name),
                subtitle: Text(
                  context.t(en: 'Your display name', ar: 'اسم العرض'),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined),
                title: Text(user.email),
                subtitle: Text(
                  context.t(en: 'Account email', ar: 'بريد الحساب'),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: Text(context.t(en: 'Role', ar: 'الدور')),
                subtitle: Text(context.roleLabel(user.role)),
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
                context.t(en: 'Preferences', ar: 'التفضيلات'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              PreferenceChoiceGroup<ThemeMode>(
                title: context.t(en: 'Theme', ar: 'المظهر'),
                subtitle: context.t(
                  en: 'Switch the app appearance immediately for every page.',
                  ar: 'بدّل مظهر التطبيق مباشرة في جميع الصفحات.',
                ),
                value: themeMode,
                options: [
                  PreferenceOption(
                    value: ThemeMode.system,
                    label: context.t(en: 'System', ar: 'النظام'),
                    icon: Icons.brightness_auto_rounded,
                    description: context.t(
                      en: 'Use the operating system theme automatically.',
                      ar: 'استخدم مظهر نظام التشغيل تلقائيًا.',
                    ),
                  ),
                  PreferenceOption(
                    value: ThemeMode.light,
                    label: context.t(en: 'Light', ar: 'فاتح'),
                    icon: Icons.light_mode_rounded,
                    description: context.t(
                      en: 'Best for bright rooms and daylight usage.',
                      ar: 'مناسب للأماكن المضيئة والاستخدام النهاري.',
                    ),
                  ),
                  PreferenceOption(
                    value: ThemeMode.dark,
                    label: context.t(en: 'Dark', ar: 'داكن'),
                    icon: Icons.dark_mode_rounded,
                    description: context.t(
                      en: 'Best for darker environments and lower glare.',
                      ar: 'مناسب للأماكن الداكنة وتقليل الإبهار.',
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
                  en: 'Select the interface language used across the app.',
                  ar: 'اختر لغة الواجهة المستخدمة في كامل التطبيق.',
                ),
                value: locale,
                options: const [
                  PreferenceOption(
                    value: Locale('en', 'US'),
                    label: 'English',
                    icon: Icons.translate_rounded,
                    description: 'Use English labels and interface text.',
                  ),
                  PreferenceOption(
                    value: Locale('ar', 'EG'),
                    label: 'العربية',
                    icon: Icons.translate_rounded,
                    description: 'استخدام العربية في الواجهة والعناصر.',
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
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.support_agent_outlined),
                title: Text(context.t(en: 'Support', ar: 'الدعم')),
                subtitle: Text(
                  context.t(
                    en: 'support@topquality.app',
                    ar: 'support@topquality.app',
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.document_scanner_outlined),
                title: Text(
                  context.t(en: 'Documentation', ar: 'التوثيق'),
                ),
                subtitle: Text(
                  context.t(
                    en: 'View user guides and release notes',
                    ar: 'عرض أدلة المستخدم وملاحظات الإصدارات',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
