import 'package:intl/intl.dart';
import 'package:top_quality/core/constants/app_constants.dart';

class AppFormatters {
  const AppFormatters._();

  static String _resolveLocale(String? locale) {
    if (locale == null || locale.trim().isEmpty) {
      return 'ar_EG';
    }
    final normalized = locale.replaceAll('-', '_');
    if (normalized.startsWith('en')) return 'en_US';
    if (normalized.startsWith('ar')) return 'ar_EG';
    return normalized;
  }

  static String currency(double value, [String? locale]) {
    final resolvedLocale = _resolveLocale(locale);
    return NumberFormat.currency(
      locale: resolvedLocale,
      symbol: '${AppConstants.currencyCode} ',
      decimalDigits: 2,
    ).format(value);
  }

  static String shortDate(DateTime value, [String? locale]) {
    final resolvedLocale = _resolveLocale(locale);
    return DateFormat('dd MMM yyyy', resolvedLocale).format(value.toLocal());
  }

  static String shortDateTime(DateTime value, [String? locale]) {
    final resolvedLocale = _resolveLocale(locale);
    return DateFormat('dd MMM yyyy, hh:mm a', resolvedLocale)
        .format(value.toLocal());
  }

  static String compact(num value, [String? locale]) {
    final resolvedLocale = _resolveLocale(locale);
    return NumberFormat.compact(locale: resolvedLocale).format(value);
  }
}
