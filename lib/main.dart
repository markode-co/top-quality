import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_constants.dart';
import 'package:top_quality/core/services/supabase_storage.dart';
import 'package:top_quality/core/theme/app_theme.dart';
import 'package:top_quality/modules/auth/presentation/pages/login_page.dart';
import 'package:top_quality/presentation/pages/app_shell.dart';
import 'package:top_quality/presentation/pages/splash_page.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseStorageBootstrap.initialize();

  runApp(const ProviderScope(child: WarehouseApp()));
}

class WarehouseApp extends ConsumerWidget {
  const WarehouseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocale = ref.watch(appLocaleProvider);
    final appThemeMode = ref.watch(appThemeModeProvider);

    return MaterialApp(
      title: AppConstants.appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: appThemeMode,
      locale: appLocale,
      supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AppRoot(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Scale UI gently based on shortest side (phones vs tablets) with safe clamps.
        final shortest = mq.size.shortestSide;
        final scale = (shortest / 430).clamp(0.85, 1.15);
        // textScaler.scale(1) يعطينا عامل التكبير الحالي (بدون الاعتماد على textScaleFactor المتوقف)
        final baseScale = mq.textScaler.scale(1);
        final textScale = TextScaler.linear(
          (baseScale * scale).clamp(0.9, 1.15),
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: textScale),
          child: IconTheme(
            data: IconTheme.of(context).copyWith(size: 22 * scale),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      data: (user) {
        return user == null ? const LoginPage() : const AppShell();
      },
      loading: () => const SplashPage(),
      error: (error, _) =>
          Scaffold(body: Center(child: Text(error.toString()))),
    );
  }
}
