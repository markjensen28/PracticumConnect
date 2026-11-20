import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'Only the Firebase Web app is configured. Register the Android/iOS apps '
      'in Firebase and run flutterfire configure before building for mobile.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBlGfzBKyXT1RQbODqBA4lj78XbQaBBBfI',
    appId: '1:175291814599:web:401133592c6ac37f3964e2',
    messagingSenderId: '175291814599',
    projectId: 'practicumconnect-aa5d1',
    authDomain: 'practicumconnect-aa5d1.firebaseapp.com',
    databaseURL: 'https://practicumconnect-aa5d1-default-rtdb.firebaseio.com',
    storageBucket: 'practicumconnect-aa5d1.firebasestorage.app',
    measurementId: 'G-ELFDF8YK20',
  );
}
