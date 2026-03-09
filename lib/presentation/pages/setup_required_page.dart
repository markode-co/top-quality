import 'package:flutter/material.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_ethernet_outlined, size: 44),
                  const SizedBox(height: 18),
                  Text(
                    context.t(
                      en: 'Supabase Configuration Required',
                      ar: 'يلزم إعداد Supabase',
                    ),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t(
                      en: 'This build no longer includes demo data. Start the app with real Supabase credentials using --dart-define for SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY, or use the compatible NEXT_PUBLIC_* names. Legacy SUPABASE_ANON_KEY remains supported. Then apply the SQL migration and deploy the employee management edge function.',
                      ar: 'هذا الإصدار لا يحتوي على بيانات تجريبية. شغّل التطبيق ببيانات Supabase الحقيقية عبر --dart-define لـ SUPABASE_URL و SUPABASE_PUBLISHABLE_KEY أو باستخدام NEXT_PUBLIC_* المتوافقة. لا يزال SUPABASE_ANON_KEY مدعومًا. بعد ذلك طبّق ترحيلات SQL وانشر دالة إدارة الموظفين.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
