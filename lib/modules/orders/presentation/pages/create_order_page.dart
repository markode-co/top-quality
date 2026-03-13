import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/domain/entities/product.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class CreateOrderPage extends ConsumerStatefulWidget {
  const CreateOrderPage({super.key, this.orderId});

  final String? orderId;

  bool get isEditing => orderId != null;

  @override
  ConsumerState<CreateOrderPage> createState() => _CreateOrderPageState();
}

class _CreateOrderPageState extends ConsumerState<CreateOrderPage> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_DraftLine> _lines = [_DraftLine()];
  bool _seeded = false;

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsValue = ref.watch(productsProvider);
    final operationState = ref.watch(operationsControllerProvider);
    final existingOrder = widget.orderId == null
        ? null
        : ref.watch(orderByIdProvider(widget.orderId!));

    if (widget.isEditing && existingOrder != null && !_seeded) {
      _seedFromOrder(existingOrder);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? context.t(en: 'Edit Order', ar: 'تعديل الطلب')
              : context.t(en: 'Create Order', ar: 'إنشاء طلب'),
        ),
      ),
      body: productsValue.when(
        data: (products) => ResponsiveListView(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _customerController,
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Customer Name',
                        ar: 'اسم العميل',
                      ),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? context.t(en: 'Required', ar: 'مطلوب')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Customer Phone',
                        ar: 'هاتف العميل',
                      ),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? context.t(en: 'Required', ar: 'مطلوب')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: context.t(en: 'Address', ar: 'العنوان'),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? context.t(en: 'Required', ar: 'مطلوب')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: context.t(en: 'Notes', ar: 'ملاحظات'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ..._buildLines(products),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _lines.add(_DraftLine())),
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(
                        context.t(en: 'Add Product', ar: 'إضافة منتج'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: operationState.isLoading
                        ? null
                        : () => _submit(products),
                    icon: Icon(
                      widget.isEditing
                          ? Icons.edit_outlined
                          : Icons.save_outlined,
                    ),
                    label: Text(
                      widget.isEditing
                          ? context.t(en: 'Save Changes', ar: 'حفظ التعديلات')
                          : context.t(en: 'Create Order', ar: 'إنشاء الطلب'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }

  List<Widget> _buildLines(List<Product> products) {
    return List<Widget>.generate(_lines.length, (index) {
      final line = _lines[index];
      final selected = products.firstWhereOrNull(
        (product) => product.id == line.productId,
      );

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;

              final productField = DropdownButtonFormField<String>(
                initialValue: line.productId,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Product', ar: 'المنتج'),
                ),
                items: products
                    .map(
                      (product) => DropdownMenuItem(
                        value: product.id,
                        child: Text(
                          context.t(
                            en: '${product.name} (${product.currentStock} in stock)',
                            ar: '${product.name} (${product.currentStock} متوفر)',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => line.productId = value),
                validator: (value) => value == null
                    ? context.t(en: 'Required', ar: 'مطلوب')
                    : null,
              );

              final qty = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.t(en: 'Qty', ar: 'الكمية')),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: line.quantity > 1
                            ? () => setState(() => line.quantity--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      LtrText('${line.quantity}'),
                      IconButton(
                        onPressed:
                            selected != null &&
                                line.quantity < selected.currentStock
                                ? () => setState(() => line.quantity++)
                                : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              );

              final deleteBtn = IconButton(
                onPressed: _lines.length == 1
                    ? null
                    : () => setState(() => _lines.removeAt(index)),
                icon: const Icon(Icons.delete_outline),
              );

              if (narrow) {
                return Column(
                  children: [
                    productField,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: qty),
                        deleteBtn,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: productField),
                  const SizedBox(width: 12),
                  Expanded(child: qty),
                  deleteBtn,
                ],
              );
            },
          ),
        ),
      );
    });
  }

  void _seedFromOrder(OrderEntity order) {
    _seeded = true;
    _customerController.text = order.customerName;
    _phoneController.text = order.customerPhone;
    _addressController.text = order.customerAddress ?? '';
    _notesController.text = order.notes ?? '';
    _lines
      ..clear()
      ..addAll(
        order.items.map(
          (item) =>
              _DraftLine(productId: item.productId, quantity: item.quantity),
        ),
      );
  }

  Future<void> _submit(List<Product> products) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final items = <OrderItem>[];
    for (final line in _lines) {
      final product = products.firstWhereOrNull(
        (item) => item.id == line.productId,
      );
      if (product == null) {
        continue;
      }
      items.add(
        OrderItem(
          productId: product.id,
          productName: product.name,
          quantity: line.quantity,
          purchasePrice: product.purchasePrice,
          salePrice: product.salePrice,
        ),
      );
    }

    if (widget.isEditing) {
      await ref
          .read(operationsControllerProvider.notifier)
          .updateOrder(
            orderId: widget.orderId!,
            customerName: _customerController.text.trim(),
            customerPhone: _phoneController.text.trim(),
            customerAddress: _addressController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            items: items,
          );
    } else {
      await ref
          .read(operationsControllerProvider.notifier)
          .createOrder(
            customerName: _customerController.text.trim(),
            customerPhone: _phoneController.text.trim(),
            customerAddress: _addressController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            items: items,
          );
    }

    final state = ref.read(operationsControllerProvider);
    if (!mounted) {
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

class _DraftLine {
  _DraftLine({this.productId, this.quantity = 1});

  String? productId;
  int quantity;
}
