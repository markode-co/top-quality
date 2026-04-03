import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/file_export.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/dashboard_snapshot.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsValue = ref.watch(employeeReportsProvider);
    final localeTag = Localizations.localeOf(context).toString();

    Future<void> refreshReports() async {
      ref.invalidate(employeeReportsProvider);
      try {
        await ref.read(employeeReportsProvider.future);
      } catch (_) {}
    }

    return reportsValue.when(
      data: (reports) {
        if (reports.isEmpty) {
          return ResponsiveListView(
            onRefresh: refreshReports,
            children: [
              EmptyPlaceholder(
                title: context.t(en: 'No report data yet', ar: 'لا توجد بيانات تقارير بعد'),
                subtitle: context.t(
                  en: 'Create and process orders to populate employee reports.',
                  ar: 'أنشئ الطلبات وحرّكها في سير العمل لتظهر تقارير الموظفين.',
                ),
              ),
            ],
          );
        }

        return ResponsiveListView(
          onRefresh: refreshReports,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderBar(
                    onExportExcel: () => _saveExcel(context, reports),
                    onExportPdf: () => _savePdf(context, reports),
                  ),
                  const SizedBox(height: 12),
                  _EmployeesGrid(
                    reports: reports,
                    localeTag: localeTag,
                  ),
                  const SizedBox(height: 18),
                  _OrdersSection(
                    reports: reports,
                    localeTag: localeTag,
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  static String _tsv(BuildContext context, List<EmployeeReport> reports) {
    final rows = <String>[
      context.t(
        en:
            'Employee\tRole\tEntered\tReviewed\tShipped\tCompleted\tReturned\tOrder #\tCustomer\tPhone\tAddress',
        ar:
            'الموظف\tالدور\tإدخال\tمراجعة\tشحن\tمكتمل\tمرتجع\tرقم الطلب\tاسم العميل\tالهاتف\tالعنوان',
      ),
      ...reports.map((report) {
        final latest = report.orderDetails.isEmpty ? null : report.orderDetails.first;
        return '${report.userName}\t${context.roleLabel(report.role)}\t${report.ordersEntered}\t${report.ordersReviewed}\t${report.ordersShipped}\t${report.ordersCompleted}\t${report.ordersReturned}\t${latest == null ? '-' : '#${latest.orderNo}'}\t${latest?.customerName ?? '-'}\t${latest?.customerPhone ?? '-'}\t${latest?.customerAddress ?? '-'}';
      }),
    ];
    return rows.join('\n');
  }

  static Future<void> _saveExcel(
    BuildContext context,
    List<EmployeeReport> reports,
  ) async {
    final content = _tsv(context, reports);
    final filename = '${context.t(en: 'employee_reports', ar: 'تقارير_الموظفين')}_${_timestamp()}.xls';
    await _saveFile(
      context,
      filename,
      _excelBytes(content),
      'application/vnd.ms-excel',
    );
  }

  static Future<void> _savePdf(
    BuildContext context,
    List<EmployeeReport> reports,
  ) async {
    final bytes = await _generatePdfBytes(context, reports);
    if (!context.mounted) return;
    final filename = '${context.t(en: 'employee_reports', ar: 'تقارير_الموظفين')}_${_timestamp()}.pdf';
    await _saveFile(
      context,
      filename,
      bytes,
      'application/pdf',
    );
  }

  static List<int> _excelBytes(String content) {
    const bom = [0xEF, 0xBB, 0xBF];
    return [...bom, ...utf8.encode(content)];
  }

  static Future<void> _saveFile(
    BuildContext context,
    String filename,
    List<int> bytes,
    String mimeType,
  ) async {
    try {
      final storedPath = await saveFile(
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (!context.mounted) return;
      final label = context.t(en: 'File saved', ar: 'تم حفظ الملف');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: $storedPath')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  static Future<Uint8List> _generatePdfBytes(
    BuildContext buildContext,
    List<EmployeeReport> reports,
  ) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) {
          final headers = [
            buildContext.t(en: 'Employee', ar: 'الموظف'),
            buildContext.t(en: 'Role', ar: 'الدور'),
            buildContext.t(en: 'Entered', ar: 'إدخال'),
            buildContext.t(en: 'Reviewed', ar: 'مراجعة'),
            buildContext.t(en: 'Shipped', ar: 'شحن'),
            buildContext.t(en: 'Completed', ar: 'مكتمل'),
            buildContext.t(en: 'Returned', ar: 'مرتجع'),
            buildContext.t(en: 'Order #', ar: 'رقم الطلب'),
            buildContext.t(en: 'Customer', ar: 'اسم العميل'),
            buildContext.t(en: 'Phone', ar: 'الهاتف'),
            buildContext.t(en: 'Address', ar: 'العنوان'),
          ];

          final data = reports.map((report) {
            final latest = report.orderDetails.isEmpty ? null : report.orderDetails.first;
            return [
              report.userName,
              buildContext.roleLabel(report.role),
              '${report.ordersEntered}',
              '${report.ordersReviewed}',
              '${report.ordersShipped}',
              '${report.ordersCompleted}',
              '${report.ordersReturned}',
              latest == null ? '-' : '#${latest.orderNo}',
              latest?.customerName ?? '-',
              latest?.customerPhone ?? '-',
              latest?.customerAddress ?? '-',
            ];
          }).toList();

          final isRtl = Localizations.localeOf(buildContext).languageCode == 'ar';
          return [
            pw.Directionality(
              textDirection:
                  isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Header(
                    level: 0,
                    text: buildContext.t(en: 'Employee reports', ar: 'تقارير الموظفين'),
                  ),
                  pw.Paragraph(
                    text: buildContext.t(
                      en: 'Generated employee performance report with latest order details.',
                      ar: 'تقرير أداء الموظفين متضمنًا أحدث تفاصيل الطلبات.',
                    ),
                  ),
                  pw.TableHelper.fromTextArray(
                    headers: headers,
                    data: data,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  static String _timestamp() {
    final now = DateTime.now().toUtc();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.onExportExcel,
    required this.onExportPdf,
  });

  final VoidCallback onExportExcel;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(en: 'Reports', ar: 'التقارير'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              context.t(
                en: 'Quick, calm overview of team performance and orders.',
                ar: 'نظرة هادئة وسريعة على أداء الفريق والطلبات.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: onExportPdf,
              child: Text(context.t(en: 'PDF', ar: 'PDF')),
            ),
            FilledButton(
              onPressed: onExportExcel,
              child: Text(context.t(en: 'Excel', ar: 'Excel')),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmployeesGrid extends StatelessWidget {
  const _EmployeesGrid({
    required this.reports,
    required this.localeTag,
  });

  final List<EmployeeReport> reports;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;
        final isMedium = constraints.maxWidth >= 760;
        final crossAxisCount = isWide
            ? 3
            : isMedium
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reports.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isWide ? 1.35 : 1.1,
          ),
          itemBuilder: (context, index) {
            final report = reports[index];
            return _EmployeeCard(report: report, localeTag: localeTag);
          },
        );
      },
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.report, required this.localeTag});

  final EmployeeReport report;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    final latest = report.orderDetails.isEmpty ? null : report.orderDetails.first;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text(report.userName.characters.first.toUpperCase()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report.userName, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(context.roleLabel(report.role), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (latest != null)
                  Chip(
                    label: Text(context.orderStatusLabel(latest.status)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _StatsRow(report: report),
            if (latest != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t(en: 'Latest order', ar: 'أحدث طلب'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text('#${latest.orderNo} • ${latest.customerName}'),
                    Text(latest.customerPhone),
                    Text(latest.customerAddress ?? '-'),
                    Text(
                      AppFormatters.shortDateTime(latest.actionAt, localeTag),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.report});

  final EmployeeReport report;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _Metric(
        label: context.t(en: 'Entered', ar: 'إدخال'),
        value: report.ordersEntered,
      ),
      _Metric(
        label: context.t(en: 'Reviewed', ar: 'مراجعة'),
        value: report.ordersReviewed,
      ),
      _Metric(
        label: context.t(en: 'Shipped', ar: 'شحن'),
        value: report.ordersShipped,
      ),
      _Metric(
        label: context.t(en: 'Completed', ar: 'مكتمل'),
        value: report.ordersCompleted,
      ),
      _Metric(
        label: context.t(en: 'Returned', ar: 'مرتجع'),
        value: report.ordersReturned,
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: metrics.map((m) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              LtrText(
                '${m.value}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Metric {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;
}

class _EmployeeOrdersPanel extends StatelessWidget {
  const _EmployeeOrdersPanel({
    required this.report,
    required this.localeTag,
  });

  final EmployeeReport report;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    final rows = report.orderDetails.take(10).toList();
    return StandardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(
              en: 'Order details for ${report.userName}',
              ar: 'تفاصيل طلبات ${report.userName}',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(context.t(en: 'Order #', ar: 'رقم الطلب'))),
                DataColumn(label: Text(context.t(en: 'Customer', ar: 'اسم العميل'))),
                DataColumn(label: Text(context.t(en: 'Phone', ar: 'رقم الهاتف'))),
                DataColumn(label: Text(context.t(en: 'Address', ar: 'العنوان'))),
                DataColumn(label: Text(context.t(en: 'Status', ar: 'الحالة'))),
                DataColumn(label: Text(context.t(en: 'Date', ar: 'التاريخ'))),
              ],
              rows: rows.map((detail) {
                return DataRow(
                  cells: [
                    DataCell(Text('#${detail.orderNo}')),
                    DataCell(Text(detail.customerName)),
                    DataCell(Text(detail.customerPhone)),
                    DataCell(Text(detail.customerAddress ?? '-')),
                    DataCell(Text(context.orderStatusLabel(detail.status))),
                    DataCell(Text(AppFormatters.shortDateTime(detail.actionAt, localeTag))),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.reports,
    required this.localeTag,
  });

  final List<EmployeeReport> reports;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    final withOrders = reports.where((r) => r.orderDetails.isNotEmpty).toList();
    if (withOrders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(en: 'Order details', ar: 'تفاصيل الطلبات'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        ...withOrders.map(
          (report) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EmployeeOrdersPanel(
              report: report,
              localeTag: localeTag,
            ),
          ),
        ),
      ],
    );
  }
}
