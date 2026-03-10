import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:top_quality/core/constants/app_constants.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/errors/app_exception.dart';
import 'package:top_quality/data/datasources/remote/backend_data_source.dart';
import 'package:top_quality/data/models/remote_dtos.dart';
import 'package:top_quality/domain/entities/activity_log.dart';
import 'package:top_quality/domain/entities/app_notification.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/entities/dashboard_snapshot.dart';
import 'package:top_quality/domain/entities/employee_draft.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/domain/entities/product.dart';
import 'package:top_quality/domain/entities/product_draft.dart';

class SupabaseBackendDataSource implements BackendDataSource {
  SupabaseBackendDataSource() : _client = Supabase.instance.client;

  final SupabaseClient _client;
  static const _supportedEmployeeActions = <String>{
    'create',
    'update',
    'deactivate',
    'delete',
    'list',
  };

  @override
  Stream<AppUser?> watchSession() async* {
    yield await getCurrentUser();
    yield* _client.auth.onAuthStateChange.asyncMap((_) => getCurrentUser());
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final rpcProfile = await _fetchCurrentUserViaRpc();
    if (rpcProfile != null) {
      return rpcProfile;
    }

    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      return null;
    }

    return _fetchCurrentUserCompat(authUser.id);
  }

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    final email = await _resolveEmailForLogin(identifier);
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw AppException('Unable to sign in.');
    }

    try {
      try {
        await _executeUserLoginAndActivity(response.user!);
      } catch (error) {
        if (!_isRecordLoginConflict(error)) {
          rethrow;
        }
      }
      var profile = await getCurrentUser();
      if (profile == null) {
        try {
          await _rpcWithAuthRetry('ensure_current_user_profile');
          profile = await getCurrentUser();
        } catch (_) {
          // Fall through to the existing friendly error below.
        }
      }
      if (profile == null) {
        throw AppException(
          'The authentication account exists, but no employee profile was found in the users table.',
        );
      }
    } catch (error) {
      await _client.auth.signOut();
      throw AppException(_friendlyAuthError(error));
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Stream<List<OrderEntity>> watchOrders() => _watchComputed(
    tables: const ['orders', 'order_items', 'order_status_history'],
    fetch: _fetchOrders,
  );

  @override
  Stream<List<Product>> watchProducts() => _watchComputed(
    tables: const ['products', 'inventory'],
    fetch: _fetchProducts,
  );

  @override
  Stream<List<AppNotification>> watchNotifications(String userId) =>
      _watchComputed(
        tables: const ['notifications'],
        fetch: () => _fetchNotifications(userId),
      );

  @override
  Stream<List<AppUser>> watchUsers() => _watchComputed(
    tables: const ['users', 'user_permissions', 'roles', 'role_permissions'],
    fetch: _fetchUsers,
  );

  @override
  Stream<List<ActivityLog>> watchActivityLogs() => _watchComputed(
    tables: const ['activity_logs'],
    fetch: _fetchActivityLogs,
  );

  @override
  Stream<DashboardSnapshot> watchDashboardSnapshot() => _watchComputed(
    tables: const [
      'orders',
      'order_items',
      'order_status_history',
      'products',
      'inventory',
      'activity_logs',
    ],
    fetch: _buildDashboard,
  );

  @override
  Stream<List<EmployeeReport>> watchEmployeeReports() => _watchComputed(
    tables: const [
      'orders',
      'order_status_history',
      'users',
      'user_permissions',
    ],
    fetch: _buildReports,
  );

  @override
  Future<void> createOrder({
    required AppUser actor,
    required String customerName,
    required String customerPhone,
    required String? notes,
    required List<OrderItem> items,
  }) async {
    await _rpcWithAuthRetry(
      'create_order',
      params: {
        'p_customer_name': customerName,
        'p_customer_phone': customerPhone,
        'p_order_notes': notes,
        'p_items': items
            .map(
              (item) => {
                'product_id': item.productId,
                'quantity': item.quantity,
              },
            )
            .toList(),
      },
    );
  }

  @override
  Future<void> updateOrder({
    required AppUser actor,
    required String orderId,
    required String customerName,
    required String customerPhone,
    required String? notes,
    required List<OrderItem> items,
  }) async {
    await _rpcWithAuthRetry(
      'update_order',
      params: {
        'p_order_id': orderId,
        'p_customer_name': customerName,
        'p_customer_phone': customerPhone,
        'p_order_notes': notes,
        'p_items': items
            .map(
              (item) => {
                'product_id': item.productId,
                'quantity': item.quantity,
              },
            )
            .toList(),
      },
    );
  }

  @override
  Future<void> deleteOrder({required AppUser actor, required String orderId}) {
    return _rpcWithAuthRetry('delete_order', params: {'p_order_id': orderId});
  }

  @override
  Future<void> transitionOrder({
    required AppUser actor,
    required String orderId,
    required OrderStatus nextStatus,
    String? note,
  }) {
    return _rpcWithAuthRetry(
      'transition_order',
      params: {
        'p_order_id': orderId,
        'p_next_status': nextStatus.name,
        'p_note': note,
      },
    );
  }

  @override
  Future<void> overrideOrderStatus({
    required AppUser actor,
    required String orderId,
    required OrderStatus nextStatus,
    String? note,
  }) {
    return _rpcWithAuthRetry(
      'override_order_status',
      params: {
        'p_order_id': orderId,
        'p_next_status': nextStatus.name,
        'p_note': note,
      },
    );
  }

  @override
  Future<void> upsertProduct({
    required AppUser actor,
    required ProductDraft product,
  }) async {
    _assertProductPermission(actor, product.id == null || product.id!.isEmpty
        ? AppPermission.productsCreate
        : AppPermission.productsEdit);

    final prefixedParams = {
      'p_product_id': product.id,
      'p_name': product.name,
      'p_sku': product.sku,
      'p_category': product.category,
      'p_purchase_price': product.purchasePrice,
      'p_sale_price': product.salePrice,
      'p_stock': product.stock,
      'p_min_stock': product.minStockLevel,
    };

    try {
      await _rpcWithAuthRetry('upsert_product', params: prefixedParams);
    } on PostgrestException catch (error) {
      if (!_isRpcArgumentMismatch(error)) {
        rethrow;
      }

      await _rpcWithAuthRetry(
        'upsert_product',
        params: {
          'product_id': product.id,
          'name': product.name,
          'sku': product.sku,
          'category': product.category,
          'purchase_price': product.purchasePrice,
          'sale_price': product.salePrice,
          'stock': product.stock,
          'min_stock': product.minStockLevel,
        },
      );
    }
  }

  @override
  Future<void> deleteProduct({
    required AppUser actor,
    required String productId,
  }) {
    _assertProductPermission(actor, AppPermission.productsDelete);
    return _rpcWithAuthRetry(
      'delete_product',
      params: {'p_product_id': productId},
    );
  }

  @override
  Future<void> adjustInventory({
    required AppUser actor,
    required String productId,
    required int quantityDelta,
    required String reason,
  }) {
    _assertProductPermission(actor, AppPermission.inventoryEdit);
    return _rpcWithAuthRetry(
      'adjust_inventory',
      params: {
        'p_product_id': productId,
        'p_quantity_delta': quantityDelta,
        'p_reason': reason,
      },
    );
  }

  @override
  Future<void> createEmployee({
    required AppUser actor,
    required EmployeeDraft employee,
  }) {
    _assertAdminActor(actor);
    return _invokeEmployeeManager(action: 'create', employee: employee);
  }

  @override
  Future<void> updateEmployee({
    required AppUser actor,
    required EmployeeDraft employee,
  }) {
    _assertAdminActor(actor);
    return _invokeEmployeeManager(action: 'update', employee: employee);
  }

  @override
  Future<void> deactivateEmployee({
    required AppUser actor,
    required String employeeId,
    required bool isActive,
  }) {
    _assertAdminActor(actor);
    return _invokeEmployeeManager(
      action: 'deactivate',
      employeeId: employeeId,
      isActive: isActive,
    );
  }

  @override
  Future<void> deleteEmployee({
    required AppUser actor,
    required String employeeId,
  }) {
    _assertAdminActor(actor);
    return _invokeEmployeeManager(action: 'delete', employeeId: employeeId);
  }

  @override
  Future<void> markNotificationRead(String notificationId) {
    return _rpcWithAuthRetry(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }

  void _assertAdminActor(AppUser actor) {
    if (actor.role != UserRole.admin) {
      throw AppException('Only admin users can manage employees.');
    }
  }

  void _assertValidEmployeeAction(String action) {
    if (_supportedEmployeeActions.contains(action)) {
      return;
    }
    throw AppException(
      'Unsupported employee action "$action". Allowed: ${_supportedEmployeeActions.join(', ')}.',
    );
  }

  void _assertProductPermission(AppUser actor, AppPermission required) {
    if (!actor.hasPermission(required)) {
      throw AppException('You do not have permission to manage products.');
    }
  }

  Future<String> _resolveEmailForLogin(String identifier) async {
    if (identifier.contains('@')) {
      return identifier;
    }

    final response = await _client
        .from('users')
        .select('email')
        .ilike('username', identifier)
        .limit(1);

    if (response.isEmpty || response.first['email'] == null) {
      throw AppException('No user found for username "$identifier".');
    }
    return response.first['email'].toString();
  }

  Future<void> _invokeEmployeeManager({
    required String action,
    EmployeeDraft? employee,
    String? employeeId,
    bool? isActive,
  }) async {
    _assertValidEmployeeAction(action);
    final payload = <String, dynamic>{
      'action': action,
      'employeeId': employeeId ?? employee?.id,
      'name': employee?.name,
      'email': employee?.email,
      'password': employee?.password,
      'roleName': employee?.role.label,
      'permissions': employee?.permissions.map((item) => item.code).toList(),
      'isActive': isActive ?? employee?.isActive,
    };

    var accessToken = await _resolveAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw AppException('Your session has expired. Please sign in again.');
    }

    dynamic response;
    try {
      response = await _invokeEmployeeManagerRequest(
        accessToken: accessToken,
        payload: payload,
      );
    } on FunctionException catch (error) {
      if (error.status != 401) {
        throw AppException(_functionExceptionMessage(error));
      }

      accessToken = await _resolveAccessToken(forceRefresh: true);
      if (accessToken == null || accessToken.isEmpty) {
        throw AppException('Your session has expired. Please sign in again.');
      }

      try {
        response = await _invokeEmployeeManagerRequest(
          accessToken: accessToken,
          payload: payload,
        );
      } on FunctionException catch (retryError) {
        if (retryError.status == 401) {
          try {
            response = await _invokeEmployeeManagerRequestWithClientSession(
              payload,
            );
          } on FunctionException catch (fallbackError) {
            throw AppException(_functionExceptionMessage(fallbackError));
          }
        } else {
          throw AppException(_functionExceptionMessage(retryError));
        }
      }
    }

    final status = response?.status as int?;
    if (status == 401) {
      throw AppException(
        'Unauthorized request to employee manager. Confirm your session is active and your account has employee management permissions.',
      );
    }
    if (status == 403) {
      throw AppException(
        'Your account does not have permission to manage employees in the current company.',
      );
    }
    if (status == 500) {
      throw AppException(
        'Employee manager function is missing required Supabase environment variables.',
      );
    }

    _throwEmployeeManagerErrorIfAny(response);
  }

  Future<String?> _resolveAccessToken({bool forceRefresh = false}) async {
    final currentSession = _client.auth.currentSession;

    // Supabase Session does not expose an `isExpired` flag; we have to check the
    // numeric expiry. Refresh proactively when the token is missing, expired,
    // or within the next 90 seconds to avoid a first-call 401 from the Edge
    // Function.
    bool shouldRefresh() {
      if (forceRefresh) return true;
      final expiresAt = currentSession?.expiresAt;
      if (expiresAt == null) return true;
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return (expiresAt - nowSeconds) < 90;
    }

    final existing = currentSession?.accessToken;
    if (existing != null && existing.isNotEmpty && !shouldRefresh()) {
      return existing;
    }

    if (shouldRefresh()) {
      try {
        final refreshResponse = await _client.auth.refreshSession();
        final refreshed = refreshResponse.session?.accessToken;
        if (refreshed != null && refreshed.isNotEmpty) {
          return refreshed;
        }
      } catch (_) {
        // Ignore and fallback to in-memory session token.
      }
    }

    final fallback = _client.auth.currentSession?.accessToken;
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }

    return null;
  }

  Future<dynamic> _invokeEmployeeManagerRequest({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) {
    return _invokeEmployeeManagerWithToken(accessToken, payload);
  }

  Future<dynamic> _invokeEmployeeManagerRequestWithClientSession(
    Map<String, dynamic> payload,
  ) async {
    final accessToken = await _resolveAccessToken(forceRefresh: true);
    if (accessToken == null || accessToken.isEmpty) {
      throw AppException('Your session has expired. Please sign in again.');
    }

    return _invokeEmployeeManagerWithToken(accessToken, payload);
  }

  Future<dynamic> _invokeEmployeeManagerWithToken(
    String accessToken,
    Map<String, dynamic> payload,
  ) {
    return _client.functions.invoke(
      'admin-manage-employee',
      headers: _buildFunctionHeaders(accessToken),
      body: payload,
    );
  }

  Map<String, String> _buildFunctionHeaders(String accessToken) {
    final headers = <String, String>{'Authorization': 'Bearer $accessToken'};
    final clientKey = AppConstants.supabaseClientKey;
    if (clientKey.isNotEmpty) {
      headers['apikey'] = clientKey;
    }
    return headers;
  }

  void _throwEmployeeManagerErrorIfAny(dynamic response) {
    final status = response?.status as int? ?? 500;
    if (status < 400) {
      return;
    }

    if (status == 404) {
      throw AppException(
        'The admin-manage-employee edge function is not deployed. Deploy the function in Supabase before managing employees.',
      );
    }
    if (status == 401) {
      throw AppException(
        'Unauthorized request to employee manager. Confirm your session is active and your account has employee management permissions.',
      );
    }
    if (status == 403) {
      throw AppException(
        'Your account does not have permission to manage employees in the current company.',
      );
    }
    if (status == 500) {
      throw AppException(
        'Employee manager function is missing required Supabase environment variables.',
      );
    }

    final payload = response?.data;
    if (payload is Map<String, dynamic> && payload['error'] != null) {
      throw AppException(payload['error'].toString());
    }
    if (payload is Map && payload['error'] != null) {
      throw AppException(payload['error'].toString());
    }
    if (payload != null) {
      throw AppException(payload.toString());
    }

    throw AppException('Employee manager request failed with status $status.');
  }

  String _functionExceptionMessage(FunctionException error) {
    if (error.status == 404) {
      return 'The admin-manage-employee edge function is not deployed. Deploy the function in Supabase before managing employees.';
    }
    if (error.status == 401) {
      return 'Unauthorized request to employee manager. Confirm your session is active and your account has employee management permissions.';
    }
    if (error.status == 403) {
      return 'Your account does not have permission to manage employees in the current company.';
    }
    if (error.status == 500) {
      return 'Employee manager function is missing required Supabase environment variables.';
    }
    final details = error.details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    if (details != null) {
      return details.toString();
    }
    return error.reasonPhrase ?? error.toString();
  }

  Future<dynamic> _rpcWithAuthRetry(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    final accessToken = await _resolveAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw AppException('Your session has expired. Please sign in again.');
    }

    try {
      return await _client.rpc(functionName, params: params);
    } on PostgrestException catch (error) {
      if (_isAuthRequiredPostgrest(error)) {
        throw AppException('Authentication required. Please sign in again.');
      }
      if (!_isUnauthorizedPostgrest(error)) {
        rethrow;
      }

      final refreshedToken = await _resolveAccessToken(forceRefresh: true);
      if (refreshedToken == null || refreshedToken.isEmpty) {
        throw AppException('Your session has expired. Please sign in again.');
      }

      try {
        return await _client.rpc(functionName, params: params);
      } on PostgrestException catch (retryError) {
        if (_isUnauthorizedPostgrest(retryError)) {
          throw AppException('Your session has expired. Please sign in again.');
        }
        rethrow;
      }
    }
  }

  Future<void> _executeUserLoginAndActivity(User user) async {
    await _rpcWithAuthRetry(
      'record_user_login',
      params: {
        'p_user_id': user.id,
      },
    );

    try {
      await _recordLoginActivity(user);
    } catch (_) {
      // Audit logging must not block a valid login session.
    }
  }

  Future<void> _recordLoginActivity(User user) async {
    await _rpcWithAuthRetry(
      'write_activity_log',
      params: {
        'p_actor_id': user.id,
        'p_action': 'Login',
        'p_entity_type': 'User',
        'p_entity_id': user.id,
        'p_metadata': <String, dynamic>{},
      },
    );
  }

  Stream<T> _watchComputed<T>({
    required List<String> tables,
    required Future<T> Function() fetch,
  }) {
    late StreamController<T> controller;
    final channels = <RealtimeChannel>[];

    Future<void> emit() async {
      if (controller.isClosed) {
        return;
      }
      try {
        controller.add(await fetch());
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<T>.broadcast(
      onListen: () async {
        await emit();
        for (final table in tables) {
          final channel = _client
              .channel('watch:$table:${DateTime.now().microsecondsSinceEpoch}')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: table,
                callback: (_) async => emit(),
              )
              .subscribe();
          channels.add(channel);
        }
      },
      onCancel: () async {
        for (final channel in channels) {
          await channel.unsubscribe();
        }
      },
    );

    return controller.stream;
  }

  Future<List<AppUser>> _fetchUsers() async {
    return _fetchUsersCompat();
  }

  Future<List<Product>> _fetchProducts() async {
    try {
      final response = await _client.from('v_products').select().order('name');

      return response
          .map((row) => RemoteMapper.product(Map<String, dynamic>.from(row)))
          .toList();
    } catch (_) {
      return _fetchProductsCompat();
    }
  }

  Future<List<OrderEntity>> _fetchOrders() async {
    try {
      final response = await _client
          .from('orders')
          .select(
            'id, customer_name, customer_phone, order_date, order_notes, status, '
            'created_by, created_by_name, '
            'order_items(id, product_id, product_name, quantity, purchase_price, sale_price, profit), '
            'order_status_history(id, status, changed_by, changed_by_name, changed_at, note)',
          )
          .order('order_date', ascending: false);

      return response
          .map((row) => RemoteMapper.order(Map<String, dynamic>.from(row)))
          .toList();
    } catch (_) {
      return _fetchOrdersCompat();
    }
  }

  Future<List<AppNotification>> _fetchNotifications(String userId) async {
    final response = await _client
        .from('notifications')
        .select(
          'id, user_id, title, message, type, read, created_at, reference_id',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response
        .map((row) => RemoteMapper.notification(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<ActivityLog>> _fetchActivityLogs() async {
    final response = await _client
        .from('activity_logs')
        .select(
          'id, actor_id, action, entity_type, entity_id, metadata, company_id, created_at',
        )
        .order('created_at', ascending: false)
        .limit(40);

    final rows = response.map((row) => Map<String, dynamic>.from(row)).toList();
    if (rows.isEmpty) {
      return const [];
    }

    final actorIds = rows
        .map((row) => row['actor_id']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final usersResponse = actorIds.isEmpty
        ? const []
        : await _client
              .from('users')
              .select('id, name')
              .inFilter('id', actorIds);

    final actorNamesById = <String, String>{
      for (final item in usersResponse)
        item['id'].toString(): item['name']?.toString() ?? 'Unknown User',
    };

    return rows
        .map(
          (row) => RemoteMapper.activityLog({
            ...row,
            'actor_name':
                actorNamesById[row['actor_id']?.toString() ?? ''] ??
                'Unknown User',
          }),
        )
        .toList();
  }

  Future<DashboardSnapshot> _buildDashboard() async {
    final orders = await _fetchOrders();
    final products = await _fetchProducts();
    final activityLogs = await _safeFetch(
      _fetchActivityLogs,
      const <ActivityLog>[],
    );

    final ordersByStatus = {
      for (final status in OrderStatus.values)
        status: orders.where((order) => order.status == status).length,
    };

    final realizedOrders = orders.where(
      (order) =>
          order.status == OrderStatus.shipped ||
          order.status == OrderStatus.completed,
    );

    final groupedActivity = <String, UserActivitySummary>{};
    for (final log in activityLogs) {
      final current = groupedActivity[log.actorId];
      if (current == null) {
        groupedActivity[log.actorId] = UserActivitySummary(
          userName: log.actorName,
          role: UserRole.orderEntry,
          totalActions: 1,
        );
      } else {
        groupedActivity[log.actorId] = UserActivitySummary(
          userName: current.userName,
          role: current.role,
          totalActions: current.totalActions + 1,
        );
      }
    }

    return DashboardSnapshot(
      totalOrders: orders.length,
      ordersByStatus: ordersByStatus,
      revenue: realizedOrders.fold<double>(
        0,
        (sum, order) => sum + order.totalRevenue,
      ),
      profit: realizedOrders.fold<double>(
        0,
        (sum, order) => sum + order.profit,
      ),
      inventoryValue: products.fold<double>(
        0,
        (sum, product) => sum + product.currentStock * product.purchasePrice,
      ),
      lowStockAlerts: products.where((product) => product.isLowStock).length,
      recentOrders: orders.take(6).toList(),
      userActivity: groupedActivity.values.toList()
        ..sort((a, b) => b.totalActions.compareTo(a.totalActions)),
    );
  }

  Future<List<EmployeeReport>> _buildReports() async {
    final users = await _fetchUsers();
    final orders = await _fetchOrders();

    return users.map((user) {
      final createdOrders = orders
          .where((order) => order.createdBy == user.id)
          .toList();
      final reviewedOrderIds = <String>{};
      final shippedOrderIds = <String>{};
      final returnedOrderIds = <String>{};

      for (final order in orders) {
        for (final history in order.history) {
          if (history.changedBy != user.id) {
            continue;
          }
          if (history.status == OrderStatus.checked ||
              history.status == OrderStatus.approved) {
            reviewedOrderIds.add(order.id);
          }
          if (history.status == OrderStatus.shipped ||
              history.status == OrderStatus.completed) {
            shippedOrderIds.add(order.id);
          }
          if (history.status == OrderStatus.returned) {
            returnedOrderIds.add(order.id);
          }
        }
      }

      return EmployeeReport(
        userId: user.id,
        userName: user.name,
        role: user.role,
        ordersEntered: createdOrders.length,
        ordersReviewed: reviewedOrderIds.length,
        ordersShipped: shippedOrderIds.length,
        ordersReturned: returnedOrderIds.length,
      );
    }).toList()..sort((a, b) => a.userName.compareTo(b.userName));
  }

  Future<T> _safeFetch<T>(Future<T> Function() fetch, T fallback) async {
    try {
      return await fetch();
    } catch (_) {
      return fallback;
    }
  }

  String _friendlyAuthError(Object error) {
    final message = error.toString();
    if (message.contains('record_user_login')) {
      return 'Supabase migration is incomplete. Apply the SQL schema so record_user_login(p_user_id) is available.';
    }
    if (message.contains('no employee profile')) {
      return 'Signed-in user has no employee profile. Insert the user into public.users with an assigned role.';
    }
    return message;
  }

  bool _isRecordLoginConflict(Object error) {
    final message = error.toString().toLowerCase();
    final isRecordLoginError = message.contains('record_user_login');
    final isConflict =
        message.contains('409') ||
        message.contains('conflict') ||
        message.contains('duplicate key') ||
        message.contains('23505') ||
        message.contains('23503');
    return isRecordLoginError && isConflict;
  }

  bool _isUnauthorizedPostgrest(PostgrestException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();

    return code == 'pgrst301' ||
        code == '401' ||
        message.contains('jwt expired') ||
        message.contains('invalid jwt') ||
        message.contains('unauthorized') ||
        details.contains('jwt') ||
        hint.contains('jwt');
  }

  bool _isAuthRequiredPostgrest(PostgrestException error) {
    final message = error.message.toLowerCase();
    return message.contains('authentication required');
  }

  bool _isRpcArgumentMismatch(PostgrestException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();

    return code == 'pgrst202' ||
        code == 'pgrst204' ||
        message.contains('function public.upsert_product') ||
        message.contains('function public.write_activity_log') ||
        message.contains('could not find the function') ||
        message.contains('argument') ||
        message.contains('parameter') ||
        message.contains('invalid input syntax') ||
        details.contains('function') ||
        details.contains('parameter') ||
        hint.contains('parameter');
  }

  Future<AppUser?> _fetchCurrentUserCompat(String userId) async {
    final users = await _fetchUsersCompat(userId: userId);
    if (users.isEmpty) {
      return null;
    }
    return users.first;
  }

  Future<AppUser?> _fetchCurrentUserViaRpc() async {
    try {
      final response = await _rpcWithAuthRetry('get_current_user_profile');
      if (response == null) {
        return null;
      }
      if (response is Map) {
        final payload = Map<String, dynamic>.from(response);
        final roleName = payload['role_name']?.toString().trim() ?? '';
        final permissions = payload['permissions'];
        if (permissions is List) {
          payload['permissions'] = {
            for (final item in permissions)
              ..._expandPermissionAliases(item.toString()),
          }.toList();
        }

        final user = RemoteMapper.appUser(payload);
        if (roleName.isEmpty && (payload['role_id']?.toString().isNotEmpty ?? false)) {
          return null;
        }
        if (user.role != UserRole.admin && user.permissions.isEmpty) {
          return null;
        }
        return user;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<AppUser>> _fetchUsersCompat({String? userId}) async {
    final usersQuery = _client
        .from('users')
        .select(
          'id, name, email, username, role_id, is_active, created_at, updated_at, last_active',
        );
    if (userId != null) {
      usersQuery.eq('id', userId);
    }
    final usersResponse = await usersQuery.order(
      'created_at',
      ascending: false,
    );

    final userRows = usersResponse
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (userRows.isEmpty) {
      return const [];
    }

    final roleIds = userRows
        .map((row) => row['role_id']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final userIds = userRows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();

    final rolesResponse = roleIds.isEmpty
        ? const []
        : await _client.from('roles').select().inFilter('id', roleIds);

    final rolePermissionsResponse = roleIds.isEmpty
        ? const []
        : await _client
              .from('role_permissions')
              .select()
              .inFilter('role_id', roleIds);

    final permissionsCatalogResponse = await _client
        .from('permissions')
        .select();

    final permissionsResponse = await _client
        .from('user_permissions')
        .select()
        .inFilter('user_id', userIds);

    final roleNamesById = <String, String>{
      for (final role in rolesResponse)
        role['id'].toString(): _resolveRoleName(
          Map<String, dynamic>.from(role),
        ),
    };

    final permissionCodeById = <String, String>{};
    for (final permission in permissionsCatalogResponse) {
      final row = Map<String, dynamic>.from(permission);
      final permissionId = _resolvePermissionId(row);
      final permissionCode = _resolvePermissionCode(
        row,
        const <String, String>{},
      );
      if (permissionId == null || permissionId.isEmpty) {
        continue;
      }
      if (permissionCode == null || permissionCode.isEmpty) {
        continue;
      }
      permissionCodeById[permissionId] = permissionCode;
    }

    final permissionsByUserId = <String, List<String>>{};
    for (final item in permissionsResponse) {
      final row = Map<String, dynamic>.from(item);
      final id = row['user_id']?.toString();
      final permissionCode = _resolvePermissionCode(row, permissionCodeById);
      if (id == null ||
          id.isEmpty ||
          permissionCode == null ||
          permissionCode.isEmpty) {
        continue;
      }
      permissionsByUserId
          .putIfAbsent(id, () => <String>[])
          .addAll(_expandPermissionAliases(permissionCode));
    }

    final permissionsByRoleId = <String, List<String>>{};
    for (final item in rolePermissionsResponse) {
      final row = Map<String, dynamic>.from(item);
      final roleId = row['role_id']?.toString();
      final permissionCode = _resolvePermissionCode(row, permissionCodeById);
      if (roleId == null ||
          roleId.isEmpty ||
          permissionCode == null ||
          permissionCode.isEmpty) {
        continue;
      }
      permissionsByRoleId
          .putIfAbsent(roleId, () => <String>[])
          .addAll(_expandPermissionAliases(permissionCode));
    }

    return userRows.map((row) {
      final id = row['id']?.toString() ?? '';
      final roleId = row['role_id']?.toString() ?? '';
      final roleName = roleNamesById[roleId] ?? '';
      final effectivePermissions = {
        ...?permissionsByRoleId[roleId],
        ...?permissionsByUserId[id],
      }.toList();

      return RemoteMapper.appUser({
        ...row,
        'role_name': roleName,
        'permissions': effectivePermissions,
      });
    }).toList();
  }

  String _resolveRoleName(Map<String, dynamic> row) {
    for (final key in const ['role_name', 'name', 'title', 'label']) {
      final value = row[key]?.toString();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String? _resolvePermissionId(Map<String, dynamic> row) {
    for (final key in const ['id', 'permission_id']) {
      final value = row[key]?.toString();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _resolvePermissionCode(
    Map<String, dynamic> row,
    Map<String, String> permissionCodeById,
  ) {
    for (final key in const ['permission_code', 'code', 'name']) {
      final value = row[key]?.toString();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    final permissionId = _resolvePermissionId(row);
    if (permissionId == null || permissionId.isEmpty) {
      return null;
    }
    return permissionCodeById[permissionId];
  }

  List<String> _expandPermissionAliases(String permissionCode) {
    switch (permissionCode) {
      case 'read':
        return const [
          'read',
          'dashboard_view',
          'notifications_view',
          'orders_view',
          'inventory_view',
          'products_view',
          'reports_view',
          'users_view',
        ];
      case 'write':
        return const [
          'write',
          'orders_create',
          'orders_edit',
          'inventory_edit',
          'products_create',
          'products_edit',
        ];
      case 'delete':
        return const [
          'delete',
          'orders_delete',
          'products_delete',
          'users_delete',
        ];
      case 'manage_users':
        return const [
          'manage_users',
          'users_view',
          'users_create',
          'users_edit',
          'users_delete',
          'users_assign_permissions',
        ];
      case 'manage_inventory':
        return const [
          'manage_inventory',
          'inventory_view',
          'inventory_edit',
          'products_view',
          'products_create',
          'products_edit',
          'products_delete',
        ];
      case 'orders_read':
        return const ['orders_read', 'orders_view'];
      case 'orders_write':
        return const ['orders_write', 'orders_view', 'orders_create', 'orders_edit'];
      case 'inventory_read':
        return const ['inventory_read', 'inventory_view', 'products_view'];
      case 'inventory_write':
        return const [
          'inventory_write',
          'inventory_view',
          'inventory_edit',
          'products_view',
          'products_edit',
        ];
      default:
        return [permissionCode];
    }
  }

  Future<List<Product>> _fetchProductsCompat() async {
    final productsResponse = await _client
        .from('products')
        .select(
          'id, name, sku, category, purchase_price, sale_price, is_active',
        )
        .eq('is_active', true)
        .order('name');

    final productRows = productsResponse
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (productRows.isEmpty) {
      return const [];
    }

    final productIds = productRows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();

    final inventoryResponse = await _client
        .from('inventory')
        .select('product_id, stock, min_stock')
        .inFilter('product_id', productIds);

    final inventoryByProductId = <String, Map<String, dynamic>>{
      for (final item in inventoryResponse)
        item['product_id'].toString(): Map<String, dynamic>.from(item),
    };

    return productRows.map((row) {
      final productId = row['id']?.toString() ?? '';
      return RemoteMapper.product({
        ...row,
        ...?inventoryByProductId[productId],
      });
    }).toList();
  }

  Future<List<OrderEntity>> _fetchOrdersCompat() async {
    final ordersResponse = await _client
        .from('orders')
        .select(
          'id, customer_name, customer_phone, order_date, order_notes, status, '
          'created_by, created_by_name',
        )
        .order('order_date', ascending: false);

    final orderRows = ordersResponse
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (orderRows.isEmpty) {
      return const [];
    }

    final orderIds = orderRows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();

    final itemsResponse = await _client
        .from('order_items')
        .select(
          'id, order_id, product_id, product_name, quantity, purchase_price, sale_price, profit',
        )
        .inFilter('order_id', orderIds);

    final historyResponse = await _client
        .from('order_status_history')
        .select(
          'id, order_id, status, changed_by, changed_by_name, changed_at, note',
        )
        .inFilter('order_id', orderIds);

    final itemsByOrderId = <String, List<Map<String, dynamic>>>{};
    for (final item in itemsResponse) {
      final row = Map<String, dynamic>.from(item);
      final orderId = row['order_id']?.toString();
      if (orderId == null || orderId.isEmpty) {
        continue;
      }
      itemsByOrderId
          .putIfAbsent(orderId, () => <Map<String, dynamic>>[])
          .add(row);
    }

    final historyByOrderId = <String, List<Map<String, dynamic>>>{};
    for (final item in historyResponse) {
      final row = Map<String, dynamic>.from(item);
      final orderId = row['order_id']?.toString();
      if (orderId == null || orderId.isEmpty) {
        continue;
      }
      historyByOrderId
          .putIfAbsent(orderId, () => <Map<String, dynamic>>[])
          .add(row);
    }

    return orderRows.map((row) {
      final orderId = row['id']?.toString() ?? '';
      return RemoteMapper.order({
        ...row,
        'order_items':
            itemsByOrderId[orderId] ?? const <Map<String, dynamic>>[],
        'order_status_history':
            historyByOrderId[orderId] ?? const <Map<String, dynamic>>[],
      });
    }).toList();
  }
}
