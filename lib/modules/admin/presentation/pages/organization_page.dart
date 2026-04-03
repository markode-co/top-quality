import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/domain/entities/employee_draft.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class OrganizationPage extends ConsumerStatefulWidget {
  const OrganizationPage({super.key});

  @override
  ConsumerState<OrganizationPage> createState() => _OrganizationPageState();
}

class _OrganizationPageState extends ConsumerState<OrganizationPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  bool _inventoryAlerts = true;
  bool _autoApproveOrders = false;
  bool _invoiceVerification = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    final orgName = (user?.companyName ?? '').trim();
    _nameController = TextEditingController(
      text: orgName.isEmpty ? 'Top Quality' : orgName,
    );
    _emailController = TextEditingController(
      text: user?.email.trim().isEmpty ?? true
          ? 'support@topquality.app'
          : user!.email,
    );
    _phoneController = TextEditingController(text: '+20 100 000 0000');
    _addressController = TextEditingController(text: 'Cairo, Egypt');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final noChangesMessage = context.t(
      en: 'No changes to save.',
      ar: 'لا يوجد تغييرات للحفظ.',
    );
    final successMessage = context.t(
      en: 'Organization and branch settings updated successfully.',
      ar: 'تم تحديث إعدادات المنظمة والفروع بنجاح.',
    );
    final failureMessage = context.t(
      en: 'Failed to save organization settings.',
      ar: 'فشل حفظ إعدادات المنظمة.',
    );
    final newCompanyName = _nameController.text.trim();
    final currentCompanyName = (currentUser.companyName ?? '').trim();
    if (newCompanyName == currentCompanyName) {
      messenger.showSnackBar(SnackBar(content: Text(noChangesMessage)));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .updateEmployee(
            EmployeeDraft(
              id: currentUser.id,
              name: currentUser.name,
              email: currentUser.email,
              password: null,
              companyName: newCompanyName.isEmpty ? null : newCompanyName,
              role: currentUser.role,
              permissions: currentUser.permissions,
              isActive: currentUser.isActive,
            ),
          );
      if (!mounted) return;
      ref.invalidate(sessionProvider);
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveListView(
      children: [
        SectionHeader(
          title: context.t(en: 'Organization settings', ar: 'إعدادات المنظمة'),
          subtitle: context.t(
            en: 'Manage company profile, branch governance, and operational policies.',
            ar: 'إدارة ملف المنظمة، حوكمة الفروع، وسياسات التشغيل.',
          ),
        ),
        _HeroCard(
          title: _nameController.text.trim().isEmpty
              ? context.t(en: 'Organization', ar: 'المنظمة')
              : _nameController.text.trim(),
          subtitle: context.t(
            en: 'Central control for branches and operations',
            ar: 'مركز التحكم الرئيسي للفروع والعمليات',
          ),
        ),
        const SizedBox(height: 18),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'Organization profile', ar: 'ملف المنظمة'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Organization name', ar: 'اسم المنظمة'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Official email', ar: 'البريد الرسمي'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Main phone', ar: 'الهاتف الرئيسي'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Head office address', ar: 'عنوان المكتب الرئيسي'),
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
                context.t(en: 'Operational policies', ar: 'سياسات التشغيل'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _inventoryAlerts,
                contentPadding: EdgeInsets.zero,
                title: Text(context.t(en: 'Low stock alerts', ar: 'تنبيهات انخفاض المخزون')),
                subtitle: Text(
                  context.t(
                    en: 'Notify branch managers when stock levels reach critical limits.',
                    ar: 'تنبيه مديري الفروع عند وصول المخزون للحد الحرج.',
                  ),
                ),
                onChanged: (value) => setState(() => _inventoryAlerts = value),
              ),
              const Divider(),
              SwitchListTile(
                value: _autoApproveOrders,
                contentPadding: EdgeInsets.zero,
                title: Text(context.t(en: 'Auto-approve repeated orders', ar: 'اعتماد الطلبات المتكررة تلقائيًا')),
                subtitle: Text(
                  context.t(
                    en: 'Fast-track trusted recurring customer orders.',
                    ar: 'تسريع معالجة طلبات العملاء المتكررة الموثوقين.',
                  ),
                ),
                onChanged: (value) => setState(() => _autoApproveOrders = value),
              ),
              const Divider(),
              SwitchListTile(
                value: _invoiceVerification,
                contentPadding: EdgeInsets.zero,
                title: Text(context.t(en: 'Require invoice verification', ar: 'إلزام التحقق من الفاتورة')),
                subtitle: Text(
                  context.t(
                    en: 'Add a mandatory verification step before shipping completion.',
                    ar: 'إضافة خطوة تحقق إلزامية قبل إتمام الشحن.',
                  ),
                ),
                onChanged: (value) => setState(() => _invoiceVerification = value),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: const Icon(Icons.save_outlined),
                label: Text(context.t(en: 'Save settings', ar: 'حفظ الإعدادات')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: scheme.onSurface.withAlpha(28),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimary.withAlpha(220),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
