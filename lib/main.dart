import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/nvr_provider.dart';
import 'providers/task_provider.dart';
import 'screens/dashboard_screen.dart';

import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const CCTVMetaApp());
}

class CCTVMetaApp extends StatelessWidget {
  const CCTVMetaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NvrProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
      ],
      child: MaterialApp(
        title: 'CCTV Command Center',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF1E1E2C),
          colorScheme: const ColorScheme.dark(
            primary: Colors.blueAccent,
            secondary: Colors.redAccent,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF252538),
            elevation: 0,
            centerTitle: true,
          ),
          cardColor: const Color(0xFF252538),
        ),
        home: const DashboardScreen(),
      ),
    );
  }
}
