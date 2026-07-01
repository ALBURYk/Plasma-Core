import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/researcher_workspace_screen.dart';
import 'theme/plasma_theme.dart';

class PlasmaCoreApp extends StatelessWidget {
  const PlasmaCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plasma Core',
      debugShowCheckedModeBanner: false,
      theme: buildPlasmaTheme(),
      home: const ResearcherWorkspaceScreen(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/researcher': (context) => const ResearcherWorkspaceScreen(),
      },
    );
  }
}
