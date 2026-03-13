import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/constants/app_constants.dart';
import 'package:top_quality/core/errors/app_exception.dart';
import 'package:top_quality/data/datasources/remote/backend_data_source.dart';
import 'package:top_quality/domain/entities/activity_log.dart';
import 'package:top_quality/domain/entities/app_notification.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/entities/dashboard_snapshot.dart';
import 'package:top_quality/domain/entities/employee_draft.dart';
import 'package:top_quality/domain/entities/order.dart';
import 'package:top_quality/domain/entities/product.dart';
import 'package:top_quality/domain/entities/product_draft.dart';
import 'package:top_quality/data/models/remote_dtos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:top_quality/data/datasources/remote/_report_acc.dart';

class _UserAcc {
  _UserAcc({
    required this.id,
    required this.name,
    required this.email,
    required this.companyId,
    required this.companyName,
    required this.roleName,
    required this.isHardAdmin,
    required this.isActive,
    required this.lastActive,
  });

  final String id;
  final String name;
  final String email;
  final String? companyId;
  final String? companyName;
  final String roleName;
  final bool isHardAdmin;
  final bool isActive;
  final DateTime? lastActive;
  final Set<String> permissionCodes = {};

  AppUser toAppUser(Set<AppPermission> Function(String) fallback) {
    final resolved = permissionCodes
        .map(AppPermission.fromCode)
        .whereType<AppPermission>()
        .toSet();
    final base = fallback(roleName);
    final perms = isHardAdmin
        ? AppPermission.values.toSet()
        : (resolved.isEmpty ? base : base.union(resolved));
    return AppUser(
      id: id,
      name: name,
      email: email,
      companyId: companyId,
      companyName: companyName,
      roleId: '',
      role: isHardAdmin ? UserRole.admin : UserRole.fromRoleName(roleName),
      permissions: perms,
      createdAt: DateTime.now(),
      isActive: isActive,
      lastActive: lastActive,
    );
  }
}

class FirebaseBackendDataSource implements BackendDataSource {
  FirebaseBackendDataSource() : _supabase = Supabase.instance.client;

  final SupabaseClient _supabase;
  final Map<String, Future<AppUser>> _profileCache = {};

  bool _isHardAdmin(String email) =>
      email.trim().toLowerCase() == 'markode@gmail.com';

  AppUser _mapUserFromProfile(Map res, User fallback) {
    final permList = (res['permissions'] as List?)?.cast<String>() ?? [];
    final roleName = (res['role_name'] ?? '').toString();
    final email = res['email']?.toString() ?? (fallback.email ?? '');
    final companyId = res['company_id']?.toString();
    final companyName = res['company_name']?.toString();
    final resolvedPerms = permList
        .map(AppPermission.fromCode)
        .whereType<AppPermission>()
        .toSet();
    final basePerms = _defaultPermissionsForRole(roleName);
    final perms = resolvedPerms.isEmpty
        ? basePerms
        : basePerms.union(resolvedPerms);
    final isAdminOverride = _isHardAdmin(email);
    return AppUser(
      id: res['id']?.toString() ?? fallback.id,
      name:
          res['name']?.toString() ??
          fallback.userMetadata?['name']?.toString() ??
          (fallback.email ?? 'User'),
      email: email,
      companyId: companyId,
      companyName: companyName,
      roleId: res['role_id']?.toString() ?? 'supabase-default',
      role: isAdminOverride ? UserRole.admin : UserRole.fromRoleName(roleName),
      permissions: isAdminOverride ? AppPermission.values.toSet() : perms,
      createdAt:
          DateTime.tryParse(res['created_at']?.toString() ?? '') ??
          DateTime.tryParse(fallback.createdAt) ??
          DateTime.now(),
      isActive: res['is_active'] as bool? ?? true,
      lastActive:
          DateTime.tryParse(res['last_active']?.toString() ?? '') ??
          (fallback.lastSignInAt == null
              ? null
              : DateTime.tryParse(fallback.lastSignInAt!)),
    );
  }

