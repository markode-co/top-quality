import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/domain/entities/organization_profile.dart';
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
  bool _isLoading = true;
  OrganizationProfile? _initialProfile;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _hydrateFallback();
    _loadOrganizationProfile();
  }

  void _hydrateFallback() {
    final user = ref.read(currentUserProvider);
    _nameController.text = (user?.companyName ?? '').trim().isEmpty
        ? 'Top Quality'
        : user!.companyName!;
    _emailController.text = user?.email ?? 'support@topquality.app';
    _phoneController.text = '+20 100 000 0000';
    _addressController.text = 'Cairo, Egypt';
  }

  Future<void> _loadOrganizationProfile() async {
    final user = ref.read(currentUserProvider);
    final companyId = user?.companyId?.trim() ?? '';

    if (companyId.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    try {
      final profile = await ref
          .read(wmsRepositoryProvider)
          .getOrganizationProfile(companyId);
      if (!mounted) return;

      final resolved =
          profile ??
          OrganizationProfile(
            companyId: companyId,
            name: _nameController.text.trim(),
            officialEmail: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            address: _addressController.text.trim(),
            inventoryAlertsEnabled: _inventoryAlerts,
            autoApproveRepeatOrders: _autoApproveOrders,
            requireInvoiceVerification: _invoiceVerification,
          );

      _applyProfile(resolved);
      setState(() {
        _initialProfile = resolved;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyProfile(OrganizationProfile profile) {
    _nameController.text = profile.name;
    _emailController.text = profile.officialEmail;
    _phoneController.text = profile.phone;
    _addressController.text = profile.address;
    _inventoryAlerts = profile.inventoryAlertsEnabled;
    _autoApproveOrders = profile.autoApproveRepeatOrders;
    _invoiceVerification = profile.requireInvoiceVerification;
  }

  OrganizationProfile? _buildDraftProfile() {
    final companyId =
        _initialProfile?.companyId ??
        ref.read(currentUserProvider)?.companyId?.trim() ??
        '';
    if (companyId.isEmpty) {
      return null;
    }

    return OrganizationProfile(
      companyId: companyId,
      name: _nameController.text.trim(),
      officialEmail: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      inventoryAlertsEnabled: _inventoryAlerts,
      autoApproveRepeatOrders: _autoApproveOrders,
      requireInvoiceVerification: _invoiceVerification,
    );
  }

  bool _sameProfile(
    OrganizationProfile left,
    OrganizationProfile right,
  ) {
    return left.name == right.name &&
        left.officialEmail == right.officialEmail &&
        left.phone == right.phone &&
        left.address == right.address &&
        left.inventoryAlertsEnabled == right.inventoryAlertsEnabled &&
        left.autoApproveRepeatOrders == right.autoApproveRepeatOrders &&
        left.requireInvoiceVerification == right.requireInvoiceVerification;
  }

  Future<void> _saveSettings() async {
    final currentUser = ref.read(currentUserProvider);
    final draft = _buildDraftProfile();
    if (currentUser == null || draft == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final noChangesMessage = context.t(
      en: 'No changes to save.',
      ar: 'لا توجد تغييرات للحفظ.',
    );
    final successMessage = context.t(
      en: 'Organization settings updated successfully.',
      ar: 'تم تحديث إعدادات المنظمة بنجاح.',
    );
    final failureMessage = context.t(
      en: 'Failed to save organization settings.',
      ar: 'فشل حفظ إعدادات المنظمة.',
    );

    final baseline = _initialProfile;
    if (baseline != null && _sameProfile(baseline, draft)) {
      messenger.showSnackBar(SnackBar(content: Text(noChangesMessage)));
      return;
    }

    if (draft.name.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.t(
              en: 'Organization name is required.',
              ar: 'اسم المنظمة مطلوب.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .updateOrganizationProfile(draft);
      if (!mounted) return;
      setState(() {
        _initialProfile = draft;
      });
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ResponsiveListView(
          children: [
            SectionHeader(
              title: context.t(en: 'Organization settings', ar: 'إعدادات المنظمة'),
              subtitle: context.t(
                en: 'Manage company profile, branch governance, and operational policies.',
                ar: 'إدارة ملف المنظمة وحوكمة الفروع وسياسات التشغيل.',
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
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Organization name',
                        ar: 'اسم المنظمة',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Official email',
                        ar: 'البريد الرسمي',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Main phone',
                        ar: 'الهاتف الرئيسي',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Head office address',
                        ar: 'عنوان المكتب الرئيسي',
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
                    context.t(en: 'Operational policies', ar: 'سياسات التشغيل'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    value: _inventoryAlerts,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.t(
                        en: 'Low stock alerts',
                        ar: 'تنبيهات انخفاض المخزون',
                      ),
                    ),
                    subtitle: Text(
                      context.t(
                        en: 'Notify branch managers when stock levels reach critical limits.',
                        ar: 'تنبيه مديري الفروع عند وصول المخزون للحد الحرج.',
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _inventoryAlerts = value),
                  ),
                  const Divider(),
                  SwitchListTile(
                    value: _autoApproveOrders,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.t(
                        en: 'Auto-approve repeated orders',
                        ar: 'اعتماد الطلبات المتكررة تلقائيًا',
                      ),
                    ),
                    subtitle: Text(
                      context.t(
                        en: 'Fast-track trusted recurring customer orders.',
                        ar: 'تسريع معالجة طلبات العملاء المتكررة الموثوقين.',
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _autoApproveOrders = value),
                  ),
                  const Divider(),
                  SwitchListTile(
                    value: _invoiceVerification,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.t(
                        en: 'Require invoice verification',
                        ar: 'إلزام التحقق من الفاتورة',
                      ),
                    ),
                    subtitle: Text(
                      context.t(
                        en: 'Add a mandatory verification step before shipping completion.',
                        ar: 'إضافة خطوة تحقق إلزامية قبل إتمام الشحن.',
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _invoiceVerification = value),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isSaving || _isLoading ? null : _saveSettings,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      context.t(en: 'Save settings', ar: 'حفظ الإعدادات'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_isLoading)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(),
              ),
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
