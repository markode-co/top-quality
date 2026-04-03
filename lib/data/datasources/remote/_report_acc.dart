import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/domain/entities/dashboard_snapshot.dart';

class ReportAcc {
  ReportAcc({required this.id, required this.name});
  final String id;
  final String name;

  // Deduplicate per (order_id, status) to keep reports stable even if history rows are repeated.
  final Set<String> enteredOrderIds = {};
  final Set<String> reviewedOrderIds = {};
  final Set<String> shippedOrderIds = {};
  final Set<String> completedOrderIds = {};
  final Set<String> returnedOrderIds = {};
  final Map<String, EmployeeOrderDetail> orderDetailsByKey = {};

  void addOrderDetail({
    required String orderId,
    required int orderNo,
    required String customerName,
    required String customerPhone,
    required String? customerAddress,
    required OrderStatus status,
    required DateTime actionAt,
  }) {
    final key = '$orderId-${status.name}';
    final existing = orderDetailsByKey[key];
    if (existing == null || actionAt.isAfter(existing.actionAt)) {
      orderDetailsByKey[key] = EmployeeOrderDetail(
        orderId: orderId,
        orderNo: orderNo,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        status: status,
        actionAt: actionAt,
      );
    }
  }

  EmployeeReport toReport() => EmployeeReport(
        userId: id,
        userName: name,
        role: UserRole.orderEntry,
        ordersEntered: enteredOrderIds.length,
        ordersReviewed: reviewedOrderIds.length,
        ordersShipped: shippedOrderIds.length,
        ordersCompleted: completedOrderIds.length,
        ordersReturned: returnedOrderIds.length,
        orderDetails: orderDetailsByKey.values.toList()
          ..sort((a, b) => b.actionAt.compareTo(a.actionAt)),
      );
}
