import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

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
          ar: 'يرجى تسجيل الدخول مرة أخرى لإدارة إعدادات الفروع.',
        ),
        icon: Icons.lock_outline,
      );
    }

    return ResponsiveListView(
      children: [
        SectionHeader(
          title: context.t(en: 'Branch settings', ar: 'إعدادات الفروع'),
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
                subtitle: Text(context.t(en: 'User name', ar: 'اسم المستخدم')),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined),
                title: Text(user.email),
                subtitle: Text(context.t(en: 'Email address', ar: 'البريد الإلكتروني')),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.apartment_outlined),
                title: Text(
                  (user.companyName ?? '').trim().isEmpty
                      ? context.t(en: 'No branch assigned', ar: 'لا يوجد فرع محدد')
                      : user.companyName!,
                ),
                subtitle: Text(context.t(en: 'Branch / organization', ar: 'الفرع / المنظمة')),
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
              DropdownButtonFormField<Locale>(
                initialValue: locale,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Language', ar: 'اللغة'),
                ),
                items: const [
                  DropdownMenuItem(value: Locale('en', 'US'), child: Text('English')),
                  DropdownMenuItem(value: Locale('ar', 'EG'), child: Text('العربية')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref.read(appLocaleProvider.notifier).state = value;
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ThemeMode>(
                initialValue: themeMode,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Theme mode', ar: 'وضع المظهر'),
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
                    ref.read(appThemeModeProvider.notifier).state = value;
                  }
                },
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.t(
                          en: 'Display preferences updated successfully.',
                          ar: 'تم تحديث إعدادات العرض بنجاح.',
                        ),
                      ),
                    ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'Notifications and support', ar: 'الإشعارات والدعم'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(context.t(en: 'Notification language', ar: 'لغة الإشعارات')),
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
                title: Text(context.t(en: 'Contact support', ar: 'تواصل مع الدعم')),
                subtitle: Text(context.t(
                  en: 'support@topquality.app',
                  ar: 'support@topquality.app',
                )),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                icon: const Icon(Icons.logout_outlined),
                label: Text(context.t(en: 'Sign out', ar: 'تسجيل الخروج')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
