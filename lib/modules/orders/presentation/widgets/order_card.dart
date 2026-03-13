import 'package:flutter/material.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.onTap,
    this.trailing,
  });

  final OrderEntity order;
  final VoidCallback onTap;
  final Widget? trailing;

  String _orderLabel(OrderEntity order) => 'طلب رقم ${order.orderNo}';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                    '${_orderLabel(order)} • ${AppFormatters.shortDateTime(order.orderDate)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(order.status),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Metric(
                    label: context.t(en: 'Items', ar: 'الأصناف'),
                    value: '${order.totalQuantity}',
                  ),
                  _Metric(
                    label: context.t(en: 'Revenue', ar: 'الإيراد'),
                    value: AppFormatters.currency(order.totalRevenue),
                  ),
                  _Metric(
                    label: context.t(en: 'Profit', ar: 'الربح'),
                    value: AppFormatters.currency(order.profit),
                  ),
                ],
              ),
              if (trailing != null) ...[
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: trailing!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
