import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class AdvancedReportsPage extends ConsumerWidget {
  const AdvancedReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider).valueOrNull ?? const <OrderEntity>[];
    final localeTag = Localizations.localeOf(context).toString();
    final recentOrders = orders.toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate));

    final totalRevenue = orders.fold<double>(0, (sum, order) => sum + order.totalRevenue);
    final totalProfit = orders.fold<double>(0, (sum, order) => sum + order.profit);
    final totalOrders = orders.length;
    final averageOrder = totalOrders == 0 ? 0.0 : totalRevenue / totalOrders;

    final productsRevenue = <String, double>{};
    for (final order in orders) {
      for (final item in order.items) {
        productsRevenue[item.productName] =
            (productsRevenue[item.productName] ?? 0) + item.totalRevenue;
      }
    }

    final topProducts = productsRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final statusCounts = <OrderStatus, int>{};
    for (final order in orders) {
      statusCounts[order.status] = (statusCounts[order.status] ?? 0) + 1;
    }

    return ResponsiveListView(
      children: [
        SectionHeader(
          title: context.t(en: 'Advanced analytics', ar: 'التقارير المتقدمة'),
          subtitle: context.t(
            en: 'Deep insights into sales, operations, and branch performance.',
            ar: 'تحليلات تفصيلية للمبيعات والعمليات وأداء الفروع.',
          ),
        ),
        _MetricsGrid(
          metrics: [
            _Metric(
              title: context.t(en: 'Total revenue', ar: 'إجمالي الإيرادات'),
              value: AppFormatters.currency(totalRevenue, localeTag),
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.payments_outlined,
            ),
            _Metric(
              title: context.t(en: 'Total profit', ar: 'إجمالي الربح'),
              value: AppFormatters.currency(totalProfit, localeTag),
              color: Theme.of(context).colorScheme.secondary,
              icon: Icons.savings_outlined,
            ),
            _Metric(
              title: context.t(en: 'Orders processed', ar: 'الطلبات المنفذة'),
              value: '$totalOrders',
              color: Theme.of(context).colorScheme.tertiary,
              icon: Icons.receipt_long_outlined,
            ),
            _Metric(
              title: context.t(en: 'Average order', ar: 'متوسط الطلب'),
              value: AppFormatters.currency(averageOrder, localeTag),
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.auto_graph_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'Order status distribution', ar: 'توزيع حالات الطلبات'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: statusCounts.entries.map((entry) {
                  return Chip(
                    label: Text('${context.orderStatusLabel(entry.key)}: ${entry.value}'),
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.65),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'Top products by revenue', ar: 'أعلى المنتجات إيرادًا'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              if (topProducts.isEmpty)
                Text(
                  context.t(en: 'No sales data yet.', ar: 'لا توجد بيانات مبيعات بعد.'),
                )
              else
                Column(
                  children: topProducts.take(6).map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(entry.key)),
                          Text(AppFormatters.currency(entry.value, localeTag)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        StandardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(en: 'Recent orders details', ar: 'تفاصيل أحدث الطلبات'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (recentOrders.isEmpty)
                Text(
                  context.t(en: 'No orders to show yet.', ar: 'لا توجد طلبات للعرض بعد.'),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text(context.t(en: 'Order #', ar: 'رقم الطلب'))),
                      DataColumn(label: Text(context.t(en: 'Customer', ar: 'اسم العميل'))),
                      DataColumn(label: Text(context.t(en: 'Phone', ar: 'رقم الهاتف'))),
                      DataColumn(label: Text(context.t(en: 'Address', ar: 'العنوان'))),
                      DataColumn(label: Text(context.t(en: 'Status', ar: 'الحالة'))),
                    ],
                    rows: recentOrders.take(12).map((order) {
                      return DataRow(
                        cells: [
                          DataCell(Text('#${order.orderNo}')),
                          DataCell(Text(order.customerName)),
                          DataCell(Text(order.customerPhone)),
                          DataCell(Text(order.customerAddress ?? '-')),
                          DataCell(Text(context.orderStatusLabel(order.status))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 3.0 : 2.5,
          children: metrics.map((metric) => _MetricCard(metric: metric)).toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

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
              backgroundColor: metric.color.withValues(alpha: 0.16),
              child: Icon(metric.icon, color: metric.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(metric.title, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    metric.value,
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
