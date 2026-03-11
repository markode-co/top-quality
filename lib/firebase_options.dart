import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return web; // fallback
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBV5BwtK4deaLIJxn-ylClbv_E8URqQK0o',
    appId: '1:1001852847766:web:c76201b837e9b399d5a4b7',
    messagingSenderId: '1001852847766',
    projectId: 'top-quality-2a1a4',
    storageBucket: 'top-quality-2a1a4.firebasestorage.app',
    authDomain: 'top-quality-2a1a4.firebaseapp.com',
    databaseURL: 'https://top-quality-2a1a4-default-rtdb.firebaseio.com',
    measurementId: 'G-17XLZS3GHD',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBXS3Nk70xHS942c1VVcbX_KAuzrQLHvY4',
    appId: '1:1001852847766:android:9d88bb24524fdad6d5a4b7',
    messagingSenderId: '1001852847766',
    projectId: 'top-quality-2a1a4',
    storageBucket: 'top-quality-2a1a4.firebasestorage.app',
    databaseURL: 'https://top-quality-2a1a4-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBjJwLAuiCfJNb8mnGoUbIdZaBWkzHcxxY',
    appId: '1:1001852847766:ios:d5e4b0b265414eb7d5a4b7',
    messagingSenderId: '1001852847766',
    projectId: 'top-quality-2a1a4',
    storageBucket: 'top-quality-2a1a4.firebasestorage.app',
    databaseURL: 'https://top-quality-2a1a4-default-rtdb.firebaseio.com',
    iosClientId: '1001852847766-9uoepkgac4koc199egvehqv066b3l0ed.apps.googleusercontent.com',
    iosBundleId: 'com.example.topquality',
  );
}
