// Hand-written to match the shape `flutterfire configure` generates, using
// the app configs from the Firebase console (Project settings). Android
// hasn't been registered in the Firebase project yet — register it in the
// console (or via `flutterfire configure`) and add its block here when
// that happens.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for Android — '
          'register an Android app in the Firebase console (or run '
          '`flutterfire configure`) and add its block here.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA-Q-yh-5nwFWfohiPnrw3TqcIkQoAfpO8',
    appId: '1:38768521060:web:b87022264b3abf23a81471',
    messagingSenderId: '38768521060',
    projectId: 'farming-game-5c14c',
    authDomain: 'farming-game-5c14c.firebaseapp.com',
    storageBucket: 'farming-game-5c14c.firebasestorage.app',
    measurementId: 'G-15C7T22L00',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCp6XL4Lb4kq7CL25QRi0pOfYSvGgWrTss',
    appId: '1:38768521060:ios:d06f343fce1c086ba81471',
    messagingSenderId: '38768521060',
    projectId: 'farming-game-5c14c',
    storageBucket: 'farming-game-5c14c.firebasestorage.app',
    iosBundleId: 'com.harryludemann.farminggame',
  );
}
