import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/activity_log.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class ActivityLogsPage extends ConsumerStatefulWidget {
  const ActivityLogsPage({super.key});

  @override
  ConsumerState<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends ConsumerState<ActivityLogsPage> {
  final _searchController = TextEditingController();
  _LogCategory _category = _LogCategory.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Future<void> refreshActivityLogs() async {
      ref.invalidate(activityLogsProvider);
      try {
        await ref.read(activityLogsProvider.future);
      } catch (_) {
        // ignore errors; UI handles states.
      }
    }

    final logsValue = ref.watch(activityLogsProvider);
    return logsValue.when(
      data: (logs) {
        if (logs.isEmpty) {
          return EmptyPlaceholder(
            title: context.t(en: 'No activity yet', ar: 'لا يوجد نشاط بعد'),
            subtitle: context.t(
              en: 'Actions will appear here as users work in the system.',
              ar: 'ستظهر العمليات هنا مع استخدام النظام.',
            ),
            icon: Icons.history_toggle_off_outlined,
          );
        }

        final filtered = _applyFilters(logs);

        return ResponsiveListView(
          onRefresh: refreshActivityLogs,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 720;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: isNarrow ? constraints.maxWidth : 420,
                        maxWidth: 560,
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: context.t(
                            en: 'Search orders, inventory, employees...',
                            ar: 'ابحث: طلبات، مخزون، موظفين...',
                          ),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context.t(en: 'Clear', ar: 'مسح'),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                    ),
                    _categoryChips(context),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              EmptyPlaceholder(
                title: context.t(
                  en: 'No matching records',
                  ar: 'لا توجد سجلات مطابقة',
                ),
                subtitle: context.t(
                  en: 'Try another keyword or clear the filters.',
                  ar: 'جرّب كلمة بحث مختلفة أو أزل الفلاتر.',
                ),
                icon: Icons.search_off_outlined,
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final showTable = constraints.maxWidth >= 980;
                  if (!showTable) {
                    return Column(
                      children: [
                        for (final log in filtered)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.history),
                              title: Text(_actionLabel(context, log)),
                              subtitle: Text(
                                '${log.actorName}\n${_entitySummary(context, log)}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                AppFormatters.shortDateTime(
                                  log.createdAt,
                                  Localizations.localeOf(context).toString(),
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                      ],
                    );
                  }

                  return Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 28,
                        headingRowHeight: 44,
                        dataRowMinHeight: 56,
                        dataRowMaxHeight: 96,
                        columns: [
                          DataColumn(
                            label: Text(context.t(en: 'User', ar: 'المستخدم')),
                          ),
                          DataColumn(
                            label: Text(context.t(en: 'Email', ar: 'الايميل')),
                          ),
                          DataColumn(
                            label: Text(
                              context.t(en: 'Task', ar: 'المهام المنفذة'),
                            ),
                          ),
                          DataColumn(
                            label: Text(context.t(en: 'Date', ar: 'التاريخ')),
                          ),
                          DataColumn(
                            label: Text(
                              context.t(en: 'Activity', ar: 'النشاطات'),
                            ),
                          ),
                        ],
                        rows: [
                          for (final log in filtered)
                            _activityRow(context, log),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  Widget _categoryChips(BuildContext context) {
    final items = <_CategoryChip>[
      _CategoryChip(
        category: _LogCategory.all,
        icon: Icons.all_inbox_outlined,
        label: context.t(en: 'All', ar: 'الكل'),
      ),
      _CategoryChip(
        category: _LogCategory.orders,
        icon: Icons.receipt_long_outlined,
        label: context.t(en: 'Orders', ar: 'الطلبات'),
      ),
      _CategoryChip(
        category: _LogCategory.inventory,
        icon: Icons.warehouse_outlined,
        label: context.t(en: 'Inventory', ar: 'المخزون'),
      ),
      _CategoryChip(
        category: _LogCategory.employees,
        icon: Icons.badge_outlined,
        label: context.t(en: 'Employees', ar: 'الموظفون'),
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          ChoiceChip(
            avatar: Icon(item.icon, size: 18),
            label: Text(item.label),
            selected: _category == item.category,
            onSelected: (_) => setState(() => _category = item.category),
          ),
      ],
    );
  }

  List<ActivityLog> _applyFilters(List<ActivityLog> logs) {
    final query = _searchController.text.trim().toLowerCase();
    return logs.where((log) {
      final matchesCategory = switch (_category) {
        _LogCategory.all => true,
        _LogCategory.orders => log.entityType.toLowerCase() == 'order',
        _LogCategory.inventory => _isInventoryLog(log),
        _LogCategory.employees => log.entityType.toLowerCase() == 'employee',
      };

      if (!matchesCategory) return false;
      if (query.isEmpty) return true;

      final haystack = _searchHaystack(context, log);
      return haystack.contains(query);
    }).toList();
  }

  String _searchHaystack(BuildContext context, ActivityLog log) {
    final meta = log.metadata ?? const <String, dynamic>{};
    final metaText = meta.entries
        .map((e) => '${e.key}:${e.value}')
        .join(' ')
        .toLowerCase();

    return [
      log.actorName,
      log.actorId,
      log.actorEmail ?? '',
      log.action,
      _actionLabel(context, log),
      log.entityType,
      log.entityId ?? '',
      _entitySummary(context, log),
      metaText,
    ].join(' ').toLowerCase();
  }
}

bool _isInventoryLog(ActivityLog log) {
  final entityType = log.entityType.trim().toLowerCase();
  if (entityType == 'inventory' || entityType == 'product') return true;

  final action = log.action.trim().toLowerCase();
  if (action == 'adjust_inventory' || action == 'upsert_product' || action == 'delete_product') return true;

  final metadata = log.metadata ?? const <String, dynamic>{};
  return metadata.containsKey('delta') ||
      metadata.containsKey('new_stock') ||
      metadata.containsKey('reason');
}

DataRow _activityRow(BuildContext context, ActivityLog log) {
  final name = log.actorName.trim();
  final email = (log.actorEmail ?? '').trim();
  final displayName = name.isNotEmpty
      ? name
      : (email.isNotEmpty
            ? email
            : (log.actorId.isNotEmpty ? log.actorId : '-'));
  final displayEmail = email.isNotEmpty
      ? email
      : (log.actorId.isNotEmpty ? log.actorId : '-');
  final task = _actionLabel(context, log);
  final activity = _entitySummary(context, log);

  return DataRow(
    cells: [
      DataCell(_cellText(context, displayName, maxWidth: 180)),
      DataCell(
        SizedBox(
          width: 220,
          child: LtrText(
            displayEmail,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
          ),
        ),
      ),
      DataCell(_cellText(context, task, maxWidth: 200)),
      DataCell(
        _cellText(
          context,
          AppFormatters.shortDateTime(
            log.createdAt,
            Localizations.localeOf(context).toString(),
          ),
          maxWidth: 170,
          maxLines: 1,
        ),
      ),
      DataCell(_cellText(context, activity, maxWidth: 260)),
    ],
  );
}

String _entitySummary(BuildContext context, ActivityLog log) {
  final type = log.entityType.trim().toLowerCase();
  final action = log.action.trim().toLowerCase();
  final id = (log.entityId ?? '').trim();
  final meta = log.metadata ?? const <String, dynamic>{};

  String typeLabel() {
    switch (type) {
      case 'order':
        return context.t(en: 'Order', ar: 'طلب');
      case 'product':
        return context.t(en: 'Product', ar: 'منتج');
      case 'inventory':
        return context.t(en: 'Inventory', ar: 'مخزون');
      case 'employee':
        return context.t(en: 'Employee', ar: 'موظف');
      case 'user':
        return context.t(en: 'User', ar: 'مستخدم');
      default:
        return type.isEmpty ? context.t(en: 'General', ar: 'عام') : type;
    }
  }

  String shortId(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (v.length <= 10) return v;
    return '${v.substring(0, 6)}...${v.substring(v.length - 4)}';
  }

  String? metaString(String key) {
    final v = meta[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  String statusLabel(String raw) {
    final value = raw.trim().toLowerCase();
    final status = OrderStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => OrderStatus.entered,
    );
    return context.orderStatusLabel(status);
  }

  if (action == 'adjust_inventory') {
    final deltaText = meta['delta']?.toString().trim();
    final reason = metaString('reason');
    final name = metaString('product_name') ?? metaString('name');
    final sku = metaString('sku') ?? metaString('product_sku');
    final inventoryLabel = context.t(en: 'Inventory', ar: 'مخزون');
    final itemLabel = [?sku, ?name].join(' - ');

    if (itemLabel.isNotEmpty && deltaText != null && deltaText.isNotEmpty) {
      return '$inventoryLabel ($itemLabel | $deltaText)';
    }
    if (itemLabel.isNotEmpty && reason != null) {
      return '$inventoryLabel ($itemLabel | $reason)';
    }
    if (deltaText != null && deltaText.isNotEmpty && reason != null) {
      return '$inventoryLabel ($deltaText - $reason)';
    }
    if (deltaText != null && deltaText.isNotEmpty) {
      return '$inventoryLabel ($deltaText)';
    }
    if (reason != null) {
      return '$inventoryLabel ($reason)';
    }
    return inventoryLabel;
  }

  if (type == 'order') {
    final customer = metaString('customer_name');
    final from = metaString('from');
    final to = metaString('to');
    if (customer != null) return '${typeLabel()} ($customer)';
    if (from != null && to != null) {
      return '${typeLabel()} (${statusLabel(from)} -> ${statusLabel(to)})';
    }
    return id.isNotEmpty ? '${typeLabel()} (${shortId(id)})' : typeLabel();
  }

  if (type == 'product') {
    final sku = metaString('sku');
    final name = metaString('name');
    if (sku != null && name != null) return '${typeLabel()} ($sku - $name)';
    if (sku != null) return '${typeLabel()} ($sku)';
    if (name != null) return '${typeLabel()} ($name)';
    return id.isNotEmpty ? '${typeLabel()} (${shortId(id)})' : typeLabel();
  }

  if (type == 'inventory') {
    final delta = meta['delta'];
    final reason = metaString('reason');
    final deltaText = (delta?.toString())?.trim();
    if (deltaText != null && deltaText.isNotEmpty && reason != null) {
      return '${typeLabel()} ($deltaText - $reason)';
    }
    if (deltaText != null && deltaText.isNotEmpty) {
      return '${typeLabel()} ($deltaText)';
    }
    if (reason != null) return '${typeLabel()} ($reason)';
    return id.isNotEmpty ? '${typeLabel()} (${shortId(id)})' : typeLabel();
  }

  if (type == 'employee') {
    final empName = metaString('employee_name') ?? metaString('name');
    final empEmail = metaString('employee_email') ?? metaString('email');
    if (empName != null) return '${typeLabel()} ($empName)';
    if (empEmail != null) return '${typeLabel()} ($empEmail)';
    return id.isNotEmpty ? '${typeLabel()} (${shortId(id)})' : typeLabel();
  }

  return id.isNotEmpty ? '${typeLabel()} (${shortId(id)})' : typeLabel();
}

Widget _cellText(
  BuildContext context,
  String value, {
  required double maxWidth,
  int maxLines = 2,
}) {
  return SizedBox(
    width: maxWidth,
    child: Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

String _actionLabel(BuildContext context, ActivityLog log) {
  final action = log.action.trim().toLowerCase();
  if (action == 'admin-manage-employee') {
    final employeeTask = log.metadata?['action']?.toString().trim().toLowerCase();
    if (employeeTask != null && employeeTask.isNotEmpty) {
      return context.t(
        en: _employeeActionLabelEn(employeeTask),
        ar: _employeeActionLabelAr(employeeTask),
      );
    }
  }
  if (action == 'upsert_product') {
    return _productUpsertActionLabel(context, log);
  }

  final mapEn = {
    'login': 'Login',
    'logout': 'Logout',
    'create_order': 'Create order',
    'update_order': 'Update order',
    'delete_order': 'Delete order',
    'override_order_status': 'Override status',
    'transition_order': 'Change status',
    'upsert_product': 'Save product',
    'delete_product': 'Delete product',
    'admin-manage-employee': 'Employee action',
    'diagnostics': 'Diagnostics',
    'adjust_inventory': 'Adjust inventory',
  };
  final mapAr = {
    'login': 'تسجيل دخول',
    'logout': 'تسجيل خروج',
    'create_order': 'إنشاء طلب',
    'update_order': 'تعديل طلب',
    'delete_order': 'حذف طلب',
    'override_order_status': 'تجاوز الحالة',
    'transition_order': 'تغيير الحالة',
    'upsert_product': 'حفظ منتج',
    'delete_product': 'حذف منتج',
    'admin-manage-employee': 'عملية موظف',
    'diagnostics': 'تشخيص',
    'adjust_inventory': 'تعديل المخزون',
  };
  return context.t(en: mapEn[action] ?? action, ar: mapAr[action] ?? action);
}

String _productUpsertActionLabel(BuildContext context, ActivityLog log) {
  final metadata = log.metadata ?? const <String, dynamic>{};
  final explicitAction = _readMetaToken(
    metadata,
    const ['action', 'operation', 'op', 'event', 'task'],
  );
  final productId = _readMetaToken(
    metadata,
    const ['p_product_id', 'product_id', 'existing_product_id'],
  );

  if (_isCreateOperation(explicitAction) ||
      (metadata.containsKey('p_product_id') && _isNullLike(productId))) {
    return context.t(en: 'Create product', ar: 'إضافة منتج');
  }
  if (_isUpdateOperation(explicitAction) || !_isNullLike(productId)) {
    return context.t(en: 'Update product', ar: 'تعديل منتج');
  }
  return context.t(en: 'Save product', ar: 'حفظ منتج');
}

String? _readMetaToken(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    final raw = metadata[key];
    if (raw == null) continue;
    final text = raw.toString().trim();
    if (text.isEmpty) continue;
    return text.toLowerCase();
  }
  return null;
}

bool _isNullLike(String? value) {
  if (value == null) return true;
  return value.isEmpty || value == 'null' || value == 'undefined';
}

bool _isCreateOperation(String? value) {
  if (value == null || value.isEmpty) return false;
  return value.contains('create') ||
      value.contains('add') ||
      value.contains('new') ||
      value.contains('insert') ||
      value.contains('إنشاء') ||
      value.contains('اضاف');
}

bool _isUpdateOperation(String? value) {
  if (value == null || value.isEmpty) return false;
  return value.contains('update') ||
      value.contains('edit') ||
      value.contains('modify') ||
      value.contains('save') ||
      value.contains('تعديل') ||
      value.contains('تحديث');
}

String _employeeActionLabelEn(String action) {
  switch (action) {
    case 'create':
      return 'Create employee';
    case 'update':
      return 'Update employee';
    case 'delete':
      return 'Delete employee';
    case 'activate':
      return 'Activate employee';
    case 'deactivate':
      return 'Deactivate employee';
    case 'transfer':
      return 'Transfer employee';
    default:
      return 'Employee action';
  }
}

String _employeeActionLabelAr(String action) {
  switch (action) {
    case 'create':
      return 'إنشاء موظف';
    case 'update':
      return 'تحديث موظف';
    case 'delete':
      return 'حذف موظف';
    case 'activate':
      return 'تفعيل موظف';
    case 'deactivate':
      return 'إيقاف موظف';
    case 'transfer':
      return 'نقل موظف';
    default:
      return 'عملية موظف';
  }
}

enum _LogCategory {
  all,
  orders,
  inventory,
  employees,
}

class _CategoryChip {
  const _CategoryChip({
    required this.category,
    required this.label,
    required this.icon,
  });

  final _LogCategory category;
  final String label;
  final IconData icon;
}
