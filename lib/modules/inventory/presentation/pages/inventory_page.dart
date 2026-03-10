import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/product.dart';
import 'package:top_quality/domain/entities/product_draft.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsValue = ref.watch(productsProvider);
    final currentUser = ref.watch(currentUserProvider);
    final canCreate =
        currentUser?.hasPermission(AppPermission.productsCreate) ?? false;
    final canEdit =
        currentUser?.hasPermission(AppPermission.productsEdit) ?? false;
    final canDelete =
        currentUser?.hasPermission(AppPermission.productsDelete) ?? false;
    final canAdjust =
        currentUser?.hasPermission(AppPermission.inventoryEdit) ?? false;

    return productsValue.when(
      data: (products) {
        final filtered = products.where((product) {
          final query = _searchController.text.trim().toLowerCase();
          if (query.isEmpty) {
            return true;
          }
          return product.name.toLowerCase().contains(query) ||
              product.sku.toLowerCase().contains(query) ||
              product.category.toLowerCase().contains(query);
        }).toList();

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
                      prefixIcon: const Icon(Icons.search),
                      hintText: context.t(
                        en: 'Search by name, SKU, or category',
                        ar: 'ابحث بالاسم أو SKU أو الفئة',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (canCreate)
                  FilledButton.icon(
                    onPressed: () => _showProductDialog(context),
                    icon: const Icon(Icons.add_box_outlined),
                    label: Text(context.t(en: 'Add Product', ar: 'إضافة منتج')),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...filtered.map(
              (product) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(product.name),
                  subtitle: Text('${product.sku} • ${product.category}'),
                  trailing: Wrap(
                    spacing: 20,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MetricText(
                        label: context.t(en: 'Stock', ar: 'المخزون'),
                        value: '${product.currentStock}',
                      ),
                      _MetricText(
                        label: context.t(en: 'Price', ar: 'السعر'),
                        value: AppFormatters.currency(product.salePrice),
                      ),
                      _MetricText(
                        label: context.t(en: 'Profit', ar: 'الربح'),
                        value: AppFormatters.currency(product.unitProfit),
                      ),
                      _MetricText(
                        label: context.t(en: 'Status', ar: 'الحالة'),
                        value: product.isLowStock
                            ? context.t(en: 'Low Stock', ar: 'مخزون منخفض')
                            : context.t(en: 'Healthy', ar: 'مستقر'),
                        color: product.isLowStock
                            ? const Color(0xFFB63D3D)
                            : const Color(0xFF0C6B58),
                      ),
                      if (canAdjust)
                        IconButton(
                          onPressed: () =>
                              _showInventoryDialog(context, product),
                          icon: const Icon(Icons.tune),
                          tooltip: context.t(
                            en: 'Adjust Inventory',
                            ar: 'تعديل المخزون',
                          ),
                        ),
                      if (canEdit)
                        IconButton(
                          onPressed: () =>
                              _showProductDialog(context, product: product),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: context.t(
                            en: 'Edit Product',
                            ar: 'تعديل المنتج',
                          ),
                        ),
                      if (canDelete)
                        IconButton(
                          onPressed: () => _deleteProduct(product.id),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: context.t(
                            en: 'Archive Product',
                            ar: 'أرشفة المنتج',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  Future<void> _showProductDialog(
    BuildContext context, {
    Product? product,
  }) async {
    final nameController = TextEditingController(text: product?.name ?? '');
    final skuController = TextEditingController(text: product?.sku ?? '');
    final categoryController = TextEditingController(
      text: product?.category ?? '',
    );
    final purchaseController = TextEditingController(
      text: product?.purchasePrice.toString() ?? '',
    );
    final saleController = TextEditingController(
      text: product?.salePrice.toString() ?? '',
    );
    final stockController = TextEditingController(
      text: product?.currentStock.toString() ?? '0',
    );
    final minStockController = TextEditingController(
      text: product?.minStockLevel.toString() ?? '0',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          product == null
              ? context.t(en: 'Add Product', ar: 'إضافة منتج')
              : context.t(en: 'Edit Product', ar: 'تعديل المنتج'),
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  keyboardType: TextInputType.name,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    labelText: context.t(en: 'Name', ar: 'الاسم'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: skuController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(labelText: 'SKU'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: context.t(en: 'Category', ar: 'الفئة'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: purchaseController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: context.t(
                      en: 'Purchase Price (EGP)',
                      ar: 'سعر الشراء (EGP)',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: saleController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: context.t(
                      en: 'Sale Price (EGP)',
                      ar: 'سعر البيع (EGP)',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.t(
                      en: 'Current Stock',
                      ar: 'المخزون الحالي',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minStockController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.t(
                      en: 'Minimum Stock',
                      ar: 'الحد الأدنى للمخزون',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t(en: 'Cancel', ar: 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t(en: 'Save', ar: 'حفظ')),
          ),
        ],
      ),
    );

    if (saved != true) {
      return;
    }

    final purchasePrice = double.tryParse(purchaseController.text.trim());
    final salePrice = double.tryParse(saleController.text.trim());
    final stock = int.tryParse(stockController.text.trim());
    final minStockLevel = int.tryParse(minStockController.text.trim());

    if (purchasePrice == null ||
        salePrice == null ||
        stock == null ||
        minStockLevel == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                en: 'Invalid numeric value. Check prices and stock fields.',
                ar: 'رقم غير صالح. راجع حقول الأسعار والمخزون.',
              ),
            ),
          ),
        );
      }
      return;
    }

    await ref
        .read(operationsControllerProvider.notifier)
        .upsertProduct(
          ProductDraft(
            id: product?.id,
            name: nameController.text.trim(),
            sku: skuController.text.trim(),
            category: categoryController.text.trim(),
            purchasePrice: purchasePrice,
            salePrice: salePrice,
            stock: stock,
            minStockLevel: minStockLevel,
          ),
        );

    if (!context.mounted) {
      return;
    }
    _showOperationResult(context);
  }

  Future<void> _showInventoryDialog(
    BuildContext context,
    Product product,
  ) async {
    final qtyController = TextEditingController(text: '0');
    final reasonController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.t(
            en: 'Adjust Inventory • ${product.name}',
            ar: 'تعديل المخزون • ${product.name}',
          ),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.t(
                    en: 'Quantity Delta (+/-)',
                    ar: 'فرق الكمية (+/-)',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: context.t(en: 'Reason', ar: 'السبب'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t(en: 'Cancel', ar: 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t(en: 'Apply', ar: 'تطبيق')),
          ),
        ],
      ),
    );

    if (saved != true) {
      return;
    }

    final quantityDelta = int.tryParse(qtyController.text.trim());
    if (quantityDelta == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                en: 'Invalid quantity value.',
                ar: 'رقم الكمية غير صالح.',
              ),
            ),
          ),
        );
      }
      return;
    }

    await ref
        .read(operationsControllerProvider.notifier)
        .adjustInventory(
          productId: product.id,
          quantityDelta: quantityDelta,
          reason: reasonController.text.trim(),
        );

    if (!context.mounted) {
      return;
    }
    _showOperationResult(context);
  }

  Future<void> _deleteProduct(String productId) async {
    await ref
        .read(operationsControllerProvider.notifier)
        .deleteProduct(productId);
    if (!mounted) {
      return;
    }
    _showOperationResult(context);
  }

  void _showOperationResult(BuildContext context) {
    final state = ref.read(operationsControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error.toString())));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t(en: 'Operation completed.', ar: 'تم تنفيذ العملية.'),
        ),
      ),
    );
  }
}

class _MetricText extends StatelessWidget {
  const _MetricText({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
