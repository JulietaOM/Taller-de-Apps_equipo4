import 'package:flutter/material.dart';
import 'features/ecg/presentation/screens/profile_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heartbeat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFF78B94),
      ),
      home: const ProfileScreen(),
    );
  }
}
