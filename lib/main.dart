import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/device_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // The till must keep selling when the network drops. Android caches by
  // default but web doesn't, so we set it explicitly. Unlimited size because
  // evicting the product catalogue mid-day would break offline scanning.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Loads this phone's tag and receipt counter before anything can sell,
  // so the very first sale already has a proper receipt number.
  await DeviceService.instance.init();

  runApp(const DukaPointApp());
}