import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/services/order_workflow_engine.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/domain/repositories/wms_repository.dart';

class TransitionOrderUseCase {
  const TransitionOrderUseCase(this._repository, this._workflow);

  final WmsRepository _repository;
  final OrderWorkflowEngine _workflow;

  Future<void> call({
    required AppUser actor,
    required OrderEntity order,
    required OrderStatus nextStatus,
    String? note,
  }) {
    _workflow.ensureCanTransition(
      actor: actor,
      current: order.status,
      next: nextStatus,
    );

    return _repository.transitionOrder(
      actor: actor,
      orderId: order.id,
      nextStatus: nextStatus,
      note: note,
    );
  }
}