  Future<Map<String, dynamic>?> _loadCompanyFromUsersView(String userId) async {
    // v_users_with_permissions can return multiple rows per user (one per permission_code),
    // so we LIMIT 1 to allow maybeSingle().
    return _supabase
        .from('v_users_with_permissions')
        .select('company_id, company_name')
        .eq('id', userId)
        .limit(1)
        .maybeSingle();
  }

  Future<List<String>> _loadPermissionCodesFromUsersView(String userId) async {
    final List<dynamic> rows = await _supabase
        .from('v_users_with_permissions')
        .select('permission_code')
        .eq('id', userId);
    return rows
        .map((e) => (e as Map)['permission_code']?.toString())
        .whereType<String>()
        .where((c) => c.isNotEmpty && c != 'none')
        .toSet()
        .toList();
  }

  Future<AppUser> _loadProfile(User user) async {
    // memoize per user to avoid repeated RPC calls during rebuilds
    final cached = _profileCache[user.id];
    if (cached != null) return cached;

    final future = _fetchProfile(user);
    _profileCache[user.id] = future;
    try {
      return await future;
    } finally {
      // keep cache entry; no removal needed unless you want explicit invalidation on signOut
    }
  }

  Future<AppUser> _fetchProfile(User user) async {
    Map? rpcRes;
    try {
      rpcRes = await _supabase.rpc('get_current_user_profile');
    } catch (_) {
      // ignore and fallback to manual path
    }

    if (rpcRes is Map && rpcRes.isNotEmpty) {
      // If RPC returned but without permissions, enrich from relational tables.
      if ((rpcRes['permissions'] as List?)?.isEmpty ?? true) {
        final enrichedCodes = await _loadPermissionCodesFromUsersView(user.id);
        rpcRes = Map.of(rpcRes)..['permissions'] = enrichedCodes;
      }
      // Ensure company info exists for UI (employees table / edit dialog).
      if (rpcRes['company_id'] == null || rpcRes['company_name'] == null) {
        final companyRow = await _loadCompanyFromUsersView(user.id);
        rpcRes = Map.of(rpcRes)
          ..['company_id'] = companyRow?['company_id']
          ..['company_name'] = companyRow?['company_name'];
      }
      return _mapUserFromProfile(rpcRes, user);
    }

    // Manual fallback path: use the public view (no direct table access/embeds).
    final List<dynamic> viewRows = await _supabase
        .from('v_users_with_permissions')
        .select(
          'id, email, name, is_active, last_active, company_id, company_name, role_name, permission_code',
        )
        .eq('id', user.id);

    final List<Map<String, dynamic>> typedRows =
        viewRows.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final profileRow = typedRows.isEmpty ? null : typedRows.first;
    final roleName = profileRow?['role_name']?.toString() ?? 'Order Entry User';
    final perms =
        typedRows
            .map((r) => r['permission_code']?.toString())
            .whereType<String>()
            .where((c) => c.isNotEmpty && c != 'none')
            .map(AppPermission.fromCode)
            .whereType<AppPermission>()
            .toSet();

    final DateTime? parsedCreatedAt = DateTime.tryParse(
      user.createdAt,
    );
    final lastActiveValue = profileRow?['last_active'];
    final DateTime? parsedLastActive = lastActiveValue != null
        ? DateTime.tryParse(lastActiveValue.toString())
        : (user.lastSignInAt == null
              ? null
              : DateTime.tryParse(user.lastSignInAt!));

    final email = profileRow?['email']?.toString() ?? (user.email ?? '');
    final isAdminOverride = _isHardAdmin(email);

    final basePerms = _defaultPermissionsForRole(roleName);
    final mergedPerms = isAdminOverride
        ? AppPermission.values.toSet()
        : basePerms.union(perms);

    return AppUser(
      id: user.id,
      name:
          profileRow?['name']?.toString() ??
          user.userMetadata?['name']?.toString() ??
          (user.email ?? 'User'),
      email: email,
      companyId: profileRow?['company_id']?.toString(),
      companyName: profileRow?['company_name']?.toString(),
      roleId: 'supabase-default',
      role: isAdminOverride ? UserRole.admin : UserRole.fromRoleName(roleName),
      permissions: mergedPerms.isEmpty
          ? _defaultPermissionsForRole(roleName)
          : mergedPerms,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      isActive: profileRow?['is_active'] as bool? ?? true,
      lastActive: parsedLastActive,
    );
  }

