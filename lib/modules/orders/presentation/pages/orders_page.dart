import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/modules/orders/presentation/widgets/order_card.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({
    super.key,
    required this.onOpenOrder,
    required this.onCreateOrder,
  });

  final ValueChanged<String> onOpenOrder;
  final VoidCallback onCreateOrder;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  final _searchController = TextEditingController();
  OrderStatus? _status;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersValue = ref.watch(ordersProvider);
    final user = ref.watch(currentUserProvider);
    final canCreate = user?.hasPermission(AppPermission.ordersCreate) ?? false;

    return ordersValue.when(
      data: (orders) {
        final filtered = _applyFilters(orders);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: context.t(
                        en: 'Search by customer, phone, or order ID',
                        ar: 'ابحث باسم العميل أو الهاتف أو رقم الطلب',
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (canCreate)
                  FilledButton.icon(
                    onPressed: widget.onCreateOrder,
                    icon: const Icon(Icons.add),
                    label: Text(
                      context.t(en: 'New Order', ar: 'طلب جديد'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(context.t(en: 'All', ar: 'الكل')),
                  selected: _status == null,
                  onSelected: (_) => setState(() => _status = null),
                ),
                ...OrderStatus.values.map(
                  (status) => FilterChip(
                    label: Text(context.orderStatusLabel(status)),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              SizedBox(
                height: 360,
                child: EmptyPlaceholder(
                  title: context.t(
                    en: 'No matching orders',
                    ar: 'لا توجد طلبات مطابقة',
                  ),
                  subtitle: context.t(
                    en: 'Adjust the search query or status filter.',
                    ar: 'عدّل عبارة البحث أو فلتر الحالة.',
                  ),
                ),
              )
            else
              ...filtered.map(
                (order) => OrderCard(
                  order: order,
                  onTap: () => widget.onOpenOrder(order.id),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  List<OrderEntity> _applyFilters(List<OrderEntity> orders) {
    final query = _searchController.text.trim().toLowerCase();
    return orders.where((order) {
      final matchesStatus = _status == null || order.status == _status;
      final matchesQuery =
          query.isEmpty ||
          order.id.toLowerCase().contains(query) ||
          order.customerName.toLowerCase().contains(query) ||
          order.customerPhone.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList();
  }
}
