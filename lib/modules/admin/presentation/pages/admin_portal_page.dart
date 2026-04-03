import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_constants.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/modules/admin/presentation/pages/organization_page.dart';
import 'package:top_quality/modules/customers/presentation/pages/customers_page.dart';
import 'package:top_quality/modules/inventory/presentation/pages/inventory_page.dart';
import 'package:top_quality/modules/orders/presentation/pages/orders_page.dart';
import 'package:top_quality/modules/reports/presentation/pages/advanced_reports_page.dart';
import 'package:top_quality/modules/settings/presentation/pages/settings_page.dart';
import 'package:top_quality/modules/users/presentation/pages/users_page.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';
import 'package:top_quality/presentation/widgets/standalone_page_scaffold.dart';

class AdminPortalPage extends ConsumerWidget {
  const AdminPortalPage({
    super.key,
    required this.onOpenOrder,
    required this.onCreateOrder,
  });

  final ValueChanged<String> onOpenOrder;
  final VoidCallback onCreateOrder;

  Future<void> _openPortalPage(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StandalonePageScaffold(
          title: title,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || !AppConstants.isAdminPortalEmail(user.email)) {
      return EmptyPlaceholder(
        title: context.t(en: 'Restricted area', ar: 'منطقة مقيدة'),
        subtitle: context.t(
          en: 'This admin portal is available only for approved credentials.',
          ar: 'بوابة الأدمن متاحة فقط للحسابات المصرح لها.',
        ),
        icon: Icons.admin_panel_settings_outlined,
      );
    }

    final orders = ref.watch(ordersProvider).valueOrNull ?? const [];
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final employees = ref.watch(usersProvider).valueOrNull ?? const [];
    final dashboard = ref.watch(dashboardProvider).valueOrNull;
    final localeTag = Localizations.localeOf(context).toString();

    final companyLabel = (user.companyName ?? '').trim().isEmpty
        ? context.t(en: 'Organization management', ar: 'إدارة المنظمة')
        : user.companyName!;

    final ordersByStatus = dashboard?.ordersByStatus ?? {};
    final summaryCards = [
      _AdminMetric(
        label: context.t(en: 'Orders', ar: 'الطلبات'),
        value: '${dashboard?.totalOrders ?? orders.length}',
        icon: Icons.receipt_long_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      _AdminMetric(
        label: context.t(en: 'Products', ar: 'المنتجات'),
        value: '${products.length}',
        icon: Icons.inventory_2_outlined,
        color: Theme.of(context).colorScheme.secondary,
      ),
      _AdminMetric(
        label: context.t(en: 'Employees', ar: 'الموظفون'),
        value: '${employees.length}',
        icon: Icons.group_outlined,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      _AdminMetric(
        label: context.t(en: 'Revenue', ar: 'الإيراد'),
        value: AppFormatters.currency(dashboard?.revenue ?? 0, localeTag),
        icon: Icons.payments_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
    ];

    final statusCards = [
      _AdminMetric(
        label: context.t(en: 'Pending', ar: 'قيد التنفيذ'),
        value: '${ordersByStatus[OrderStatus.entered] ?? 0}',
        icon: Icons.timelapse_outlined,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      _AdminMetric(
        label: context.t(en: 'In review', ar: 'قيد المراجعة'),
        value: '${ordersByStatus[OrderStatus.checked] ?? 0}',
        icon: Icons.fact_check_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      _AdminMetric(
        label: context.t(en: 'Ready to ship', ar: 'جاهز للشحن'),
        value: '${ordersByStatus[OrderStatus.approved] ?? 0}',
        icon: Icons.local_shipping_outlined,
        color: Theme.of(context).colorScheme.secondary,
      ),
      _AdminMetric(
        label: context.t(en: 'Low stock', ar: 'مخزون منخفض'),
        value:
            '${dashboard?.lowStockAlerts ?? products.where((product) => product.isLowStock).length}',
        icon: Icons.warning_amber_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
    ];

    final recentOrders = dashboard?.recentOrders.take(4).toList() ?? [];
    final topUsers = dashboard?.userActivity.take(4).toList() ?? [];

    return ResponsiveListView(
      children: [
        _AdminHero(
          companyLabel: companyLabel,
          adminEmail: user.email,
          subtitle: context.t(
            en: 'Professional control center for operations, branches, and performance.',
            ar: 'مركز تحكم احترافي لإدارة العمليات والفروع والأداء.',
          ),
        ),
        const SizedBox(height: 18),
        _PanelCard(
          title: context.t(en: 'Performance snapshot', ar: 'ملخص الأداء'),
          child: _MetricGrid(metrics: summaryCards),
        ),
        const SizedBox(height: 18),
        _PanelCard(
          title: context.t(en: 'Operational status', ar: 'الحالة التشغيلية'),
          child: _MetricGrid(metrics: statusCards),
        ),
        const SizedBox(height: 18),
        _PanelCard(
          title: context.t(en: 'Control center', ar: 'مركز التحكم'),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionButton(
                icon: Icons.add,
                label: context.t(en: 'Create order', ar: 'إنشاء طلب'),
                filled: true,
                onPressed: onCreateOrder,
              ),
              _ActionButton(
                icon: Icons.receipt_long_outlined,
                label: context.t(en: 'Manage orders', ar: 'إدارة الطلبات'),
                onPressed: () => _openPortalPage(
                  context,
                  title: context.t(en: 'Orders', ar: 'الطلبات'),
                  child: OrdersPage(
                    onOpenOrder: onOpenOrder,
                    onCreateOrder: onCreateOrder,
                  ),
                ),
              ),
              _ActionButton(
                icon: Icons.business_outlined,
                label: context.t(en: 'Organization settings', ar: 'إعدادات المنظمة'),
                onPressed: () => _openPortalPage(
                  context,
                  title: context.t(
                    en: 'Organization settings',
                    ar: 'إعدادات المنظمة',
                  ),
                  child: const OrganizationPage(),
                ),
              ),
              _ActionButton(
                icon: Icons.apartment_outlined,
                label: context.t(en: 'Branch management', ar: 'إدارة الفروع'),
                onPressed: () => _openPortalPage(
                  context,
                  title: context.t(en: 'Branch management', ar: 'إدارة الفروع'),
                  child: const CustomersPage(),
                ),
              ),
              _ActionButton(
                icon: Icons.settings_outlined,
                label: context.t(en: 'Branch settings', ar: 'إعدادات الفروع'),
                onPressed: () => _openPortalPage(
                  context,
                  title: context.t(en: 'Branch settings', ar: 'إعدادات الفروع'),
                  child: const SettingsPage(),
                ),
              ),
              _ActionButton(
                icon: Icons.auto_graph_outlined,
                label: context.t(en: 'Advanced analytics', ar: 'التقارير المتقدمة'),
                onPressed: () => _openPortalPage(
                  context,
                  title: context.t(
                    en: 'Advanced analytics',
                    ar: 'التقارير المتقدمة',
                  ),
                  child: const AdvancedReportsPage(),
                ),
              ),
              _ActionButton(
                icon: Icons.inventory_2_outlined,
                label: context.t(en: 'Manage products', ar: 'إدارة المنتجات'),
                onPressed: () => _openPortalPage(
                  context,
                  title: context.t(en: 'Manage products', ar: 'إدارة المنتجات'),
                  child: const InventoryPage(),
                ),
              ),
              _ActionButton(
                icon: Icons.group_outlined,
                label: context.t(en: 'Manage employees', ar: 'إدارة الموظفين'),
                onPressed: () => _openPortalPage(
                  context,
                  title: context.t(en: 'Manage employees', ar: 'إدارة الموظفين'),
                  child: const UsersPage(),
                ),
              ),
            ],
          ),
        ),
        if (recentOrders.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PanelCard(
            title: context.t(en: 'Recent orders', ar: 'أحدث الطلبات'),
            child: Column(
              children: recentOrders.map((order) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  title: Text(order.customerName),
                  subtitle: Text(
                    '#${order.orderNo} • ${context.orderStatusLabel(order.status)}',
                  ),
                  trailing: Text(
                    AppFormatters.currency(order.totalRevenue, localeTag),
                  ),
                  onTap: () => onOpenOrder(order.id),
                );
              }).toList(),
            ),
          ),
        ],
        if (topUsers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PanelCard(
            title: context.t(en: 'Top activity', ar: 'أعلى نشاط'),
            child: Column(
              children: topUsers.map((activity) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  title: Text(activity.userName),
                  subtitle: Text(context.roleLabel(activity.role)),
                  trailing: Text('${activity.totalActions}'),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _AdminHero extends StatelessWidget {
  const _AdminHero({
    required this.companyLabel,
    required this.adminEmail,
    required this.subtitle,
  });

  final String companyLabel;
  final String adminEmail;
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
            blurRadius: 24,
            offset: const Offset(0, 14),
            color: scheme.onSurface.withAlpha(32),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(en: 'Admin Control Center', ar: 'مركز تحكم الأدمن'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimary.withAlpha(230),
                  ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroChip(label: companyLabel, icon: Icons.business_outlined),
                _HeroChip(label: adminEmail, icon: Icons.verified_user_outlined),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_AdminMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 3.2 : 2.5,
          children: metrics.map((metric) => _MetricCard(metric: metric)).toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _AdminMetric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: metric.color.withValues(alpha: 0.15),
              child: Icon(metric.icon, size: 20, color: metric.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: 220,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
    return child;
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.onPrimary.withAlpha(48),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.onPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMetric {
  const _AdminMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}
