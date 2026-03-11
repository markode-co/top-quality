import 'package:firebase_core/firebase_core.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/firebase_options.dart';

class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static AppMode get mode => AppMode.live;

  static bool get isConfigured => true;

  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
