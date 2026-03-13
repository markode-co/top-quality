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
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _orderLabel(order),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '• ${AppFormatters.shortDateTime(order.orderDate)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(order.status),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 520;
                  final metrics = [
                    _Metric(
                      label: context.t(en: 'Items', ar: 'الأصناف'),
                      value: '${order.totalQuantity}',
                    ),
                    _Metric(
                      label: context.t(en: 'Revenue', ar: 'الإيراد'),
                      value: AppFormatters.currency(order.totalRevenue),
                      ltr: true,
                    ),
                    _Metric(
                      label: context.t(en: 'Profit', ar: 'الربح'),
                      value: AppFormatters.currency(order.profit),
                      ltr: true,
                    ),
                  ];

                  if (!narrow) {
                    return Row(
                      children: [
                        for (final m in metrics) Expanded(child: m),
                      ],
                    );
                  }

                  final w = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      for (final m in metrics)
                        SizedBox(width: w, child: m),
                    ],
                  );
                },
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
  const _Metric({required this.label, required this.value, this.ltr = false});

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.titleSmall;
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    final valueWidget = ltr
        ? LtrText(value, style: valueStyle, maxLines: 1)
        : Text(value, style: valueStyle, maxLines: 1, overflow: TextOverflow.ellipsis);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        valueWidget,
      ],
    );
  }
}