  @override
  Stream<AppUser?> watchSession() =>
      _supabase.auth.onAuthStateChange.asyncMap((data) async {
        final session = data.session;
        final user = session?.user;
        if (user == null) return null;
        return _loadProfile(user);
      });

  @override
  Future<AppUser?> getCurrentUser() async {
    final user = _supabase.auth.currentUser;
    return user == null ? null : _loadProfile(user);
  }

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: await _resolveEmail(identifier),
        password: password,
      );
      if (res.session == null || res.user == null) {
        throw AppException('auth_invalid_credentials');
      }
    } on AuthException catch (e) {
      throw AppException(_mapAuthError(e));
    }
  }

  @override
  Future<void> signOut() => _supabase.auth.signOut();

  // ----- Streams -----
  @override
  Stream<List<OrderEntity>> watchOrders() => _supabase
      .from('orders')
      .stream(primaryKey: const ['id'])
      .order('created_at', ascending: false)
      .asyncMap((rows) async {
        if (rows.isEmpty) return <OrderEntity>[];

        final orderIds = rows
            .map((row) => row['id']?.toString())
            .whereType<String>()
            .toList();

        final itemsRes = await _supabase
            .from('order_items')
            .select(
              'order_id, product_id, product_name, quantity, purchase_price, sale_price',
            )
            .inFilter('order_id', orderIds);

        final historyRes = await _supabase
            .from('order_status_history')
            .select(
              'order_id, status, changed_by, changed_by_name, changed_at, note',
            )
            .inFilter('order_id', orderIds);

        final itemsByOrder = <String, List<Map<String, dynamic>>>{};
        for (final row in (itemsRes as List<dynamic>)) {
          final map = Map<String, dynamic>.from(row as Map);
          final oid = map['order_id']?.toString();
          if (oid == null) continue;
          itemsByOrder.putIfAbsent(oid, () => []).add(map);
        }

        final historyByOrder = <String, List<Map<String, dynamic>>>{};
        for (final row in (historyRes as List<dynamic>)) {
          final map = Map<String, dynamic>.from(row as Map);
          final oid = map['order_id']?.toString();
          if (oid == null) continue;
          historyByOrder.putIfAbsent(oid, () => []).add(map);
        }

        return rows.map((row) {
          final map = Map<String, dynamic>.from(row);
          map['order_date'] = row['created_at'];
          map['order_items'] =
              itemsByOrder[map['id']?.toString()] ?? const <Map<String, dynamic>>[];
          map['order_status_history'] =
              historyByOrder[map['id']?.toString()] ??
              const <Map<String, dynamic>>[];
          return RemoteMapper.order(map);
        }).toList();
      });

  @override
  Stream<List<Product>> watchProducts() => _supabase
      .from('products')
      .stream(primaryKey: ['id'])
      .map((rows) => rows.map(_mapProductRow).toList());

  @override
  Stream<List<AppNotification>> watchNotifications(String userId) =>
      _supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .map(
            (rows) => rows
                .map((row) => RemoteMapper.notification(row))
                .toList(),
          );

  @override
  Stream<List<AppUser>> watchUsers() {
    // Stream aggregated permissions from view v_users_with_permissions
    final stream = _supabase
        .from('v_users_with_permissions')
        .stream(primaryKey: ['id', 'permission_code']);

    return stream.map((rows) {
        final Map<String, _UserAcc> acc = {};
      for (final row in rows) {
        final id = row['id'].toString();
        final entry = acc.putIfAbsent(id, () {
          final roleName = (row['role_name'] ?? '').toString();
          final email = row['email']?.toString() ?? '';
          final companyId = row['company_id']?.toString();
          final companyName = row['company_name']?.toString();
          return _UserAcc(
            id: id,
            name: row['name']?.toString() ?? 'User',
            email: email,
            companyId: companyId,
            companyName: companyName,
            roleName: roleName,
            isHardAdmin: _isHardAdmin(email),
            isActive: row['is_active'] as bool? ?? true,
            lastActive: DateTime.tryParse(row['last_active']?.toString() ?? ''),
          );
        });
        final permCode = row['permission_code']?.toString();
        if (permCode != null && permCode.isNotEmpty) {
          entry.permissionCodes.add(permCode);
        }
      }
      // ensure hard-admin gets all permissions even if view rows are limited
      for (final entry in acc.values) {
        if (entry.isHardAdmin) {
          entry.permissionCodes.addAll(AppPermission.values.map((e) => e.code));
        }
      }
      return acc.values
          .map((e) => e.toAppUser(_defaultPermissionsForRole))
          .toList();
    });
  }

  Set<AppPermission> _defaultPermissionsForRole(String roleName) {
    final role = UserRole.fromRoleName(roleName);
    switch (role) {
      case UserRole.admin:
        return AppPermission.values.toSet();
      case UserRole.reviewer:
        return {
          AppPermission.dashboardView,
          AppPermission.usersView,
          AppPermission.productsView,
          AppPermission.inventoryView,
          AppPermission.ordersView,
          AppPermission.reportsView,
          AppPermission.activityLogsView,
        };
      case UserRole.orderEntry:
        return {
          AppPermission.dashboardView,
          AppPermission.usersView,
          AppPermission.productsView,
          AppPermission.inventoryView,
          AppPermission.ordersView,
        };
      case UserRole.shipping:
        return {
          AppPermission.dashboardView,
          AppPermission.usersView,
          AppPermission.productsView,
        };
    }
  }

  @override
  Stream<List<ActivityLog>> watchActivityLogs() => _supabase
      .from('v_activity_logs')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(_mapActivityRow).toList());

  @override
  Stream<DashboardSnapshot> watchDashboardSnapshot() => _supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .asyncMap((orderRows) async {
        // fetch related items and stock snapshot
        final itemsRes = await _supabase
            .from('order_items')
            .select(
              'order_id, quantity, purchase_price, sale_price, product_name',
            );
        final productsRes = await _supabase
            .from('products')
            .select('current_stock, min_stock_level');

        final itemRows = (itemsRes as List).cast<Map>();
        final productRows = (productsRes as List).cast<Map>();

        final total = orderRows.length;
        final Map<OrderStatus, int> byStatus = {
          for (final s in OrderStatus.values) s: 0,
        };

        // aggregate revenue/profit and items per order
        double revenue = 0;
        double profit = 0;
        final Map<String, List<OrderItem>> itemsByOrder = {};
        for (final row in itemRows) {
          final orderId = row['order_id']?.toString();
          if (orderId == null) continue;
          final qty = row['quantity'] as int? ?? 0;
          final purchase = (row['purchase_price'] as num?)?.toDouble() ?? 0;
          final sale = (row['sale_price'] as num?)?.toDouble() ?? 0;
          revenue += sale * qty;
          profit += (sale - purchase) * qty;
          itemsByOrder
              .putIfAbsent(orderId, () => [])
              .add(
                OrderItem(
                  productId: '', // not selected in query
                  productName: row['product_name']?.toString() ?? '',
                  quantity: qty,
                  purchasePrice: purchase,
                  salePrice: sale,
                ),
              );
        }

        for (final r in orderRows) {
          final statusName = (r['status']?.toString() ?? 'entered')
              .toLowerCase();
          final status = OrderStatus.values.firstWhere(
            (s) => s.name == statusName,
            orElse: () => OrderStatus.entered,
          );
          byStatus[status] = (byStatus[status] ?? 0) + 1;
        }

        final lowStockAlerts = productRows
            .where(
              (p) =>
                  (p['current_stock'] as int? ?? 0) <=
                  (p['min_stock_level'] as int? ?? 0),
            )
            .length;

        final recent = orderRows.take(5).map((r) {
          final order = _mapOrderRow(r);
          final withItems = order.copyWith(
            items: itemsByOrder[order.id] ?? const [],
          );
          return withItems;
        }).toList();

        return DashboardSnapshot(
          totalOrders: total,
          ordersByStatus: byStatus,
          revenue: revenue,
          profit: profit,
          inventoryValue: 0,
          lowStockAlerts: lowStockAlerts,
          recentOrders: recent,
          userActivity: const [],
        );
      });

  @override
  Stream<List<EmployeeReport>> watchEmployeeReports() =>
      _supabase
          .from('order_status_history')
          .stream(primaryKey: ['id'])
          .map((rows) {
            final Map<String, ReportAcc> acc = {};
            for (final r in rows) {
              final userId = r['changed_by']?.toString();
              final orderId = r['order_id']?.toString();
              if (userId == null || userId.isEmpty) continue;
              if (orderId == null || orderId.isEmpty) continue;
              final name = r['changed_by_name']?.toString() ?? 'Unknown';
              final status = (r['status']?.toString() ?? '').toLowerCase();
              final entry = acc.putIfAbsent(
                userId,
                () => ReportAcc(id: userId, name: name),
              );
              switch (status) {
                case 'entered':
                  entry.enteredOrderIds.add(orderId);
                  break;
                case 'checked':
                case 'approved':
                  entry.reviewedOrderIds.add(orderId);
                  break;
                case 'shipped':
                  entry.shippedOrderIds.add(orderId);
                  break;
                case 'completed':
                  entry.completedOrderIds.add(orderId);
                  break;
                case 'returned':
                  entry.returnedOrderIds.add(orderId);
                  break;
                default:
                  break;
              }
            }
            final list = acc.values.map((e) => e.toReport()).toList();
            list.sort((a, b) => a.userName.compareTo(b.userName));
            return list;
          });

  // ----- Orders -----
  @override
  Future<void> createOrder({
    required AppUser actor,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String? notes,
    required List<OrderItem> items,
  }) => _ensureCurrentUserProfile().then(
    (_) => _callRpc('create_order', {
      'p_customer_name': customerName,
      'p_customer_phone': customerPhone,
      'p_customer_address': customerAddress,
      'p_items': items
          .map(
            (i) => {
              'product_id': i.productId,
              'product_name': i.productName,
              'quantity': i.quantity,
              'purchase_price': i.purchasePrice,
              'sale_price': i.salePrice,
            },
          )
          .toList(),
      'p_order_notes': notes,
    }, failMessage: 'order_op_failed'),
  );

  @override
  Future<void> updateOrder({
    required AppUser actor,
    required String orderId,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String? notes,
    required List<OrderItem> items,
  }) => _ensureCurrentUserProfile().then(
    (_) => _callRpc('update_order', {
      'p_order_id': orderId,
      'p_customer_name': customerName,
      'p_customer_phone': customerPhone,
      'p_items': items
          .map(
            (i) => {
              'product_id': i.productId,
              'product_name': i.productName,
              'quantity': i.quantity,
              'purchase_price': i.purchasePrice,
              'sale_price': i.salePrice,
            },
          )
          .toList(),
      'p_order_notes': notes,
      'p_customer_address': customerAddress,
    }, failMessage: 'order_update_failed'),
  );

  @override
  Future<void> deleteOrder({required AppUser actor, required String orderId}) =>
      _callRpc('delete_order', {
        'p_order_id': orderId,
      }, failMessage: 'order_delete_failed');

  @override
  Future<void> transitionOrder({
    required AppUser actor,
    required String orderId,
    required OrderStatus nextStatus,
    String? note,
  }) => _ensureCurrentUserProfile().then(
    (_) => _callRpc('transition_order', {
      'p_order_id': orderId,
      'p_next_status': nextStatus.name,
      'p_note': note,
    }, failMessage: 'order_status_failed'),
  );

  @override
  Future<void> overrideOrderStatus({
    required AppUser actor,
    required String orderId,
    required OrderStatus nextStatus,
    String? note,
  }) => _ensureCurrentUserProfile().then(
    (_) => _callRpc('override_order_status', {
      'p_order_id': orderId,
      'p_next_status': nextStatus.name,
      'p_note': note,
    }, failMessage: 'order_status_failed'),
  );

  // ----- Products / Inventory -----
  @override
  Future<void> upsertProduct({
    required AppUser actor,
    required ProductDraft product,
  }) => _callRpc('upsert_product', {
    'p_product_id': product.id,
    'p_name': product.name,
    'p_sku': product.sku,
    'p_category': product.category,
    'p_purchase_price': product.purchasePrice,
    'p_sale_price': product.salePrice,
    'p_stock': product.stock,
    'p_min_stock': product.minStockLevel,
  }, failMessage: 'product_op_failed');

  @override
  Future<void> deleteProduct({
    required AppUser actor,
    required String productId,
  }) => _callRpc('delete_product', {
    'p_product_id': productId,
  }, failMessage: 'product_delete_failed');

  @override
  Future<void> adjustInventory({
    required AppUser actor,
    required String productId,
    required int quantityDelta,
    required String reason,
  }) => _callRpc('adjust_inventory', {
    'p_product_id': productId,
    'p_quantity_delta': quantityDelta,
    'p_reason': reason,
  }, failMessage: 'inventory_adjust_failed');

  // ----- Employees -----
  @override
  Future<void> createEmployee({
    required AppUser actor,
    required EmployeeDraft employee,
  }) => _callEmployeeFn(action: 'create', employee: employee);

  @override
  Future<void> updateEmployee({
    required AppUser actor,
    required EmployeeDraft employee,
  }) => _callEmployeeFn(action: 'update', employee: employee);

  @override
  Future<void> deactivateEmployee({
    required String employeeId,
    required bool isActive,
    required AppUser actor,
  }) => _callEmployeeFn(
    action: 'deactivate',
    employee: EmployeeDraft(
      id: employeeId,
      name: actor.name,
      email: actor.email,
      role: actor.role,
      permissions: actor.permissions,
      isActive: isActive,
    ),
  );

  @override
  Future<void> deleteEmployee({
    required AppUser actor,
    required String employeeId,
  }) => _callEmployeeFn(
    action: 'delete',
    employee: EmployeeDraft(
      id: employeeId,
      name: actor.name,
      email: actor.email,
      role: actor.role,
      permissions: actor.permissions,
      isActive: false,
    ),
  );

  // ----- Notifications -----
  @override
  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'read': true})
          .eq('id', notificationId);
    } catch (_) {
      // ignore: the stream will retry on next emission
    }
  }

  Future<void> _callEmployeeFn({
    required String action,
    required EmployeeDraft employee,
  }) async {
    await _ensureCurrentUserProfile();
    final token = await _freshAccessToken();

    final payload = {
      'action': action,
      'employeeId': employee.id,
      'name': employee.name,
      'email': employee.email,
      'password': employee.password,
      'companyName': employee.companyName,
      'roleName': employee.role.label,
      'permissions': employee.permissions.map((e) => e.code).toList(),
      'isActive': employee.isActive,
    };

    try {
      final res = await _supabase.functions.invoke(
        'admin-manage-employee',
        body: payload,
        headers: {
          'Authorization': 'Bearer $token',
          // Supabase Edge requires the project anon/public key in apikey header.
          'apikey': AppConstants.supabaseClientKey,
          'Content-Type': 'application/json',
        },
      );
      if (res.status >= 400) {
        throw AppException(res.data?.toString() ?? 'employee_op_failed');
      }
    } on FunctionException {
      throw AppException('employee_op_failed');
    } catch (_) {
      throw AppException('employee_op_failed');
    }
  }

  Future<String> _freshAccessToken() async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw AppException('auth_required');

    var token = session.accessToken;
    final expiresAt = session.expiresAt;
    if (expiresAt != null) {
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
        isUtc: true,
      ).toLocal();
      if (expiry.isBefore(DateTime.now().add(const Duration(seconds: 30)))) {
        final refreshed = await _supabase.auth.refreshSession();
        token = refreshed.session?.accessToken ?? token;
      }
    }
    if (token.isEmpty) throw AppException('auth_required');
    return token;
  }

  Future<void> _ensureCurrentUserProfile() async {
    try {
      await _supabase.rpc('ensure_current_user_profile');
    } catch (_) {
      // Ignore: if RPC is missing or user already exists, we still proceed.
    }
  }

  Future<void> _callRpc(
    String fn,
    Map<String, dynamic> params, {
    required String failMessage,
  }) async {
    try {
      await _supabase.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      if (e.code == '23505' && fn == 'upsert_product') {
        throw AppException('product_sku_exists');
      }
      if (e.code == '23503' && fn == 'create_order') {
        throw AppException('order_product_missing');
      }
      throw AppException('$failMessage: ${e.details}');
    } on AuthException catch (_) {
      throw AppException(failMessage);
    } catch (_) {
      throw AppException(failMessage);
    }
  }

  Product _mapProductRow(Map row) => Product(
    id: row['id'].toString(),
    name: row['name']?.toString() ?? '',
    sku: row['sku']?.toString() ?? '',
    category: row['category']?.toString() ?? '',
    purchasePrice: (row['purchase_price'] as num?)?.toDouble() ?? 0,
    salePrice: (row['sale_price'] as num?)?.toDouble() ?? 0,
    currentStock: row['current_stock'] as int? ?? 0,
    minStockLevel: row['min_stock_level'] as int? ?? 0,
  );

  OrderEntity _mapOrderRow(Map row) => OrderEntity(
    id: row['id'].toString(),
    orderNo: (row['order_no'] as num?)?.toInt() ?? 0,
    customerName: row['customer_name']?.toString() ?? '',
    customerPhone: row['customer_phone']?.toString() ?? '',
    customerAddress: row['customer_address']?.toString(),
    orderDate:
        DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.now(),
    notes: row['order_notes']?.toString(),
    status: OrderStatus.values.firstWhere(
      (s) => s.name == (row['status']?.toString() ?? 'entered'),
      orElse: () => OrderStatus.entered,
    ),
    createdBy: row['created_by']?.toString() ?? '',
    createdByName: row['created_by_name']?.toString() ?? '',
    items: const [],
    history: const [],
  );

  ActivityLog _mapActivityRow(Map row) => ActivityLog(
    id: row['id'].toString(),
    actorId: row['actor_id']?.toString() ?? '',
    actorName: row['actor_name']?.toString() ?? '',
    actorEmail: row['actor_email']?.toString(),
    action: row['action']?.toString() ?? '',
    entityType: row['entity_type']?.toString() ?? '',
    entityId: row['entity_id']?.toString(),
    createdAt:
        DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.now(),
    metadata: row['metadata'] as Map<String, dynamic>?,
    companyId: row['company_id']?.toString(),
  );

  Future<String> _resolveEmail(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.contains('@')) return trimmed;

    // Try Supabase lookup by username -> email
    final res = await _supabase
        .from('users')
        .select('email')
        .eq('username', trimmed)
        .maybeSingle();
    final email = res == null ? null : res['email']?.toString();
    if (email != null && email.contains('@')) return email;

    // Fallback: append configured domain if present
    if (AppConstants.loginFallbackDomain.isNotEmpty) {
      return '$trimmed@${AppConstants.loginFallbackDomain}';
    }
    return trimmed;
  }

  String _mapAuthError(AuthException e) {
    switch (e.code) {
      case 'invalid_credentials':
      case 'invalid_grant':
      case 'invalid_password':
      case 'user_not_found':
      case 'invalid_login_credentials':
        return 'auth_invalid_credentials';
      case 'invalid_credential':
        return 'auth_invalid_credential';
      case 'invalid_email':
        return 'auth_invalid_email';
      case 'too_many_requests':
        return 'auth_too_many_requests';
      default:
        return 'auth_generic_error';
    }
  }
  @override
  Future<OrderEntity?> getOrderById(String id) async {
    final res = await _supabase
        .from('orders')
        .select('''
          id,
          order_no,
          customer_name,
          customer_phone,
          customer_address,
          created_at,
          status,
          created_by,
          created_by_name,
          order_notes,
          order_items (product_id, product_name, quantity, purchase_price, sale_price),
          order_status_history (status, changed_by, changed_by_name, changed_at, note)
        ''')
        .eq('id', id)
        .maybeSingle();

    if (res == null) return null;

    final mapped = RemoteMapper.order({
      ...res,
      'order_date': res['created_at'],
    });
    return mapped;
  }
}
