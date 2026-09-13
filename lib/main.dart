import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'engine/game_store.dart';
import 'firebase_options.dart';
import 'widgets/connection_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FarmSimApp());
}

class FarmSimApp extends StatelessWidget {
  // Injectable for tests (`firebase_auth_mocks` / `fake_cloud_firestore`) —
  // real runs fall back to the live Firebase singletons.
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  const FarmSimApp({super.key, this.auth, this.firestore});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameStore(auth: auth, firestore: firestore),
      child: MaterialApp(
        title: 'Farm Sim',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: const ConnectionGate(),
      ),
    );
  }
}
