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

    return reportsValue.when(
      data: (reports) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionPanel(
            title: context.t(en: 'Employee Reports', ar: 'تقارير الموظفين'),
            trailing: Wrap(
              spacing: 8,
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
            child: SingleChildScrollView(
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
                          DataCell(Text('${report.ordersReturned}')),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  static String _csv(BuildContext context, List<dynamic> reports) {
    final rows = <String>[
      context.t(
        en: 'employee,role,entered,reviewed,shipped,returned',
        ar: 'الموظف,الدور,إدخال,مراجعة,شحن,مرتجع',
      ),
      ...reports.map(
        (report) =>
            '${report.userName},${report.role.label},${report.ordersEntered},${report.ordersReviewed},${report.ordersShipped},${report.ordersReturned}',
      ),
    ];
    return rows.join('\n');
  }

  static String _tsv(BuildContext context, List<dynamic> reports) {
    final rows = <String>[
      context.t(
        en: 'Employee\tRole\tEntered\tReviewed\tShipped\tReturned',
        ar: 'الموظف\tالدور\tإدخال\tمراجعة\tشحن\tمرتجع',
      ),
      ...reports.map(
        (report) =>
            '${report.userName}\t${report.role.label}\t${report.ordersEntered}\t${report.ordersReviewed}\t${report.ordersShipped}\t${report.ordersReturned}',
      ),
    ];
    return rows.join('\n');
  }

  static String _pdf(BuildContext context, List<dynamic> reports) {
    final lines = reports
        .map(
          (report) =>
              '${report.userName} (${report.role.label}) handled entered=${report.ordersEntered}, reviewed=${report.ordersReviewed}, shipped=${report.ordersShipped}, returned=${report.ordersReturned}.',
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
