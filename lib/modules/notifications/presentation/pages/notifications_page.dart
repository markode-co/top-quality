import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/app_notification.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key, required this.onOpenOrder});

  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsValue = ref.watch(notificationsProvider);
    final operationsState = ref.watch(operationsControllerProvider);
    final localeTag = Localizations.localeOf(context).toString();

    return notificationsValue.when(
      data: (notifications) {
        if (notifications.isEmpty) {
          return EmptyPlaceholder(
            title: context.t(en: 'No notifications', ar: 'لا توجد إشعارات'),
            subtitle: context.t(
              en: 'Workflow and system notifications will appear here.',
              ar: 'ستظهر إشعارات النظام وسير العمل هنا.',
            ),
          );
        }

        final unreadIds = notifications
            .where((notification) => !notification.isRead)
            .map((notification) => notification.id)
            .toList();

        return ResponsiveListView(
          onRefresh: () async {
            ref.invalidate(notificationsProvider);
            try {
              await ref.read(notificationsProvider.future);
            } catch (_) {}
          },
          children: [
            if (unreadIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Align(
                  alignment:
                      context.isArabic ? Alignment.centerRight : Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: operationsState.isLoading
                        ? null
                        : () => ref
                            .read(operationsControllerProvider.notifier)
                            .markAllNotificationsRead(unreadIds),
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: Text(
                      context.t(en: 'Mark all as read', ar: 'تحديد الكل كمقروء'),
                    ),
                  ),
                ),
              ),
            ...notifications.map((notification) {
              final localized = _NotificationTextLocalizer.localize(notification, context);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NotificationCard(
                  notification: notification,
                  title: localized.title,
                  message: localized.message,
                  dateText: AppFormatters.shortDateTime(
                    notification.createdAt,
                    localeTag,
                  ),
                  onMarkRead: notification.isRead
                      ? null
                      : () => ref
                          .read(operationsControllerProvider.notifier)
                          .markNotificationRead(notification.id),
                  onOpenOrder: notification.referenceId?.startsWith('ORD-') == true
                      ? () => onOpenOrder(notification.referenceId!)
                      : null,
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        final text = error.toString();
        final isRealtimeTimeout =
            text.contains('RealtimeSubscribeException') ||
            text.toLowerCase().contains('timedout');
        return EmptyPlaceholder(
          title: context.t(
            en: 'Notifications temporarily unavailable',
            ar: 'الإشعارات غير متاحة مؤقتًا',
          ),
          subtitle: isRealtimeTimeout
              ? context.t(
                  en: 'Realtime connection timed out. Pull to refresh or try again shortly.',
                  ar: 'انتهت مهلة الاتصال المباشر. اسحب للتحديث أو أعد المحاولة بعد قليل.',
                )
              : context.t(
                  en: 'Unable to load notifications right now.',
                  ar: 'تعذر تحميل الإشعارات حاليًا.',
                ),
          icon: Icons.notifications_off_outlined,
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.title,
    required this.message,
    required this.dateText,
    required this.onMarkRead,
    required this.onOpenOrder,
  });

  final AppNotification notification;
  final String title;
  final String message;
  final String dateText;
  final VoidCallback? onMarkRead;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = switch (notification.type) {
      NotificationType.alert => scheme.error,
      NotificationType.system => scheme.tertiary,
      NotificationType.workflow => scheme.primary,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: Badge(
          isLabelVisible: !notification.isRead,
          child: Icon(Icons.notifications_none_outlined, color: iconColor),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$message\n$dateText',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: onMarkRead,
          child: Text(context.t(en: 'Mark read', ar: 'تحديد كمقروء')),
        ),
        onTap: onOpenOrder,
      ),
    );
  }
}

class _LocalizedNotificationText {
  const _LocalizedNotificationText({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;
}

enum _NotificationIntent {
  orderStatus,
  orderCreated,
  orderUpdated,
  orderDeleted,
  productCreated,
  productUpdated,
  productDeleted,
  employeeUpdated,
  employeeCreated,
  employeeTransferred,
  employeeActivated,
  employeeDeactivated,
  employeeDeleted,
  generic,
}

class _NotificationTextLocalizer {
  static final RegExp _arOrderStatusPattern = RegExp(
    r'^\s*الطلب\s*رقم\s*(\d+)\s*أصبح\s*(.+?)\s*(?:\(بواسطة\s*(.+?)\))?\s*$',
  );
  static final RegExp _enOrderStatusPattern = RegExp(
    r'^\s*Order\s*#?\s*(\d+)\s*(?:is now|became)\s*(.+?)\s*(?:\(by\s*(.+?)\))?\s*$',
    caseSensitive: false,
  );

  static final RegExp _arOrderCreatedPattern = RegExp(
    r'^\s*تم\s*إنشاء\s*الطلب\s*رقم\s*(\d+)\s*(?:بواسطة\s*(.+?))?\s*$',
  );
  static final RegExp _enOrderCreatedPattern = RegExp(
    r'^\s*Order\s*#?\s*(\d+)\s*(?:was\s+)?created(?:\s+by\s+(.+?))?\s*$',
    caseSensitive: false,
  );

  static final RegExp _arOrderUpdatedPattern = RegExp(
    r'^\s*تم\s*تعديل\s*الطلب\s*رقم\s*(\d+)\s*(?:بواسطة\s*(.+?))?\s*$',
  );
  static final RegExp _enOrderUpdatedPattern = RegExp(
    r'^\s*Order\s*#?\s*(\d+)\s*(?:was\s+)?updated(?:\s+by\s+(.+?))?\s*$',
    caseSensitive: false,
  );

  static final RegExp _arOrderDeletedPattern = RegExp(
    r'^\s*تم\s*حذف\s*الطلب\s*رقم\s*(\d+)\s*(?:بواسطة\s*(.+?))?\s*$',
  );
  static final RegExp _enOrderDeletedPattern = RegExp(
    r'^\s*Order\s*#?\s*(\d+)\s*(?:was\s+)?deleted(?:\s+by\s+(.+?))?\s*$',
    caseSensitive: false,
  );

  static final RegExp _actorPattern = RegExp(
    r'^\s*(.+?)\s*\((?:by|بواسطة)\s*(.+?)\)\s*$',
    caseSensitive: false,
  );

  static _LocalizedNotificationText localize(
    AppNotification notification,
    BuildContext context,
  ) {
    final intent = _detectIntent(notification.title, notification.message);
    return _LocalizedNotificationText(
      title: _localizeTitle(intent, context, fallback: notification.title),
      message: _localizeMessage(
        intent,
        notification.message,
        context,
      ),
    );
  }

  static _NotificationIntent _detectIntent(String title, String message) {
    final haystack = '${_normalizeForMatch(title)} ${_normalizeForMatch(message)}';

    if (_hasAnyToken(haystack, const ['order status', 'حاله الطلب', 'تغيرت حاله الطلب'])) {
      return _NotificationIntent.orderStatus;
    }
    if (_hasAnyToken(haystack, const ['order created', 'تم انشاء الطلب'])) {
      return _NotificationIntent.orderCreated;
    }
    if (_hasAnyToken(haystack, const ['order updated', 'تم تعديل الطلب'])) {
      return _NotificationIntent.orderUpdated;
    }
    if (_hasAnyToken(haystack, const ['order deleted', 'تم حذف الطلب'])) {
      return _NotificationIntent.orderDeleted;
    }
    if (_hasAnyToken(haystack, const ['product created', 'تم انشاء المنتج'])) {
      return _NotificationIntent.productCreated;
    }
    if (_hasAnyToken(haystack, const ['product updated', 'تم تحديث المنتج'])) {
      return _NotificationIntent.productUpdated;
    }
    if (_hasAnyToken(haystack, const ['product deleted', 'تم حذف منتج', 'تم حذف المنتج'])) {
      return _NotificationIntent.productDeleted;
    }
    if (_hasAnyToken(haystack, const ['employee transferred', 'تم نقل الموظف'])) {
      return _NotificationIntent.employeeTransferred;
    }
    if (_hasAnyToken(haystack, const ['employee updated', 'تم تحديث بيانات الموظف'])) {
      return _NotificationIntent.employeeUpdated;
    }
    if (_hasAnyToken(haystack, const ['employee created', 'تم انشاء موظف'])) {
      return _NotificationIntent.employeeCreated;
    }
    if (_hasAnyToken(haystack, const ['employee activated', 'تم تفعيل الموظف'])) {
      return _NotificationIntent.employeeActivated;
    }
    if (_hasAnyToken(haystack, const ['employee deactivated', 'تم ايقاف الموظف'])) {
      return _NotificationIntent.employeeDeactivated;
    }
    if (_hasAnyToken(haystack, const ['employee deleted', 'تم حذف الموظف'])) {
      return _NotificationIntent.employeeDeleted;
    }

    return _NotificationIntent.generic;
  }

  static String _localizeTitle(
    _NotificationIntent intent,
    BuildContext context, {
    required String fallback,
  }) {
    return switch (intent) {
      _NotificationIntent.orderStatus =>
        context.t(en: 'Order status changed', ar: 'تم تغيير حالة الطلب'),
      _NotificationIntent.orderCreated =>
        context.t(en: 'Order created', ar: 'تم إنشاء طلب'),
      _NotificationIntent.orderUpdated =>
        context.t(en: 'Order updated', ar: 'تم تعديل طلب'),
      _NotificationIntent.orderDeleted =>
        context.t(en: 'Order deleted', ar: 'تم حذف طلب'),
      _NotificationIntent.productCreated =>
        context.t(en: 'Product created', ar: 'تم إنشاء منتج'),
      _NotificationIntent.productUpdated =>
        context.t(en: 'Product updated', ar: 'تم تحديث منتج'),
      _NotificationIntent.productDeleted =>
        context.t(en: 'Product deleted', ar: 'تم حذف منتج'),
      _NotificationIntent.employeeUpdated =>
        context.t(en: 'Employee details updated', ar: 'تم تحديث بيانات الموظف'),
      _NotificationIntent.employeeCreated =>
        context.t(en: 'New employee created', ar: 'تم إنشاء موظف جديد'),
      _NotificationIntent.employeeTransferred =>
        context.t(en: 'Employee transferred', ar: 'تم نقل الموظف'),
      _NotificationIntent.employeeActivated =>
        context.t(en: 'Employee activated', ar: 'تم تفعيل الموظف'),
      _NotificationIntent.employeeDeactivated =>
        context.t(en: 'Employee deactivated', ar: 'تم إيقاف الموظف'),
      _NotificationIntent.employeeDeleted =>
        context.t(en: 'Employee deleted', ar: 'تم حذف الموظف'),
      _NotificationIntent.generic => _translateByPhraseOnly(fallback, context),
    };
  }

  static String _localizeMessage(
    _NotificationIntent intent,
    String rawMessage,
    BuildContext context,
  ) {
    final orderStatusMessage = _buildOrderStatusMessage(rawMessage, context);
    if (orderStatusMessage != null) return orderStatusMessage;

    final orderCreatedMessage = _buildOrderCreatedMessage(rawMessage, context);
    if (orderCreatedMessage != null) return orderCreatedMessage;

    final orderUpdatedMessage = _buildOrderUpdatedMessage(rawMessage, context);
    if (orderUpdatedMessage != null) return orderUpdatedMessage;

    final orderDeletedMessage = _buildOrderDeletedMessage(rawMessage, context);
    if (orderDeletedMessage != null) return orderDeletedMessage;

    final actorMessage = _buildActorMessage(rawMessage, context, intent);
    if (actorMessage != null) return actorMessage;

    return _translateByPhraseOnly(rawMessage, context);
  }

  static String? _buildOrderStatusMessage(String rawMessage, BuildContext context) {
    final arMatch = _arOrderStatusPattern.firstMatch(rawMessage);
    if (arMatch != null) {
      final orderNo = arMatch.group(1)!;
      final statusLabel = _statusLabel(arMatch.group(2) ?? '', context);
      final actor = arMatch.group(3)?.trim();
      return _formatOrderStatus(orderNo, statusLabel, actor, context);
    }

    final enMatch = _enOrderStatusPattern.firstMatch(rawMessage);
    if (enMatch != null) {
      final orderNo = enMatch.group(1)!;
      final statusLabel = _statusLabel(enMatch.group(2) ?? '', context);
      final actor = enMatch.group(3)?.trim();
      return _formatOrderStatus(orderNo, statusLabel, actor, context);
    }
    return null;
  }

  static String _formatOrderStatus(
    String orderNo,
    String statusLabel,
    String? actor,
    BuildContext context,
  ) {
    if (context.isArabic) {
      final base = 'الطلب رقم $orderNo أصبح $statusLabel';
      if (actor == null || actor.isEmpty) return base;
      return '$base (بواسطة $actor)';
    }
    final base = 'Order #$orderNo is now $statusLabel';
    if (actor == null || actor.isEmpty) return base;
    return '$base (by $actor)';
  }

  static String? _buildOrderCreatedMessage(String rawMessage, BuildContext context) {
    final arMatch = _arOrderCreatedPattern.firstMatch(rawMessage);
    if (arMatch != null) {
      return _formatOrderCreated(
        orderNo: arMatch.group(1)!,
        actor: arMatch.group(2)?.trim(),
        context: context,
      );
    }
    final enMatch = _enOrderCreatedPattern.firstMatch(rawMessage);
    if (enMatch != null) {
      return _formatOrderCreated(
        orderNo: enMatch.group(1)!,
        actor: enMatch.group(2)?.trim(),
        context: context,
      );
    }
    return null;
  }

  static String _formatOrderCreated({
    required String orderNo,
    required String? actor,
    required BuildContext context,
  }) {
    if (context.isArabic) {
      final base = 'تم إنشاء الطلب رقم $orderNo';
      if (actor == null || actor.isEmpty) return base;
      return '$base بواسطة $actor';
    }
    final base = 'Order #$orderNo was created';
    if (actor == null || actor.isEmpty) return base;
    return '$base by $actor';
  }

  static String? _buildOrderUpdatedMessage(String rawMessage, BuildContext context) {
    final arMatch = _arOrderUpdatedPattern.firstMatch(rawMessage);
    if (arMatch != null) {
      return _formatOrderUpdated(
        orderNo: arMatch.group(1)!,
        actor: arMatch.group(2)?.trim(),
        context: context,
      );
    }
    final enMatch = _enOrderUpdatedPattern.firstMatch(rawMessage);
    if (enMatch != null) {
      return _formatOrderUpdated(
        orderNo: enMatch.group(1)!,
        actor: enMatch.group(2)?.trim(),
        context: context,
      );
    }
    return null;
  }

  static String _formatOrderUpdated({
    required String orderNo,
    required String? actor,
    required BuildContext context,
  }) {
    if (context.isArabic) {
      final base = 'تم تعديل الطلب رقم $orderNo';
      if (actor == null || actor.isEmpty) return base;
      return '$base بواسطة $actor';
    }
    final base = 'Order #$orderNo was updated';
    if (actor == null || actor.isEmpty) return base;
    return '$base by $actor';
  }

  static String? _buildOrderDeletedMessage(String rawMessage, BuildContext context) {
    final arMatch = _arOrderDeletedPattern.firstMatch(rawMessage);
    if (arMatch != null) {
      return _formatOrderDeleted(
        orderNo: arMatch.group(1)!,
        actor: arMatch.group(2)?.trim(),
        context: context,
      );
    }
    final enMatch = _enOrderDeletedPattern.firstMatch(rawMessage);
    if (enMatch != null) {
      return _formatOrderDeleted(
        orderNo: enMatch.group(1)!,
        actor: enMatch.group(2)?.trim(),
        context: context,
      );
    }
    return null;
  }

  static String _formatOrderDeleted({
    required String orderNo,
    required String? actor,
    required BuildContext context,
  }) {
    if (context.isArabic) {
      final base = 'تم حذف الطلب رقم $orderNo';
      if (actor == null || actor.isEmpty) return base;
      return '$base بواسطة $actor';
    }
    final base = 'Order #$orderNo was deleted';
    if (actor == null || actor.isEmpty) return base;
    return '$base by $actor';
  }

  static String? _buildActorMessage(
    String rawMessage,
    BuildContext context,
    _NotificationIntent intent,
  ) {
    final match = _actorPattern.firstMatch(rawMessage);
    if (match == null) return null;
    final subject = match.group(1)?.trim() ?? '';
    final actor = match.group(2)?.trim() ?? '';
    if (subject.isEmpty) return null;

    return switch (intent) {
      _NotificationIntent.productDeleted => context.isArabic
          ? 'تم حذف المنتج $subject (بواسطة $actor)'
          : 'Product $subject was deleted (by $actor)',
      _NotificationIntent.productUpdated => context.isArabic
          ? 'تم تحديث المنتج $subject (بواسطة $actor)'
          : 'Product $subject was updated (by $actor)',
      _NotificationIntent.productCreated => context.isArabic
          ? 'تم إنشاء المنتج $subject (بواسطة $actor)'
          : 'Product $subject was created (by $actor)',
      _ => context.isArabic
          ? '$subject (بواسطة $actor)'
          : '$subject (by $actor)',
    };
  }

  static String _statusLabel(String raw, BuildContext context) {
    final status = _resolveOrderStatus(raw);
    if (status == null) return raw.trim();
    return context.orderStatusLabel(status);
  }

  static OrderStatus? _resolveOrderStatus(String rawStatus) {
    final normalized = _normalizeForMatch(rawStatus);

    if (_hasAnyToken(normalized, const ['entered', 'entry', 'ادخال', 'تم الادخال'])) {
      return OrderStatus.entered;
    }
    if (_hasAnyToken(normalized, const ['checked', 'review', 'مراجعه', 'تمت المراجعه'])) {
      return OrderStatus.checked;
    }
    if (_hasAnyToken(normalized, const ['approved', 'approval', 'اعتماد', 'تم الاعتماد'])) {
      return OrderStatus.approved;
    }
    if (_hasAnyToken(normalized, const ['shipped', 'shipping', 'شحن', 'تم الشحن'])) {
      return OrderStatus.shipped;
    }
    if (_hasAnyToken(normalized, const ['completed', 'complete', 'مكتمل'])) {
      return OrderStatus.completed;
    }
    if (_hasAnyToken(normalized, const ['returned', 'return', 'مرتجع', 'رجوع'])) {
      return OrderStatus.returned;
    }
    return null;
  }

  static String _translateByPhraseOnly(String value, BuildContext context) {
    if (context.isArabic) {
      return value
          .replaceAll('(by ', '(بواسطة ')
          .replaceAll('Order #', 'الطلب رقم ')
          .replaceAll(' was created', ' تم إنشاؤه')
          .replaceAll(' was updated', ' تم تعديله')
          .replaceAll(' was deleted', ' تم حذفه');
    }
    return value
        .replaceAll('(بواسطة ', '(by ')
        .replaceAll('الطلب رقم ', 'Order #')
        .replaceAll('تم إنشاء', 'Created')
        .replaceAll('تم تعديل', 'Updated')
        .replaceAll('تم حذف', 'Deleted');
  }

  static bool _hasAnyToken(String normalizedText, List<String> tokens) {
    for (final token in tokens) {
      final normalizedToken = _normalizeForMatch(token);
      if (normalizedText == normalizedToken ||
          normalizedText.contains(normalizedToken)) {
        return true;
      }
    }
    return false;
  }

  static String _normalizeForMatch(String value) {
    final collapsed = value
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    return collapsed.replaceAll(RegExp(r'\s+'), ' ');
  }
}
