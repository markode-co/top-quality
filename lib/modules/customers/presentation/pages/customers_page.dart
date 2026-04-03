import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/entities/branch_profile.dart';
import 'package:top_quality/domain/entities/employee_draft.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _BranchRecord {
  _BranchRecord({
    required this.name,
    this.phone = '',
    this.email,
    this.address,
    this.isActive = true,
  });

  final String name;
  String phone;
  String? email;
  String? address;
  bool isActive;

  int employees = 0;
  int orders = 0;
  double totalRevenue = 0;
  DateTime? lastOrderDate;
}

enum _BranchFilter { all, active, noOrders }

enum _BranchSort { name, employees, orders, revenue, latest }

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _searchController = TextEditingController();
  final List<_BranchRecord> _manualBranches = [];
  _BranchFilter _filter = _BranchFilter.all;
  _BranchSort _sort = _BranchSort.name;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _branchKey(String branchName) => branchName.trim().toLowerCase();

  Future<void> _showAddBranchDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final branch = await showDialog<_BranchRecord?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.t(en: 'Add branch', ar: 'إضافة فرع')),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: context.t(en: 'Branch name', ar: 'اسم الفرع'),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? context.t(en: 'Branch name is required', ar: 'اسم الفرع مطلوب')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: context.t(en: 'Branch phone', ar: 'هاتف الفرع'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: context.t(en: 'Branch email', ar: 'بريد الفرع'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  decoration: InputDecoration(
                    labelText: context.t(en: 'Branch address', ar: 'عنوان الفرع'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(context.t(en: 'Cancel', ar: 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final branch = _BranchRecord(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  email: emailController.text.trim().isEmpty
                      ? null
                      : emailController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                );
                Navigator.of(context).pop(branch);
              },
              child: Text(context.t(en: 'Save', ar: 'حفظ')),
            ),
          ],
        );
      },
    );

    if (branch == null) {
      return;
    }

    final savedToBackend = await _trySaveBranchToBackend(branch);
    if (!savedToBackend) {
      setState(() => _manualBranches.add(branch));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t(en: 'Branch saved successfully.', ar: 'تم حفظ الفرع بنجاح.'),
        ),
      ),
    );
  }

  Future<bool> _trySaveBranchToBackend(_BranchRecord branch) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .upsertBranch(
            BranchProfile(
              name: branch.name.trim(),
              phone: branch.phone.trim(),
              email: branch.email?.trim(),
              address: branch.address?.trim(),
              isActive: branch.isActive,
            ),
          );

      final email = branch.email?.trim();
      if (email != null && email.isNotEmpty) {
        final users = ref.read(usersProvider).valueOrNull ?? const [];
        AppUser? existingUser;
        for (final user in users) {
          if (user.email.trim().toLowerCase() == email.toLowerCase()) {
            existingUser = user;
            break;
          }
        }

        if (existingUser != null) {
          final currentBranchName = (existingUser.companyName ?? '').trim();
          final newBranchName = branch.name.trim();
          if (currentBranchName.toLowerCase() != newBranchName.toLowerCase()) {
            final payload = EmployeeDraft(
              id: existingUser.id,
              name: existingUser.name,
              email: existingUser.email,
              password: null,
              companyName: newBranchName,
              role: existingUser.role,
              permissions: existingUser.permissions,
              isActive: existingUser.isActive,
            );
            await ref
                .read(operationsControllerProvider.notifier)
                .updateEmployee(payload);
          }
        }
      }

      ref.invalidate(branchesProvider);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                en: 'Failed to save branch to the server. It will remain visible locally.',
                ar: 'فشل حفظ الفرع على الخادم. سيبقى مرئيًا محليًا.',
              ),
            ),
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toString();
    final currentUser = ref.watch(currentUserProvider);
    final users = ref.watch(usersProvider).valueOrNull ?? const [];
    final orders = ref.watch(ordersProvider).valueOrNull ?? const [];
    final storedBranches = ref.watch(branchesProvider).valueOrNull ?? const [];
    final fallbackBranch = (currentUser?.companyName ?? '').trim();

    final branchesByKey = <String, _BranchRecord>{};
    final userIdToBranchName = <String, String>{};

    for (final branch in storedBranches) {
      final key = _branchKey(branch.name);
      branchesByKey[key] = _BranchRecord(
        name: branch.name,
        phone: branch.phone,
        email: branch.email,
        address: branch.address,
        isActive: branch.isActive,
      );
    }

    for (final user in users) {
      final branchName = (user.companyName ?? '').trim();
      if (branchName.isEmpty) continue;
      final key = _branchKey(branchName);
      final record = branchesByKey.putIfAbsent(
        key,
        () => _BranchRecord(
          name: branchName,
          email: user.email,
          isActive: user.isActive,
        ),
      );
      record.employees += 1;
      record.isActive = record.isActive || user.isActive;
      if ((record.email ?? '').trim().isEmpty) {
        record.email = user.email;
      }
      userIdToBranchName[user.id] = branchName;
    }

    if (fallbackBranch.isNotEmpty) {
      final key = _branchKey(fallbackBranch);
      branchesByKey.putIfAbsent(
        key,
        () => _BranchRecord(
          name: fallbackBranch,
          email: currentUser?.email,
          isActive: true,
        ),
      );
    }

    for (final branch in _manualBranches) {
      final key = _branchKey(branch.name);
      final existing = branchesByKey[key];
      if (existing == null) {
        branchesByKey[key] = branch;
      } else {
        if (branch.phone.trim().isNotEmpty) existing.phone = branch.phone;
        if ((branch.email ?? '').trim().isNotEmpty) existing.email = branch.email;
        if ((branch.address ?? '').trim().isNotEmpty) {
          existing.address = branch.address;
        }
      }
    }

    for (final order in orders) {
      final branchName = userIdToBranchName[order.createdBy] ?? fallbackBranch;
      if (branchName.trim().isEmpty) continue;
      final key = _branchKey(branchName);
      final record = branchesByKey.putIfAbsent(
        key,
        () => _BranchRecord(name: branchName),
      );
      record.orders += 1;
      record.totalRevenue += order.totalRevenue;
      if (record.lastOrderDate == null ||
          order.orderDate.isAfter(record.lastOrderDate!)) {
        record.lastOrderDate = order.orderDate;
      }
    }

    final allBranches = branchesByKey.values.toList();
    final totalEmployees =
        allBranches.fold<int>(0, (sum, branch) => sum + branch.employees);
    final totalOrders = allBranches.fold<int>(0, (sum, branch) => sum + branch.orders);
    final totalRevenue =
        allBranches.fold<double>(0, (sum, branch) => sum + branch.totalRevenue);
    final activeBranches =
        allBranches.where((branch) => branch.isActive).length;

    final query = _searchController.text.trim().toLowerCase();
    final filtered = allBranches.where((branch) {
      final matchesFilter = switch (_filter) {
        _BranchFilter.all => true,
        _BranchFilter.active => branch.isActive,
        _BranchFilter.noOrders => branch.orders == 0,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return branch.name.toLowerCase().contains(query) ||
          branch.phone.toLowerCase().contains(query) ||
          (branch.email?.toLowerCase().contains(query) ?? false) ||
          (branch.address?.toLowerCase().contains(query) ?? false);
    }).toList()
      ..sort((a, b) {
        return switch (_sort) {
          _BranchSort.name =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          _BranchSort.employees => b.employees.compareTo(a.employees),
          _BranchSort.orders => b.orders.compareTo(a.orders),
          _BranchSort.revenue => b.totalRevenue.compareTo(a.totalRevenue),
          _BranchSort.latest =>
            (b.lastOrderDate ?? DateTime(1970)).compareTo(
              a.lastOrderDate ?? DateTime(1970),
            ),
        };
      });

    return ResponsiveListView(
      children: [
        SectionHeader(
          title: context.t(en: 'Branch management', ar: 'إدارة الفروع'),
          subtitle: context.t(
            en: 'This page shows branches/companies based on organization users.',
            ar: 'هذه الصفحة تعرض الفروع أو الشركات بناءً على بيانات المستخدمين.',
          ),
          trailing: FilledButton.icon(
            onPressed: _showAddBranchDialog,
            icon: const Icon(Icons.add_business_outlined),
            label: Text(context.t(en: 'Add branch', ar: 'إضافة فرع')),
          ),
        ),
        const SizedBox(height: 10),
        _SummaryGrid(
          cards: [
            _SummaryCardData(
              icon: Icons.apartment_outlined,
              label: context.t(en: 'Branches', ar: 'الفروع'),
              value: '$activeBranches / ${allBranches.length}',
            ),
            _SummaryCardData(
              icon: Icons.group_outlined,
              label: context.t(en: 'Employees', ar: 'الموظفون'),
              value: '$totalEmployees',
            ),
            _SummaryCardData(
              icon: Icons.receipt_long_outlined,
              label: context.t(en: 'Orders', ar: 'الطلبات'),
              value: '$totalOrders',
            ),
            _SummaryCardData(
              icon: Icons.payments_outlined,
              label: context.t(en: 'Revenue', ar: 'الإيراد'),
              value: AppFormatters.currency(totalRevenue, localeTag),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.t(en: 'Search branches', ar: 'البحث في الفروع'),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_BranchSort>(
                initialValue: _sort,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Sort by', ar: 'ترتيب حسب'),
                ),
                items: [
                  DropdownMenuItem(
                    value: _BranchSort.name,
                    child: Text(context.t(en: 'Name', ar: 'الاسم')),
                  ),
                  DropdownMenuItem(
                    value: _BranchSort.employees,
                    child: Text(context.t(en: 'Employees', ar: 'الموظفون')),
                  ),
                  DropdownMenuItem(
                    value: _BranchSort.orders,
                    child: Text(context.t(en: 'Orders', ar: 'الطلبات')),
                  ),
                  DropdownMenuItem(
                    value: _BranchSort.revenue,
                    child: Text(context.t(en: 'Revenue', ar: 'الإيراد')),
                  ),
                  DropdownMenuItem(
                    value: _BranchSort.latest,
                    child: Text(context.t(en: 'Latest activity', ar: 'أحدث نشاط')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _sort = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<_BranchFilter>(
                segments: [
                  ButtonSegment(
                    value: _BranchFilter.all,
                    icon: const Icon(Icons.list_alt_outlined),
                    label: Text(context.t(en: 'All', ar: 'الكل')),
                  ),
                  ButtonSegment(
                    value: _BranchFilter.active,
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(context.t(en: 'Active', ar: 'نشط')),
                  ),
                  ButtonSegment(
                    value: _BranchFilter.noOrders,
                    icon: const Icon(Icons.inbox_outlined),
                    label: Text(context.t(en: 'No orders', ar: 'بدون طلبات')),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (values) {
                  if (values.isNotEmpty) {
                    setState(() => _filter = values.first);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (ref.watch(branchesProvider).isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          ),
        if (filtered.isEmpty)
          StandardCard(
            child: Text(
              context.t(
                en: 'No branches found.',
                ar: 'لا يوجد فروع مطابقة.',
              ),
            ),
          )
        else
          ...filtered.map((branch) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StandardCard(
                child: _BranchTile(branch: branch, localeTag: localeTag),
              ),
            );
          }),
      ],
    );
  }
}

class _SummaryCardData {
  const _SummaryCardData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.cards});

  final List<_SummaryCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920
            ? 4
            : constraints.maxWidth >= 640
                ? 2
                : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 3.2 : 2.7,
          children: cards.map((card) => _SummaryTile(card: card)).toList(),
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.card});

  final _SummaryCardData card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              foregroundColor: scheme.primary,
              child: Icon(card.icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(card.label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    card.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.localeTag,
  });

  final _BranchRecord branch;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final branchName = branch.name.trim().isEmpty
        ? context.t(en: 'Unnamed branch', ar: 'فرع بدون اسم')
        : branch.name.trim();
    final initial = branchName.characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text(initial),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                branchName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Chip(
              label: Text(
                branch.isActive
                    ? context.t(en: 'Active', ar: 'نشط')
                    : context.t(en: 'Inactive', ar: 'غير نشط'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if ((branch.email ?? '').trim().isNotEmpty)
              _InfoPill(icon: Icons.email_outlined, text: branch.email!),
            if (branch.phone.trim().isNotEmpty)
              _InfoPill(icon: Icons.phone_outlined, text: branch.phone),
            if ((branch.address ?? '').trim().isNotEmpty)
              _InfoPill(icon: Icons.location_on_outlined, text: branch.address!),
            _InfoPill(
              icon: Icons.schedule_outlined,
              text: branch.lastOrderDate == null
                  ? context.t(en: 'No activity yet', ar: 'لا يوجد نشاط بعد')
                  : context.t(
                      en: 'Last activity ${AppFormatters.shortDate(branch.lastOrderDate!, localeTag)}',
                      ar: 'آخر نشاط ${AppFormatters.shortDate(branch.lastOrderDate!, localeTag)}',
                    ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${context.t(en: 'Employees', ar: 'الموظفون')}: ${branch.employees}',
              ),
            ),
            Expanded(
              child: Text(
                '${context.t(en: 'Orders', ar: 'الطلبات')}: ${branch.orders}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Spacer(),
            Text(
              '${context.t(en: 'Revenue', ar: 'الإيراد')}: ${AppFormatters.currency(branch.totalRevenue, localeTag)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
