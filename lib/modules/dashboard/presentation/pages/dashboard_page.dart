import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, required this.onOpenOrder});

  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardValue = ref.watch(dashboardProvider);

    return dashboardValue.when(
      data: (snapshot) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1200
                  ? 4
                  : constraints.maxWidth > 800
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 16)) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 196),
                      child: StatCard(
                        title: context.t(
                          en: 'Total Orders',
                          ar: 'إجمالي الطلبات',
                        ),
                        value: '${snapshot.totalOrders}',
                        subtitle: context.t(
                          en: 'Across all workflow stages',
                          ar: 'عبر جميع مراحل سير العمل',
                        ),
                        icon: Icons.receipt_long_outlined,
                        color: const Color(0xFF0C6B58),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 196),
                      child: StatCard(
                        title: context.t(en: 'Revenue', ar: 'الإيراد'),
                        value: AppFormatters.currency(snapshot.revenue),
                        subtitle: context.t(
                          en: 'Realized from shipped/completed orders',
                          ar: 'متحقق من الطلبات المشحونة/المكتملة',
                        ),
                        icon: Icons.payments_outlined,
                        color: const Color(0xFFD97A29),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 196),
                      child: StatCard(
                        title: context.t(en: 'Profit', ar: 'الربح'),
                        value: AppFormatters.currency(snapshot.profit),
                        subtitle: context.t(
                          en: 'Calculated automatically per order',
                          ar: 'يُحسب تلقائيًا لكل طلب',
                        ),
                        icon: Icons.trending_up_outlined,
                        color: const Color(0xFF1E64B7),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 196),
                      child: StatCard(
                        title: context.t(
                          en: 'Low Stock Alerts',
                          ar: 'تنبيهات نقص المخزون',
                        ),
                        value: '${snapshot.lowStockAlerts}',
                        subtitle: context.t(
                          en: 'Products below minimum stock',
                          ar: 'منتجات أقل من الحد الأدنى',
                        ),
                        icon: Icons.warning_amber_rounded,
                        color: const Color(0xFFB63D3D),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 980;
              if (vertical) {
                return Column(
                  children: [
                    SectionPanel(
                      title: context.t(
                        en: 'Orders by Status',
                        ar: 'الطلبات حسب الحالة',
                      ),
                      child: SizedBox(
                        height: 260,
                        child: _StatusChart(snapshot.ordersByStatus),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionPanel(
                      title: context.t(en: 'Recent Orders', ar: 'أحدث الطلبات'),
                      child: Column(
                        children: snapshot.recentOrders.take(5).map((order) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(order.customerName),
                            subtitle: Text(order.id),
                            trailing: StatusBadge(order.status),
                            onTap: () => onOpenOrder(order.id),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SectionPanel(
                      title: context.t(
                        en: 'Orders by Status',
                        ar: 'الطلبات حسب الحالة',
                      ),
                      child: SizedBox(
                        height: 260,
                        child: _StatusChart(snapshot.ordersByStatus),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SectionPanel(
                      title: context.t(en: 'Recent Orders', ar: 'أحدث الطلبات'),
                      child: Column(
                        children: snapshot.recentOrders.take(5).map((order) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(order.customerName),
                            subtitle: Text(order.id),
                            trailing: StatusBadge(order.status),
                            onTap: () => onOpenOrder(order.id),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }
}

class _StatusChart extends StatelessWidget {
  const _StatusChart(this.data);

  final Map<OrderStatus, int> data;

  @override
  Widget build(BuildContext context) {
    final statuses = OrderStatus.values;
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 30),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= statuses.length) {
                  return const SizedBox.shrink();
                }
                final status = statuses[index];
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(context.orderStatusShort(status)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(statuses.length, (index) {
          final status = statuses[index];
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: (data[status] ?? 0).toDouble(),
                width: 24,
                color: const Color(0xFF0C6B58),
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          );
        }),
      ),
    );
  }
}
