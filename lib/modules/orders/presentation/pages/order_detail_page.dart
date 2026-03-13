import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/modules/orders/presentation/pages/create_order_page.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(orderDetailProvider(orderId));

    if (detail.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final order = detail.value ?? ref.watch(orderByIdProvider(orderId));
    if (order == null) {
      return Scaffold(
        body: EmptyPlaceholder(
          title: context.t(en: 'Order not found', ar: 'الطلب غير موجود'),
          subtitle: context.t(
            en: 'The selected order could not be loaded.',
            ar: 'تعذر تحميل الطلب المحدد.',
          ),
        ),
      );
    }

    final availableTransitions = ref.watch(availableTransitionsProvider(order));
    final operationState = ref.watch(operationsControllerProvider);
    final user = ref.watch(currentUserProvider)!;
    final canEdit = user.hasPermission(AppPermission.ordersEdit);
    final canDelete = user.hasPermission(AppPermission.ordersDelete);
    final canOverride = user.hasPermission(AppPermission.ordersOverride);

    return Scaffold(
      appBar: AppBar(title: Text('طلب رقم ${order.orderNo}')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionPanel(
            title: context.t(en: 'Overview', ar: 'نظرة عامة'),
            trailing: StatusBadge(order.status),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Info(
                  label: context.t(en: 'Customer', ar: 'العميل'),
                  value: order.customerName,
                ),
                _Info(
                  label: context.t(en: 'Phone', ar: 'الهاتف'),
                  value: order.customerPhone,
                ),
                _Info(
                  label: context.t(en: 'Created By', ar: 'أنشأه'),
                  value: order.createdByName,
                ),
                _Info(
                  label: context.t(en: 'Date', ar: 'التاريخ'),
                  value: AppFormatters.shortDateTime(order.orderDate),
                ),
                _Info(
                  label: context.t(en: 'Total Cost', ar: 'إجمالي التكلفة'),
                  value: AppFormatters.currency(order.totalCost),
                ),
                _Info(
                  label: context.t(en: 'Revenue', ar: 'الإيراد'),
                  value: AppFormatters.currency(order.totalRevenue),
                ),
                _Info(
                  label: context.t(en: 'Profit', ar: 'الربح'),
                  value: AppFormatters.currency(order.profit),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionPanel(
            title: context.t(en: 'Administration', ar: 'الإدارة'),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (canEdit)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CreateOrderPage(orderId: order.id),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(context.t(en: 'Edit Order', ar: 'تعديل الطلب')),
                  ),
                if (canDelete)
                  OutlinedButton.icon(
                    onPressed: operationState.isLoading
                        ? null
                        : () => _deleteOrder(context, ref, order.id),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(context.t(en: 'Delete Order', ar: 'حذف الطلب')),
                  ),
                if (canOverride)
                  PopupMenuButton<OrderStatus>(
                    onSelected: (status) =>
                        _overrideOrder(context, ref, order.id, status),
                    itemBuilder: (context) => [
                      for (final status in OrderStatus.values)
                        PopupMenuItem(
                          value: status,
                          child: Text(
                            context.t(
                              en: 'Override to ${context.orderStatusLabel(status)}',
                              ar: 'تجاوز إلى ${context.orderStatusLabel(status)}',
                            ),
                          ),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.admin_panel_settings_outlined),
                          const SizedBox(width: 8),
                          Text(
                            context.t(
                              en: 'Override Status',
                              ar: 'تجاوز الحالة',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionPanel(
            title: context.t(en: 'Order Items', ar: 'بنود الطلب'),
            child: Column(
              children: order.items
                  .map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.productName),
                      subtitle: Text(
                        context.t(
                          en: 'Qty ${item.quantity} • ${AppFormatters.currency(item.salePrice)}',
                          ar: 'كمية ${item.quantity} • ${AppFormatters.currency(item.salePrice)}',
                        ),
                      ),
                      trailing: Text(AppFormatters.currency(item.totalRevenue)),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          SectionPanel(
            title: context.t(en: 'Workflow Timeline', ar: 'سجل سير العمل'),
            child: Column(
              children: order.history
                  .map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timeline),
                      title: Text(context.orderStatusLabel(entry.status)),
                      subtitle: Text(
                        '${entry.changedByName} • ${AppFormatters.shortDateTime(entry.changedAt)}',
                      ),
                      trailing: entry.note == null ? null : Text(entry.note!),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (availableTransitions.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionPanel(
              title: context.t(en: 'Next Actions', ar: 'الخطوات التالية'),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: availableTransitions
                    .map(
                      (status) => FilledButton.icon(
                        onPressed: operationState.isLoading
                            ? null
                            : () => _transition(context, ref, order, status),
                        icon: const Icon(Icons.sync_alt),
                        label: Text(
                          context.t(
                            en: 'Move to ${context.orderStatusLabel(status)}',
                            ar: 'نقل إلى ${context.orderStatusLabel(status)}',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    OrderEntity order,
    OrderStatus status,
  ) async {
    await ref
        .read(operationsControllerProvider.notifier)
        .transitionOrder(order: order, nextStatus: status);
    final state = ref.read(operationsControllerProvider);
    if (!context.mounted) {
      return;
    }
    if (state.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error.toString())));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t(
            en: 'Order updated successfully.',
            ar: 'تم تحديث الطلب بنجاح.',
          ),
        ),
      ),
    );
  }

  Future<void> _overrideOrder(
    BuildContext context,
    WidgetRef ref,
    String orderId,
    OrderStatus status,
  ) async {
    await ref
        .read(operationsControllerProvider.notifier)
        .overrideOrderStatus(orderId: orderId, nextStatus: status);
    final state = ref.read(operationsControllerProvider);
    if (!context.mounted) {
      return;
    }
    if (state.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error.toString())));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t(en: 'Override applied.', ar: 'تم تطبيق التجاوز.'),
        ),
      ),
    );
  }

  Future<void> _deleteOrder(
    BuildContext context,
    WidgetRef ref,
    String orderId,
  ) async {
    await ref.read(operationsControllerProvider.notifier).deleteOrder(orderId);
    final state = ref.read(operationsControllerProvider);
    if (!context.mounted) {
      return;
    }
    if (state.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error.toString())));
      return;
    }
    Navigator.of(context).pop();
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
