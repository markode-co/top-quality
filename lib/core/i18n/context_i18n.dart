import 'package:flutter/material.dart';
import 'package:top_quality/core/constants/app_enums.dart';

extension ContextI18n on BuildContext {
  bool get isArabic =>
      Localizations.localeOf(this).languageCode.toLowerCase() == 'ar';

  String t({required String en, required String ar}) => isArabic ? ar : en;

  String roleLabel(UserRole role) {
    return switch (role) {
      UserRole.orderEntry =>
          t(en: 'Order Entry User', ar: 'مدخل الطلبات'),
      UserRole.reviewer =>
          t(en: 'Order Reviewer', ar: 'مراجع الطلبات'),
      UserRole.shipping =>
          t(en: 'Shipping User', ar: 'مسؤول الشحن'),
      UserRole.admin => t(en: 'Admin', ar: 'مدير النظام'),
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
      OrderStatus.entered => t(en: 'ENT', ar: 'إدخ'),
      OrderStatus.checked => t(en: 'CHK', ar: 'مراج'),
      OrderStatus.approved => t(en: 'APR', ar: 'اعتم'),
      OrderStatus.shipped => t(en: 'SHP', ar: 'شحن'),
      OrderStatus.completed => t(en: 'CMP', ar: 'تم'),
      OrderStatus.returned => t(en: 'RET', ar: 'رجع'),
    };
  }
}
