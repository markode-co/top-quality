import 'package:top_quality/core/services/order_workflow_engine.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/domain/repositories/wms_repository.dart';

class CreateOrderUseCase {
  const CreateOrderUseCase(this._repository, this._workflow);

  final WmsRepository _repository;
  final OrderWorkflowEngine _workflow;

  Future<void> call({
    required AppUser actor,
    required String customerName,
    required String customerPhone,
    required String? notes,
    required List<OrderItem> items,
  }) {
    _workflow.ensureCanCreate(actor);
    return _repository.createOrder(
      actor: actor,
      customerName: customerName,
      customerPhone: customerPhone,
      notes: notes,
      items: items,
    );
  }
}

