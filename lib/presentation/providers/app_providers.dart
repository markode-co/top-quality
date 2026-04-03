import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/services/order_workflow_engine.dart';
import 'package:top_quality/data/datasources/remote/backend_data_source.dart';
import 'package:top_quality/data/datasources/remote/firebase_backend_data_source.dart';
import 'package:top_quality/data/repositories_impl/auth_repository_impl.dart';
import 'package:top_quality/data/repositories_impl/wms_repository_impl.dart';
import 'package:top_quality/domain/entities/activity_log.dart';
import 'package:top_quality/domain/entities/app_notification.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/entities/dashboard_snapshot.dart';
import 'package:top_quality/domain/entities/employee_draft.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/domain/entities/product.dart';
import 'package:top_quality/domain/entities/product_draft.dart';
import 'package:top_quality/domain/repositories/auth_repository.dart';
import 'package:top_quality/domain/repositories/wms_repository.dart';
import 'package:top_quality/domain/usecases/create_order.dart';
import 'package:top_quality/domain/usecases/sign_in.dart';
import 'package:top_quality/domain/usecases/sign_out.dart';
import 'package:top_quality/domain/usecases/transition_order.dart';

final appModeProvider = Provider<AppMode>((ref) => AppMode.live);

Locale _defaultLocaleFromSystem() {
  final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
  final languageCode = platformLocale.languageCode.toLowerCase();
  if (languageCode == 'ar') {
    return const Locale('ar', 'EG');
  }
  return const Locale('en', 'US');
}

final appLocaleProvider = StateProvider<Locale>((ref) => _defaultLocaleFromSystem());
final appThemeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final backendConfiguredProvider = Provider<bool>(
  (ref) => ref.watch(appModeProvider) == AppMode.live,
);

final workflowEngineProvider = Provider<OrderWorkflowEngine>(
  (ref) => const OrderWorkflowEngine(),
);

final backendDataSourceProvider = Provider<BackendDataSource>(
  (ref) => FirebaseBackendDataSource(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(backendDataSourceProvider)),
);

final wmsRepositoryProvider = Provider<WmsRepository>(
  (ref) => WmsRepositoryImpl(ref.watch(backendDataSourceProvider)),
);

final signInUseCaseProvider = Provider<SignInUseCase>(
  (ref) => SignInUseCase(ref.watch(authRepositoryProvider)),
);

final signOutUseCaseProvider = Provider<SignOutUseCase>(
  (ref) => SignOutUseCase(ref.watch(authRepositoryProvider)),
);

final createOrderUseCaseProvider = Provider<CreateOrderUseCase>(
  (ref) => CreateOrderUseCase(
    ref.watch(wmsRepositoryProvider),
    ref.watch(workflowEngineProvider),
  ),
);

final transitionOrderUseCaseProvider = Provider<TransitionOrderUseCase>(
  (ref) => TransitionOrderUseCase(
    ref.watch(wmsRepositoryProvider),
    ref.watch(workflowEngineProvider),
  ),
);

final sessionProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchSession(),
);

final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(sessionProvider).valueOrNull,
);

final ordersProvider = StreamProvider<List<OrderEntity>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<List<OrderEntity>>.value(const []);
  }
  return ref.watch(wmsRepositoryProvider).watchOrders();
});

final productsProvider = StreamProvider<List<Product>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<List<Product>>.value(const []);
  }
  return ref.watch(wmsRepositoryProvider).watchProducts();
});

final usersProvider = StreamProvider<List<AppUser>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<List<AppUser>>.value(const []);
  }
  return ref.watch(wmsRepositoryProvider).watchUsers();
});

final activityLogsProvider = StreamProvider<List<ActivityLog>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<List<ActivityLog>>.value(const []);
  }
  return ref.watch(wmsRepositoryProvider).watchActivityLogs();
});

final dashboardProvider = StreamProvider<DashboardSnapshot>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const Stream<DashboardSnapshot>.empty();
  }
  return ref.watch(wmsRepositoryProvider).watchDashboardSnapshot();
});

final employeeReportsProvider = StreamProvider<List<EmployeeReport>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<List<EmployeeReport>>.value(const []);
  }
  return ref.watch(wmsRepositoryProvider).watchEmployeeReports();
});

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<List<AppNotification>>.value(const []);
  }
  return ref.watch(wmsRepositoryProvider).watchNotifications(user.id);
});

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications =
      ref.watch(notificationsProvider).valueOrNull ?? const [];
  return notifications.where((notification) => !notification.isRead).length;
});

final hasPermissionProvider = Provider.family<bool, AppPermission>((
  ref,
  permission,
) {
  final user = ref.watch(currentUserProvider);
  return user?.hasPermission(permission) ?? false;
});

final availableTransitionsProvider =
    Provider.family<List<OrderStatus>, OrderEntity>((ref, order) {
      final user = ref.watch(currentUserProvider);
      if (user == null) {
        return const [];
      }
      return ref
          .watch(workflowEngineProvider)
          .availableTransitions(actor: user, current: order.status);
    });

final orderByIdProvider = Provider.family<OrderEntity?, String>((ref, id) {
  final orders = ref.watch(ordersProvider).valueOrNull ?? const [];
  for (final order in orders) {
    if (order.id == id) {
      return order;
    }
  }
  return null;
});

