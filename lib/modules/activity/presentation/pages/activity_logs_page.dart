import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String? _entityFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        final entityTypes = {
          for (final log in logs) log.entityType,
        }.toList()
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
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, idx) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final log = filtered[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(
                        log.actorName.isNotEmpty
                            ? log.actorName
                            : (log.actorEmail ?? log.actorId),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (log.actorEmail != null)
                              Text(
                                log.actorEmail!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            Text(
                              '${_actionLabel(context, log.action)} • ${log.entityType}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              AppFormatters.shortDateTime(log.createdAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      dense: true,
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

  List<ActivityLog> _applyFilters(List<ActivityLog> logs) {
    final query = _searchController.text.trim().toLowerCase();
    return logs.where((log) {
      final matchesEntity =
          _entityFilter == null || log.entityType == _entityFilter;
      final matchesQuery = query.isEmpty ||
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
