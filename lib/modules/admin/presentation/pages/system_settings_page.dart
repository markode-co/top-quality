import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class SystemSettingsPage extends ConsumerStatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  ConsumerState<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends ConsumerState<SystemSettingsPage> {
  Locale? _selectedLocale;
  ThemeMode? _selectedThemeMode;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final locale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    _selectedLocale ??= locale;
    _selectedThemeMode ??= themeMode;

    if (user == null) {
      return EmptyPlaceholder(
        title: context.t(en: 'Restricted', ar: 'مقيد'),
        subtitle: context.t(
          en: 'Sign in to view system settings.',
          ar: 'سجّل الدخول لعرض إعدادات النظام.',
        ),
        icon: Icons.settings_outlined,
      );
    }

    final hasChanges = _selectedLocale != locale || _selectedThemeMode != themeMode;

    return ResponsiveListView(
      children: [
        SectionHeader(
          title: context.t(en: 'System settings', ar: 'إعدادات النظام'),
          subtitle: context.t(
            en: 'Update account details, language and support preferences.',
            ar: 'تحديث تفاصيل الحساب، اللغة وتفضيلات الدعم.',
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
                leading: const Icon(Icons.person),
                title: Text(user.name),
                subtitle: Text(context.t(en: 'Your display name', ar: 'اسم العرض')),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email),
                title: Text(user.email),
                subtitle: Text(context.t(en: 'Account email', ar: 'البريد الحسابي')),
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
              DropdownButtonFormField<Locale>(
                initialValue: _selectedLocale,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Language', ar: 'اللغة'),
                ),
                items: const [
                  DropdownMenuItem(value: Locale('en', 'US'), child: Text('English')),
                  DropdownMenuItem(value: Locale('ar', 'EG'), child: Text('العربية')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedLocale = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<ThemeMode>(
                initialValue: _selectedThemeMode,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Theme', ar: 'السمة'),
                ),
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(context.t(en: 'System default', ar: 'مطابق للنظام')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(context.t(en: 'Light', ar: 'فاتح')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(context.t(en: 'Dark', ar: 'داكن')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedThemeMode = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  if (!hasChanges) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t(
                        en: 'No changes to save.',
                        ar: 'لا توجد تغييرات للحفظ.',
                      ))),
                    );
                    return;
                  }

                  ref.read(appLocaleProvider.notifier).state = _selectedLocale!;
                  ref.read(appThemeModeProvider.notifier).state = _selectedThemeMode!;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t(
                      en: 'Display preferences saved.',
                      ar: 'تم حفظ تفضيلات العرض.',
                    ))),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: Text(context.t(en: 'Save preferences', ar: 'حفظ التفضيلات')),
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
                subtitle: Text(context.t(en: 'support@topquality.app', ar: 'support@topquality.app')),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.document_scanner_outlined),
                title: Text(context.t(en: 'Documentation', ar: 'التوثيق')),
                subtitle: Text(context.t(en: 'View user guides and release notes', ar: 'عرض أدلة المستخدم وإصدارات الميزات')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
