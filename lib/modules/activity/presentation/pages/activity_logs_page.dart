import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/activity_log.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class ActivityLogsPage extends ConsumerStatefulWidget {
  const ActivityLogsPage({super.key});

  @override
  ConsumerState<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends ConsumerState<ActivityLogsPage> {
  final _searchController = TextEditingController();
  String? _entityFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logsValue = ref.watch(activityLogsProvider);
    final users = ref.watch(usersProvider).valueOrNull ?? const <AppUser>[];
    final userById = {for (final user in users) user.id: user};
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
        final entityTypes = {for (final log in logs) log.entityType}.toList()
          ..sort();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: context.t(
                        en: 'Search by user, action, or entity',
                        ar: 'ابحث باسم المستخدم أو الإجراء أو الكيان',
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(context.t(en: 'All types', ar: 'كل الأنواع')),
                      selected: _entityFilter == null,
                      onSelected: (_) => setState(() => _entityFilter = null),
                    ),
                    for (final type in entityTypes)
                      ChoiceChip(
                        label: Text(type),
                        selected: _entityFilter == type,
                        onSelected: (_) => setState(() => _entityFilter = type),
                      ),
                  ],
                ),
              ],
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
              Card(
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
                        label: Text(context.t(en: 'Activity', ar: 'النشاطات')),
                      ),
                    ],
                    rows: [
                      for (final log in filtered)
                        _activityRow(context, log, userById[log.actorId]),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  List<ActivityLog> _applyFilters(List<ActivityLog> logs) {
    final query = _searchController.text.trim().toLowerCase();
    return logs.where((log) {
      final matchesEntity =
          _entityFilter == null || log.entityType == _entityFilter;
      final matchesQuery =
          query.isEmpty ||
          log.actorName.toLowerCase().contains(query) ||
          (log.actorId.toLowerCase().contains(query)) ||
          (log.actorEmail?.toLowerCase().contains(query) ?? false) ||
          log.action.toLowerCase().contains(query) ||
          log.entityType.toLowerCase().contains(query) ||
          (log.entityId?.toLowerCase().contains(query) ?? false);
      return matchesEntity && matchesQuery;
    }).toList();
  }
}

DataRow _activityRow(BuildContext context, ActivityLog log, AppUser? user) {
  final name = log.actorName.trim().isNotEmpty
      ? log.actorName.trim()
      : (user?.name.trim().isNotEmpty ?? false)
      ? user!.name.trim()
      : '';
  final email = log.actorEmail?.trim().isNotEmpty ?? false
      ? log.actorEmail!.trim()
      : (user?.email.trim().isNotEmpty ?? false)
      ? user!.email.trim()
      : '';
  final displayName = name.isNotEmpty
      ? name
      : (email.isNotEmpty
            ? email
            : (log.actorId.isNotEmpty ? log.actorId : '-'));
  final displayEmail = email.isNotEmpty
      ? email
      : (log.actorId.isNotEmpty ? log.actorId : '-');
  final task = _actionLabel(context, log.action);
  final activityBase = log.entityType.isNotEmpty
      ? log.entityType
      : context.t(en: 'General', ar: 'عام');
  final activity = (log.entityId?.isNotEmpty ?? false)
      ? '$activityBase - ${log.entityId}'
      : activityBase;

  return DataRow(
    cells: [
      DataCell(_cellText(context, displayName, maxWidth: 180)),
      DataCell(_cellText(context, displayEmail, maxWidth: 220)),
      DataCell(_cellText(context, task, maxWidth: 200)),
      DataCell(
        _cellText(
          context,
          AppFormatters.shortDateTime(log.createdAt),
          maxWidth: 170,
          maxLines: 1,
        ),
      ),
      DataCell(_cellText(context, activity, maxWidth: 260)),
    ],
  );
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

String _actionLabel(BuildContext context, String action) {
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
  };
  return context.t(en: mapEn[action] ?? action, ar: mapAr[action] ?? action);
}
