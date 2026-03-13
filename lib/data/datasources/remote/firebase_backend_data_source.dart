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
    required this.roleName,
    required this.isHardAdmin,
  });

  final String id;
  final String name;
  final String email;
  final String roleName;
  final bool isHardAdmin;
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
      roleId: '',
      role: isHardAdmin ? UserRole.admin : UserRole.fromRoleName(roleName),
      permissions: perms,
      createdAt: DateTime.now(),
      isActive: true,
      lastActive: null,
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
        final enrichedPerms = await _loadPermissionsFromRelations(
          userId: user.id,
          roleId: rpcRes['role_id'],
        );
        rpcRes = Map.of(rpcRes)..['permissions'] = enrichedPerms.toList();
      }
      return _mapUserFromProfile(rpcRes, user);
    }

    // Manual relational path: auth.user -> users -> role_permissions/user_permissions
    final profileRow = await _supabase
        .from('users')
        .select(
          'id, email, name, role_id, created_at, is_active, last_active, role:role_id(name)',
        )
        .eq('id', user.id)
        .maybeSingle();

    final roleName =
        profileRow?['role']?['name']?.toString() ?? 'Order Entry User';
    final perms = await _loadPermissionsFromRelations(
      userId: user.id,
      roleId: profileRow?['role_id']?.toString(),
    );

    final DateTime? parsedCreatedAt = DateTime.tryParse(
      profileRow?['created_at']?.toString() ?? user.createdAt,
    );
    final DateTime? parsedLastActive = profileRow?['last_active'] != null
        ? DateTime.tryParse(profileRow!['last_active'].toString())
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
      roleId: profileRow?['role_id']?.toString() ?? 'supabase-default',
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
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.map(_mapOrderRow).toList());

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
          return _UserAcc(
            id: id,
            name: row['name']?.toString() ?? 'User',
            email: email,
            roleName: roleName,
            isHardAdmin: _isHardAdmin(email),
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
      _supabase.from('orders').stream(primaryKey: ['id']).map((rows) {
        final Map<String, ReportAcc> acc = {};
        for (final r in rows) {
          final createdBy = r['created_by']?.toString() ?? 'unknown';
          final name = r['created_by_name']?.toString() ?? 'Unknown';
          final status = (r['status']?.toString() ?? 'entered').toLowerCase();
          final entry = acc.putIfAbsent(
            createdBy,
            () => ReportAcc(id: createdBy, name: name),
          );
          switch (status) {
            case 'entered':
              entry.entered++;
              break;
            case 'checked':
              entry.reviewed++;
              break;
            case 'shipped':
              entry.shipped++;
              break;
            case 'returned':
              entry.returned++;
              break;
            default:
              break;
          }
        }
        return acc.values.map((e) => e.toReport()).toList();
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

  Future<Set<AppPermission>> _loadPermissionsFromRelations({
    required String userId,
    String? roleId,
  }) async {
    final codes = <String>{};
    // role -> role_permissions
    if (roleId != null && roleId.isNotEmpty) {
      final rolePerms = await _supabase
          .from('role_permissions')
          .select('permission_code')
          .eq('role_id', roleId);
      for (final row in rolePerms) {
        final c = row['permission_code']?.toString();
        if (c != null) codes.add(c);
      }
    }
    // direct user_permissions
    final userPerms = await _supabase
        .from('user_permissions')
        .select('permission_code')
        .eq('user_id', userId);
    for (final row in userPerms) {
      final c = row['permission_code']?.toString();
      if (c != null) codes.add(c);
    }

    return codes.map(AppPermission.fromCode).whereType<AppPermission>().toSet();
  }

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
