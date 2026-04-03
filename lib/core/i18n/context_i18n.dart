import 'package:flutter/material.dart';
import 'package:top_quality/core/constants/app_enums.dart';

extension ContextI18n on BuildContext {
  bool get isArabic =>
      Localizations.localeOf(this).languageCode.toLowerCase() == 'ar';

  String t({required String en, required String ar}) => isArabic ? ar : en;

  String roleLabel(UserRole role) {
    return switch (role) {
      UserRole.orderEntry => t(en: 'Order Entry User', ar: 'مدخل الطلبات'),
      UserRole.reviewer => t(en: 'Order Reviewer', ar: 'مراجع الطلبات'),
      UserRole.shipping => t(en: 'Shipping User', ar: 'مسؤول الشحن'),
      UserRole.admin => t(en: 'Admin', ar: 'مدير النظام'),
      UserRole.viewer => t(en: 'Viewer', ar: 'مستخدم استعراض'),
    };
  }

  String orderStatusLabel(OrderStatus status) {
    return switch (status) {
      OrderStatus.entered => t(en: 'Entered', ar: 'تم الإدخال'),
      OrderStatus.checked => t(en: 'Checked', ar: 'تمت المراجعة'),
      OrderStatus.approved => t(en: 'Approved', ar: 'تم الاعتماد'),
      OrderStatus.shipped => t(en: 'Shipped', ar: 'تم الشحن'),
      OrderStatus.completed => t(en: 'Completed', ar: 'مكتمل'),
      OrderStatus.returned => t(en: 'Returned', ar: 'مرتجع'),
    };
  }

  String orderStatusShort(OrderStatus status) {
    return switch (status) {
      OrderStatus.entered => t(en: 'ENT', ar: 'إدخال'),
      OrderStatus.checked => t(en: 'CHK', ar: 'مراجعة'),
      OrderStatus.approved => t(en: 'APR', ar: 'اعتماد'),
      OrderStatus.shipped => t(en: 'SHP', ar: 'شحن'),
      OrderStatus.completed => t(en: 'CMP', ar: 'تم'),
      OrderStatus.returned => t(en: 'RET', ar: 'رجوع'),
    };
  }

  String permissionLabel(AppPermission permission) {
    return switch (permission) {
      AppPermission.ordersView => t(en: 'View Orders', ar: 'عرض الطلبات'),
      AppPermission.ordersCreate => t(en: 'Create Orders', ar: 'إنشاء الطلبات'),
      AppPermission.ordersEdit => t(en: 'Edit Orders', ar: 'تعديل الطلبات'),
      AppPermission.ordersDelete => t(en: 'Delete Orders', ar: 'حذف الطلبات'),
      AppPermission.ordersApprove => t(en: 'Approve Orders', ar: 'اعتماد الطلبات'),
      AppPermission.ordersShip => t(en: 'Ship Orders', ar: 'شحن الطلبات'),
      AppPermission.ordersOverride =>
        t(en: 'Override Order Flow', ar: 'تجاوز مسار الطلبات'),
      AppPermission.inventoryView => t(en: 'View Inventory', ar: 'عرض المخزون'),
      AppPermission.inventoryEdit => t(en: 'Edit Inventory', ar: 'تعديل المخزون'),
      AppPermission.productsView => t(en: 'View Products', ar: 'عرض المنتجات'),
      AppPermission.productsCreate => t(en: 'Create Products', ar: 'إنشاء المنتجات'),
      AppPermission.productsEdit => t(en: 'Edit Products', ar: 'تعديل المنتجات'),
      AppPermission.productsDelete => t(en: 'Delete Products', ar: 'حذف المنتجات'),
      AppPermission.reportsView => t(en: 'View Reports', ar: 'عرض التقارير'),
      AppPermission.usersView => t(en: 'View Users', ar: 'عرض المستخدمين'),
      AppPermission.usersCreate => t(en: 'Create Users', ar: 'إنشاء المستخدمين'),
      AppPermission.usersEdit => t(en: 'Edit Users', ar: 'تعديل المستخدمين'),
      AppPermission.usersDelete => t(en: 'Delete Users', ar: 'حذف المستخدمين'),
      AppPermission.usersAssignPermissions =>
        t(en: 'Assign Permissions', ar: 'تعيين الصلاحيات'),
      AppPermission.dashboardView =>
        t(en: 'View Dashboard', ar: 'عرض لوحة التحكم'),
      AppPermission.notificationsView => t(en: 'View Notifications', ar: 'عرض الإشعارات'),
      AppPermission.activityLogsView => t(en: 'View Activity Logs', ar: 'عرض سجل النشاط'),
      AppPermission.activityLogsViewAll =>
        t(en: 'View All Activity Logs', ar: 'عرض كل سجلات النشاط'),
      AppPermission.activityLogsCompanyView =>
        t(en: 'View Company Activity Logs', ar: 'عرض سجل نشاط الشركة'),
    };
  }
}
