import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/domain/entities/dashboard_snapshot.dart';

class ReportAcc {
  ReportAcc({required this.id, required this.name});
  final String id;
  final String name;
  int entered = 0;
  int reviewed = 0;
  int shipped = 0;
  int returned = 0;

  EmployeeReport toReport() => EmployeeReport(
        userId: id,
        userName: name,
        role: UserRole.orderEntry,
        ordersEntered: entered,
        ordersReviewed: reviewed,
        ordersShipped: shipped,
        ordersReturned: returned,
      );
}
