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
import 'package:supabase_flutter/supabase_flutter.dart';

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
      name: res['name']?.toString() ??
          fallback.userMetadata?['name']?.toString() ??
          (fallback.email ?? 'User'),
      email: email,
      roleId: res['role_id']?.toString() ?? 'supabase-default',
      role: isAdminOverride ? UserRole.admin : UserRole.fromRoleName(roleName),
      permissions: isAdminOverride ? AppPermission.values.toSet() : perms,
      createdAt: DateTime.tryParse(res['created_at']?.toString() ?? '') ??
          DateTime.tryParse(fallback.createdAt) ??
          DateTime.now(),
      isActive: res['is_active'] as bool? ?? true,
      lastActive: DateTime.tryParse(res['last_active']?.toString() ?? '') ??
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
        final enrichedPerms =
            await _loadPermissionsFromRelations(userId: user.id, roleId: rpcRes['role_id']);
        rpcRes = Map.of(rpcRes)..['permissions'] = enrichedPerms.toList();
      }
      return _mapUserFromProfile(rpcRes, user);
    }

    // Manual relational path: auth.user -> users -> role_permissions/user_permissions
    final profileRow = await _supabase
        .from('users')
        .select('id, email, name, role_id, created_at, is_active, last_active, role:role_id(name)')
        .eq('id', user.id)
        .maybeSingle();

    final roleName = profileRow?['role']?['name']?.toString() ?? 'Order Entry User';
    final perms = await _loadPermissionsFromRelations(
      userId: user.id,
      roleId: profileRow?['role_id']?.toString(),
    );

    final DateTime? parsedCreatedAt =
        DateTime.tryParse(profileRow?['created_at']?.toString() ?? user.createdAt);
    final DateTime? parsedLastActive =
        profileRow?['last_active'] != null
            ? DateTime.tryParse(profileRow!['last_active'].toString())
            : (user.lastSignInAt == null ? null : DateTime.tryParse(user.lastSignInAt!));

    final email = profileRow?['email']?.toString() ?? (user.email ?? '');
    final isAdminOverride = _isHardAdmin(email);

    final basePerms = _defaultPermissionsForRole(roleName);
    final mergedPerms =
        isAdminOverride ? AppPermission.values.toSet() : basePerms.union(perms);

    return AppUser(
      id: user.id,
      name: profileRow?['name']?.toString() ??
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
  Stream<List<OrderEntity>> watchOrders() =>
      Stream.value(const <OrderEntity>[]);

  @override
  Stream<List<Product>> watchProducts() =>
      Stream.value(const <Product>[]);

  @override
  Stream<List<AppNotification>> watchNotifications(String userId) =>
      Stream.value(const <AppNotification>[]);

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
          entry.permissionCodes
              .addAll(AppPermission.values.map((e) => e.code));
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
  Stream<List<ActivityLog>> watchActivityLogs() =>
      Stream.value(const <ActivityLog>[]);

  @override
  Stream<DashboardSnapshot> watchDashboardSnapshot() =>
      Stream.value(_emptyDashboardSnapshot);

  @override
  Stream<List<EmployeeReport>> watchEmployeeReports() =>
      Stream.value(const <EmployeeReport>[]);

  // ----- Orders -----
  @override
  Future<void> createOrder({
    required AppUser actor,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String? notes,
    required List<OrderItem> items,
  }) =>
      _notImplemented('createOrder');

  @override
  Future<void> updateOrder({
    required AppUser actor,
    required String orderId,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String? notes,
    required List<OrderItem> items,
  }) =>
      _notImplemented('updateOrder');

  @override
  Future<void> deleteOrder({required AppUser actor, required String orderId}) =>
      _notImplemented('deleteOrder');

  @override
  Future<void> transitionOrder({
    required AppUser actor,
    required String orderId,
    required OrderStatus nextStatus,
    String? note,
  }) =>
      _notImplemented('transitionOrder');

  @override
  Future<void> overrideOrderStatus({
    required AppUser actor,
    required String orderId,
    required OrderStatus nextStatus,
    String? note,
  }) =>
      _notImplemented('overrideOrderStatus');

  // ----- Products / Inventory -----
  @override
  Future<void> upsertProduct({
    required AppUser actor,
    required ProductDraft product,
  }) =>
      _notImplemented('upsertProduct');

  @override
  Future<void> deleteProduct({
    required AppUser actor,
    required String productId,
  }) =>
      _notImplemented('deleteProduct');

  @override
  Future<void> adjustInventory({
    required AppUser actor,
    required String productId,
    required int quantityDelta,
    required String reason,
  }) =>
      _notImplemented('adjustInventory');

  // ----- Employees -----
  @override
  Future<void> createEmployee({
    required AppUser actor,
    required EmployeeDraft employee,
  }) =>
      _notImplemented('createEmployee');

  @override
  Future<void> updateEmployee({
    required AppUser actor,
    required EmployeeDraft employee,
  }) =>
      _notImplemented('updateEmployee');

  @override
  Future<void> deactivateEmployee({
    required String employeeId,
    required bool isActive,
    required AppUser actor,
  }) =>
      _notImplemented('deactivateEmployee');

  @override
  Future<void> deleteEmployee({
    required AppUser actor,
    required String employeeId,
  }) =>
      _notImplemented('deleteEmployee');

  // ----- Notifications -----
  @override
  Future<void> markNotificationRead(String notificationId) =>
      _notImplemented('markNotificationRead');

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

    return codes
        .map(AppPermission.fromCode)
        .whereType<AppPermission>()
        .toSet();
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

  Future<void> _notImplemented(String method) async {
    throw AppException('$method is not implemented for Firebase yet.');
  }

  static final DashboardSnapshot _emptyDashboardSnapshot = DashboardSnapshot(
    totalOrders: 0,
    ordersByStatus: {
      for (final status in OrderStatus.values) status: 0,
    },
    revenue: 0,
    profit: 0,
    inventoryValue: 0,
    lowStockAlerts: 0,
    recentOrders: const [],
    userActivity: const [],
  );
}
