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
                      title: Text('${log.actorName} • ${log.action}'),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  label: Text(log.entityType),
                                  avatar: const Icon(Icons.category_outlined),
                                ),
                                if (log.companyId != null)
                                  Chip(
                                    label: Text(
                                      '${context.t(en: 'Company', ar: 'الشركة')}: ${log.companyId}',
                                    ),
                                    avatar: const Icon(Icons.apartment_outlined),
                                  ),
                                Text(
                                  AppFormatters.shortDateTime(log.createdAt),
                                ),
                              ],
                            ),
                            if (log.entityId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${context.t(en: 'Entity ID', ar: 'معرّف الكيان')}: ${log.entityId}',
                                ),
                              ),
                            if (log.metadata != null &&
                                log.metadata!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: log.metadata!.entries.map((entry) {
                                    final value = entry.value?.toString() ?? '';
                                    return InputChip(
                                      label: Text('${entry.key}: $value'),
                                      avatar:
                                          const Icon(Icons.data_object_outlined),
                                    );
                                  }).toList(),
                                ),
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
          log.action.toLowerCase().contains(query) ||
          log.entityType.toLowerCase().contains(query) ||
          (log.entityId?.toLowerCase().contains(query) ?? false);
      return matchesEntity && matchesQuery;
    }).toList();
  }
}
