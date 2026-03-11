import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

class FirebaseBackendDataSource implements BackendDataSource {
  FirebaseBackendDataSource()
      : _auth = FirebaseAuth.instance,
        _db = FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AppUser _mapUser(User user) => AppUser(
        id: user.uid,
        name: user.displayName ?? (user.email ?? 'User'),
        email: user.email ?? '',
        roleId: 'firebase-default',
        role: UserRole.orderEntry,
        permissions: <AppPermission>{},
        createdAt: user.metadata.creationTime ?? DateTime.now(),
        isActive: true,
        lastActive: user.metadata.lastSignInTime,
      );

  @override
  Stream<AppUser?> watchSession() =>
      _auth.authStateChanges().map((u) => u == null ? null : _mapUser(u));

  @override
  Future<AppUser?> getCurrentUser() async {
    final user = _auth.currentUser;
    return user == null ? null : _mapUser(user);
  }

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    final email = await _resolveEmail(identifier);

    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AppException(_mapAuthError(e, identifier: identifier));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  // ----- Streams -----
  @override
  Stream<List<OrderEntity>> watchOrders() => const Stream.empty();

  @override
  Stream<List<Product>> watchProducts() => const Stream.empty();

  @override
  Stream<List<AppNotification>> watchNotifications(String userId) =>
      const Stream.empty();

  @override
  Stream<List<AppUser>> watchUsers() => const Stream.empty();

  @override
  Stream<List<ActivityLog>> watchActivityLogs() => const Stream.empty();

  @override
  Stream<DashboardSnapshot> watchDashboardSnapshot() =>
      Stream.value(_emptyDashboardSnapshot);

  @override
  Stream<List<EmployeeReport>> watchEmployeeReports() =>
      const Stream.empty();

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

  Future<String> _resolveEmail(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.contains('@')) return trimmed;

    // Try Firestore lookup by username -> email
    try {
      final snap = await _db
          .collection('users')
          .where('username', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final email = data['email']?.toString();
        if (email != null && email.contains('@')) {
          return email;
        }
      }
    } catch (_) {
      // Ignore lookup errors and fall back to other strategies.
    }

    // Fallback: append configured domain if present
    if (AppConstants.loginFallbackDomain.isNotEmpty) {
      return '$trimmed@${AppConstants.loginFallbackDomain}';
    }
    return trimmed;
  }

  String _mapAuthError(
    FirebaseAuthException e, {
    required String identifier,
  }) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
        return 'بيانات الدخول غير صحيحة. جرّب البريد الإلكتروني أو اسم المستخدم مع كلمة المرور الصحيحة.';
      case 'invalid-email':
        return 'صيغة البريد أو اسم المستخدم غير صحيحة.';
      case 'too-many-requests':
        return 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.';
      default:
        return e.message ?? 'تعذّر تسجيل الدخول.';
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
