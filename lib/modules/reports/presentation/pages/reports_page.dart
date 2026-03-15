import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsValue = ref.watch(employeeReportsProvider);

    Future<void> refreshReports() async {
      ref.invalidate(employeeReportsProvider);
      try {
        await ref.read(employeeReportsProvider.future);
      } catch (_) {
        // ignore errors; UI handles states.
      }
    }

    return reportsValue.when(
      data: (reports) => ResponsiveListView(
        onRefresh: refreshReports,
        children: [
          SectionPanel(
            title: context.t(en: 'Employee Reports', ar: 'تقارير الموظفين'),
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _showExport(
                    context,
                    context.t(en: 'CSV Preview', ar: 'معاينة CSV'),
                    _csv(context, reports),
                  ),
                  child: const Text('CSV'),
                ),
                OutlinedButton(
                  onPressed: () => _showExport(
                    context,
                    context.t(
                      en: 'Excel-ready Preview',
                      ar: 'معاينة جاهزة لـ Excel',
                    ),
                    _tsv(context, reports),
                  ),
                  child: const Text('Excel'),
                ),
                OutlinedButton(
                  onPressed: () => _showExport(
                    context,
                    context.t(
                      en: 'PDF Narrative Preview',
                      ar: 'معاينة PDF نصية',
                    ),
                    _pdf(context, reports),
                  ),
                  child: const Text('PDF'),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showTable = constraints.maxWidth >= 900;
                if (!showTable) {
                  return Column(
                    children: reports.map((report) {
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.userName,
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.roleLabel(report.role),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  _miniMetric(
                                    context,
                                    context.t(en: 'Entered', ar: 'إدخال'),
                                    '${report.ordersEntered}',
                                  ),
                                  _miniMetric(
                                    context,
                                    context.t(en: 'Reviewed', ar: 'مراجعة'),
                                    '${report.ordersReviewed}',
                                  ),
                                  _miniMetric(
                                    context,
                                    context.t(en: 'Shipped', ar: 'شحن'),
                                    '${report.ordersShipped}',
                                  ),
                                  _miniMetric(
                                    context,
                                    context.t(en: 'Completed', ar: 'مكتمل'),
                                    '${report.ordersCompleted}',
                                  ),
                                  _miniMetric(
                                    context,
                                    context.t(en: 'Returned', ar: 'مرتجع'),
                                    '${report.ordersReturned}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(
                        label: Text(context.t(en: 'Employee', ar: 'الموظف')),
                      ),
                      DataColumn(
                        label: Text(context.t(en: 'Role', ar: 'الدور')),
                      ),
                      DataColumn(
                        label: Text(context.t(en: 'Entered', ar: 'إدخال')),
                      ),
                      DataColumn(
                        label: Text(context.t(en: 'Reviewed', ar: 'مراجعة')),
                      ),
                      DataColumn(
                        label: Text(context.t(en: 'Shipped', ar: 'شحن')),
                      ),
                      DataColumn(
                        label: Text(context.t(en: 'Completed', ar: 'مكتمل')),
                      ),
                      DataColumn(
                        label: Text(context.t(en: 'Returned', ar: 'مرتجع')),
                      ),
                    ],
                    rows: reports
                        .map(
                          (report) => DataRow(
                            cells: [
                              DataCell(Text(report.userName)),
                              DataCell(Text(context.roleLabel(report.role))),
                              DataCell(Text('${report.ordersEntered}')),
                              DataCell(Text('${report.ordersReviewed}')),
                              DataCell(Text('${report.ordersShipped}')),
                              DataCell(Text('${report.ordersCompleted}')),
                              DataCell(Text('${report.ordersReturned}')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  static Widget _miniMetric(BuildContext context, String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          LtrText(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }

  static String _csv(BuildContext context, List<dynamic> reports) {
    final rows = <String>[
      context.t(
        en: 'employee,role,entered,reviewed,shipped,completed,returned',
        ar: 'الموظف,الدور,إدخال,مراجعة,شحن,مكتمل,مرتجع',
      ),
      ...reports.map(
        (report) =>
            '${report.userName},${report.role.label},${report.ordersEntered},${report.ordersReviewed},${report.ordersShipped},${report.ordersCompleted},${report.ordersReturned}',
      ),
    ];
    return rows.join('\n');
  }

  static String _tsv(BuildContext context, List<dynamic> reports) {
    final rows = <String>[
      context.t(
        en: 'Employee\tRole\tEntered\tReviewed\tShipped\tCompleted\tReturned',
        ar: 'الموظف\tالدور\tإدخال\tمراجعة\tشحن\tمكتمل\tمرتجع',
      ),
      ...reports.map(
        (report) =>
            '${report.userName}\t${report.role.label}\t${report.ordersEntered}\t${report.ordersReviewed}\t${report.ordersShipped}\t${report.ordersCompleted}\t${report.ordersReturned}',
      ),
    ];
    return rows.join('\n');
  }

  static String _pdf(BuildContext context, List<dynamic> reports) {
    final lines = reports
        .map(
          (report) =>
              '${report.userName} (${report.role.label}) handled entered=${report.ordersEntered}, reviewed=${report.ordersReviewed}, shipped=${report.ordersShipped}, completed=${report.ordersCompleted}, returned=${report.ordersReturned}.',
        )
        .join('\n');
    return context.t(
      en: 'Operational report summary\n\n$lines',
      ar: 'ملخص التقرير التشغيلي\n\n$lines',
    );
  }

  static Future<void> _showExport(
    BuildContext context,
    String title,
    String content,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(content)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t(en: 'Close', ar: 'إغلاق')),
          ),
        ],
      ),
    );
  }
}
