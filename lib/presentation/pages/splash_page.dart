import 'package:flutter/material.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0C6B58), Color(0xFF0F2B2A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/branding/logo.png',
                  width: 102,
                  height: 102,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.t(en: 'Top Quality', ar: 'توب كواليتي'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(
                width: 180,
                child: LinearProgressIndicator(
                  minHeight: 6,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