final orderDetailProvider =
    FutureProvider.autoDispose.family<OrderEntity?, String>((ref, id) {
      return ref.watch(wmsRepositoryProvider).getOrderById(id);
    });

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._ref, this._signIn, this._signOut)
    : super(const AsyncData(null));

  final Ref _ref;
  final SignInUseCase _signIn;
  final SignOutUseCase _signOut;

  void _resetScopedDataProviders() {
    _ref.invalidate(ordersProvider);
    _ref.invalidate(productsProvider);
    _ref.invalidate(usersProvider);
    _ref.invalidate(activityLogsProvider);
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(employeeReportsProvider);
    _ref.invalidate(notificationsProvider);
  }

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _signIn(identifier: identifier, password: password),
    );
    state = result;
    if (!result.hasError) {
      _resetScopedDataProviders();
    }
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_signOut.call);
    state = result;
    if (!result.hasError) {
      _resetScopedDataProviders();
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>(
      (ref) => AuthController(
        ref,
        ref.watch(signInUseCaseProvider),
        ref.watch(signOutUseCaseProvider),
      ),
    );

class OperationsController extends StateNotifier<AsyncValue<void>> {
  OperationsController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  AppUser _requireUser() {
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      throw StateError('No authenticated user');
    }
    return user;
  }

  Future<void> _run(Future<void> Function(AppUser user) action) async {
    final user = _requireUser();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => action(user));
  }

  void _refreshOrdersStreams({String? orderId}) {
    _ref.invalidate(ordersProvider);
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(employeeReportsProvider);
    _ref.invalidate(activityLogsProvider);
    _ref.invalidate(notificationsProvider);
    if (orderId != null && orderId.isNotEmpty) {
      _ref.invalidate(orderDetailProvider(orderId));
      _ref.invalidate(orderByIdProvider(orderId));
    }
  }

  void _refreshProductsStream() {
    _ref.invalidate(productsProvider);
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(activityLogsProvider);
    _ref.invalidate(employeeReportsProvider);
    _ref.invalidate(notificationsProvider);
  }

  void _refreshUsersStream() {
    _ref.invalidate(usersProvider);
    _ref.invalidate(activityLogsProvider);
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(employeeReportsProvider);
  }

  Future<void> createOrder({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String? notes,
    required List<OrderItem> items,
  }) async {
    return _run(
      (user) async {
        await _ref.read(createOrderUseCaseProvider)(
          actor: user,
          customerName: customerName,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          notes: notes,
          items: items,
        );
        _refreshOrdersStreams();
      },
    );
  }

  Future<void> updateOrder({
    required String orderId,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String? notes,
    required List<OrderItem> items,
  }) async {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .updateOrder(
              actor: user,
              orderId: orderId,
              customerName: customerName,
              customerPhone: customerPhone,
              customerAddress: customerAddress,
              notes: notes,
              items: items,
            );
        _refreshOrdersStreams(orderId: orderId);
      },
    );
  }

  Future<void> deleteOrder(String orderId) async {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .deleteOrder(actor: user, orderId: orderId);
        _refreshOrdersStreams(orderId: orderId);
      },
    );
  }

  Future<void> transitionOrder({
    required OrderEntity order,
    required OrderStatus nextStatus,
    String? note,
  }) async {
    return _run(
      (user) async {
        await _ref.read(transitionOrderUseCaseProvider)(
          actor: user,
          order: order,
          nextStatus: nextStatus,
          note: note,
        );
        _refreshOrdersStreams(orderId: order.id);
      },
    );
  }

  Future<void> overrideOrderStatus({
    required String orderId,
    required OrderStatus nextStatus,
    String? note,
  }) async {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .overrideOrderStatus(
              actor: user,
              orderId: orderId,
              nextStatus: nextStatus,
              note: note,
            );
        _refreshOrdersStreams(orderId: orderId);
      },
    );
  }

  Future<void> upsertProduct(ProductDraft product) async {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .upsertProduct(actor: user, product: product);
        _refreshProductsStream();
      },
    );
  }

  Future<void> deleteProduct(String productId) async {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .deleteProduct(actor: user, productId: productId);
        _refreshProductsStream();
      },
    );
  }

  Future<void> adjustInventory({
    required String productId,
    required int quantityDelta,
    required String reason,
  }) async {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .adjustInventory(
              actor: user,
              productId: productId,
              quantityDelta: quantityDelta,
              reason: reason,
            );
        _refreshProductsStream();
      },
    );
  }

  Future<void> createEmployee(EmployeeDraft employee) {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .createEmployee(actor: user, employee: employee);
        _refreshUsersStream();
      },
    );
  }

  Future<void> updateEmployee(EmployeeDraft employee) {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .updateEmployee(actor: user, employee: employee);
        _refreshUsersStream();
      },
    );
  }

  Future<void> deactivateEmployee({
    required String employeeId,
    required bool isActive,
  }) {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .deactivateEmployee(
              actor: user,
              employeeId: employeeId,
              isActive: isActive,
            );
        _refreshUsersStream();
      },
    );
  }

  Future<void> deleteEmployee(String employeeId) {
    return _run(
      (user) async {
        await _ref
            .read(wmsRepositoryProvider)
            .deleteEmployee(actor: user, employeeId: employeeId);
        _refreshUsersStream();
      },
    );
  }

  Future<void> markNotificationRead(String notificationId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async {
        await _ref
            .read(wmsRepositoryProvider)
            .markNotificationRead(notificationId);
        _ref.invalidate(notificationsProvider);
      },
    );
  }

  Future<void> markAllNotificationsRead(List<String> notificationIds) async {
    if (notificationIds.isEmpty) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async {
        for (final id in notificationIds) {
          await _ref.read(wmsRepositoryProvider).markNotificationRead(id);
        }
        _ref.invalidate(notificationsProvider);
      },
    );
  }
}

final operationsControllerProvider =
    StateNotifierProvider<OperationsController, AsyncValue<void>>(
      (ref) => OperationsController(ref),
    );
