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

    Future<void> refreshDashboard() async {
      ref.invalidate(dashboardProvider);
      try {
        await ref.read(dashboardProvider.future);
      } catch (_) {
        // ignore errors; UI shows failures.
      }
    }

    return dashboardValue.when(
      data: (snapshot) => ResponsiveListView(
        onRefresh: refreshDashboard,
        children: [
          SectionHeader(
            title: context.t(en: 'Executive dashboard', ar: 'لوحة التحكم'),
            subtitle: context.t(
              en: 'A modern view of orders, revenue, inventory and team activity.',
              ar: 'عرض حديث للطلبات والإيرادات والمخزون ونشاط الفريق.',
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1200
                  ? 4
                  : constraints.maxWidth > 900
                      ? 2
                      : 1;
              final width = (constraints.maxWidth - ((columns - 1) * 16)) / columns;
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
                          en: 'Orders tracked across the system',
                          ar: 'الطلبات المتتبعة عبر النظام',
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
                        value: AppFormatters.currency(
                          snapshot.revenue,
                          Localizations.localeOf(context).toString(),
                        ),
                        subtitle: context.t(
                          en: 'From completed and shipped orders',
                          ar: 'من الطلبات المكتملة والمشحونة',
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
                        value: AppFormatters.currency(
                          snapshot.profit,
                          Localizations.localeOf(context).toString(),
                        ),
                        subtitle: context.t(
                          en: 'Net margin across all sales',
                          ar: 'الهامش الصافي عبر جميع المبيعات',
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
                        title: context.t(en: 'Inventory value', ar: 'قيمة المخزون'),
                        value: AppFormatters.currency(
                          snapshot.inventoryValue,
                          Localizations.localeOf(context).toString(),
                        ),
                        subtitle: context.t(
                          en: 'Current stock value in warehouse',
                          ar: 'قيمة المخزون الحالية في المستودع',
                        ),
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFF6C63FF),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 196),
                      child: StatCard(
                        title: context.t(
                          en: 'Low stock alerts',
                          ar: 'تنبيهات نقص المخزون',
                        ),
                        value: '${snapshot.lowStockAlerts}',
                        subtitle: context.t(
                          en: 'Products below warning threshold',
                          ar: 'منتجات تحت حد التحذير',
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
                            subtitle: Text(
                              context.t(
                                en: 'Order #${order.orderNo}',
                                ar: 'طلب رقم ${order.orderNo}',
                              ),
                            ),
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
                            subtitle: Text(
                              context.t(
                                en: 'Order #${order.orderNo}',
                                ar: 'طلب رقم ${order.orderNo}',
                              ),
                            ),
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

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.entered:
        return const Color(0xFF2C82C9);
      case OrderStatus.checked:
        return const Color(0xFF6C63FF);
      case OrderStatus.approved:
        return const Color(0xFF17A2B8);
      case OrderStatus.shipped:
        return const Color(0xFFFFC107);
      case OrderStatus.completed:
        return const Color(0xFF2BB673);
      case OrderStatus.returned:
        return const Color(0xFFE74C3C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = OrderStatus.values;
    final maxY =
        (data.values.isEmpty ? 0 : data.values.reduce((a, b) => a > b ? a : b))
            .toDouble();

    if (maxY == 0) {
      return Center(
        child: Text(
          context.t(
            en: 'No data available yet.',
            ar: 'لا توجد بيانات للعرض الآن',
          ),
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.25,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY / 4).clamp(1, double.infinity),
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: (maxY / 4).clamp(1, double.infinity),
              getTitlesWidget: (value, meta) => Text(
                value % 1 == 0 ? value.toInt().toString() : '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= statuses.length) {
                  return const SizedBox.shrink();
                }
                final status = statuses[index];
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    context.orderStatusLabel(status),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => Colors.black87,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final status = statuses[group.x.toInt()];
              final count = data[status] ?? 0;
              return BarTooltipItem(
                '${context.orderStatusLabel(status)}\n$count',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(statuses.length, (index) {
          final status = statuses[index];
          final count = (data[status] ?? 0).toDouble();
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: count,
                width: 26,
                borderRadius: BorderRadius.circular(10),
                color: _statusColor(status),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: Colors.grey.withValues(alpha: 0.08),
                ),
                gradient: LinearGradient(
                  colors: [
                    _statusColor(status),
                    _statusColor(status).withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
