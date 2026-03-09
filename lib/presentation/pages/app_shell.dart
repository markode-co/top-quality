import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/modules/auth/presentation/pages/login_page.dart';
import 'package:top_quality/modules/dashboard/presentation/pages/dashboard_page.dart';
import 'package:top_quality/modules/inventory/presentation/pages/inventory_page.dart';
import 'package:top_quality/modules/notifications/presentation/pages/notifications_page.dart';
import 'package:top_quality/modules/orders/presentation/pages/create_order_page.dart';
import 'package:top_quality/modules/orders/presentation/pages/order_detail_page.dart';
import 'package:top_quality/modules/orders/presentation/pages/orders_page.dart';
import 'package:top_quality/modules/reports/presentation/pages/reports_page.dart';
import 'package:top_quality/modules/users/presentation/pages/users_page.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/app_top_controls.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const LoginPage();
    }

    final destinations = _buildDestinations(context, user);
    if (destinations.isEmpty) {
      return _NoPermissionsScaffold(
        user: user,
        onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
      );
    }

    final safeIndex =
        _selectedIndex >= 0 && _selectedIndex < destinations.length
        ? _selectedIndex
        : 0;
    if (safeIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() => _selectedIndex = safeIndex);
      });
    }

    final currentDestination = destinations[safeIndex];
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    final wide = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentDestination.label),
        actions: [
          Chip(label: Text(context.roleLabel(user.role))),
          const SizedBox(width: 8),
          const LanguageToggle(),
          const SizedBox(width: 8),
          const ThemeModeToggle(),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            child: IconButton(
              onPressed: () => _goTo('notifications', destinations),
              icon: const Icon(Icons.notifications_none_outlined),
              tooltip: context.t(en: 'Notifications', ar: 'الإشعارات'),
            ),
          ),
          IconButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            tooltip: context.t(en: 'Sign out', ar: 'تسجيل الخروج'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: safeIndex,
                  onDestinationSelected: (value) =>
                      setState(() => _selectedIndex = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final item in destinations)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(item.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: currentDestination.page),
              ],
            )
          : currentDestination.page,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (value) =>
                  setState(() => _selectedIndex = value),
              destinations: [
                for (final item in destinations)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  ),
              ],
            ),
    );
  }

  List<_AppDestination> _buildDestinations(BuildContext context, AppUser user) {
    final all = <_AppDestination>[
      _AppDestination(
        id: 'dashboard',
        label: context.t(en: 'Dashboard', ar: 'لوحة التحكم'),
        icon: Icons.dashboard_outlined,
        page: DashboardPage(onOpenOrder: _openOrder),
        visibleWhen: (candidate) =>
            candidate.hasPermission(AppPermission.dashboardView),
      ),
      _AppDestination(
        id: 'orders',
        label: context.t(en: 'Orders', ar: 'الطلبات'),
        icon: Icons.receipt_long_outlined,
        page: OrdersPage(
          onOpenOrder: _openOrder,
          onCreateOrder: _openCreateOrder,
        ),
        visibleWhen: (candidate) =>
            candidate.hasPermission(AppPermission.ordersView) ||
            candidate.hasPermission(AppPermission.ordersCreate) ||
            candidate.hasPermission(AppPermission.ordersApprove) ||
            candidate.hasPermission(AppPermission.ordersShip),
      ),
      _AppDestination(
        id: 'inventory',
        label: context.t(en: 'Inventory', ar: 'المخزون'),
        icon: Icons.inventory_2_outlined,
        page: const InventoryPage(),
        visibleWhen: (candidate) =>
            candidate.hasPermission(AppPermission.inventoryView) ||
            candidate.hasPermission(AppPermission.productsView),
      ),
      _AppDestination(
        id: 'reports',
        label: context.t(en: 'Reports', ar: 'التقارير'),
        icon: Icons.assessment_outlined,
        page: const ReportsPage(),
        visibleWhen: (candidate) =>
            candidate.hasPermission(AppPermission.reportsView),
      ),
      _AppDestination(
        id: 'notifications',
        label: context.t(en: 'Notifications', ar: 'الإشعارات'),
        icon: Icons.notifications_none_outlined,
        page: NotificationsPage(onOpenOrder: _openOrder),
        visibleWhen: (candidate) =>
            candidate.hasPermission(AppPermission.notificationsView),
      ),
      _AppDestination(
        id: 'employees',
        label: context.t(en: 'Employees', ar: 'الموظفون'),
        icon: Icons.group_outlined,
        page: const UsersPage(),
        visibleWhen: (candidate) =>
            candidate.hasPermission(AppPermission.usersView) ||
            candidate.hasPermission(AppPermission.usersCreate),
      ),
    ];

    return all.where((item) => item.visibleWhen(user)).toList();
  }

  void _goTo(String destinationId, List<_AppDestination> destinations) {
    final index = destinations.indexWhere((item) => item.id == destinationId);
    if (index >= 0) {
      setState(() => _selectedIndex = index);
    }
  }

  Future<void> _openOrder(String orderId) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailPage(orderId: orderId)),
    );
  }

  Future<void> _openCreateOrder() {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateOrderPage()));
  }
}

class _AppDestination {
  const _AppDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.page,
    required this.visibleWhen,
  });

  final String id;
  final String label;
  final IconData icon;
  final Widget page;
  final bool Function(AppUser user) visibleWhen;
}

class _NoPermissionsScaffold extends StatelessWidget {
  const _NoPermissionsScaffold({required this.user, required this.onSignOut});

  final AppUser user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(en: 'Top Quality ERP', ar: 'توب كواليتي ERP')),
        actions: [
          const LanguageToggle(),
          const SizedBox(width: 8),
          const ThemeModeToggle(),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: context.t(en: 'Sign out', ar: 'تسجيل الخروج'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 44),
                  const SizedBox(height: 16),
                  Text(
                    context.t(
                      en: 'No modules available for your account',
                      ar: 'لا توجد وحدات متاحة لهذا الحساب',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t(
                      en: 'Your account is authenticated, but no navigation modules are currently permitted. Contact your administrator.',
                      ar: 'تم تسجيل الدخول بنجاح، لكن لا توجد صلاحيات تعرض وحدات داخل النظام. تواصل مع مدير النظام.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${context.t(en: 'User', ar: 'المستخدم')}: ${user.email}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
