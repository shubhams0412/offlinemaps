import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/vector_map_screen.dart';
import 'screens/countries_screen.dart';
import 'screens/intro_screen.dart';
import 'data/india_states.dart';
import 'models/map_region.dart';


import 'views/search_screen.dart';
import 'views/download_maps_screen.dart';
import 'views/saved_locations_screen.dart';
import 'views/settings_screen.dart';

import 'viewmodels/auth_viewmodel.dart';
import 'download/download_manager.dart';
import 'storage/storage_manager.dart';
import 'services/offline_manager.dart';
import 'services/valhalla_setup_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Setup Valhalla (Copy assets, update config and initialize)
  await ValhallaSetupService.setup();

  final storageManager = StorageManager();
  final downloadedIds = await storageManager.getDownloadedRegionIds();
  MapRegion? initialRegion;

  if (downloadedIds.isNotEmpty) {
    // Try to find the full MapRegion object (priority to India states)
    final firstId = downloadedIds.first;
    initialRegion = kIndiaStates.cast<MapRegion?>().firstWhere(
      (r) => r?.id == firstId,
      orElse: () => MapRegion(
        id: firstId,
        name: firstId.replaceAll('_', ' ').split(' ').map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '').join(' '),
        centerLat: 0.0,
        centerLng: 0.0,
        size: 'Unknown',
        mbtilesPath: '',
      ),
    );
  }

  // Check if we have seen the intro screen
  final prefs = await SharedPreferences.getInstance();
  final hasSeenIntro = prefs.getBool('has_seen_intro') ?? false;

  runApp(
    MultiProvider(
      providers: [
        // ── New offline download system ────────────────────────────────────
        Provider<StorageManager>(create: (_) => storageManager),
        ChangeNotifierProvider(create: (_) => OfflineManager()),
        ChangeNotifierProxyProvider<StorageManager, DownloadManager>(
          create: (ctx) => DownloadManager(ctx.read<StorageManager>()),
          update: (_, storage, prev) => prev ?? DownloadManager(storage),
        ),

        // ── Legacy ViewModels ──────────────────────────────────────────────
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
      ],
      child: OfflineMapsApp(
        hasSeenIntro: hasSeenIntro,
        initialRegion: initialRegion,
      ),
    ),
  );
}

class OfflineMapsApp extends StatelessWidget {
  final bool hasSeenIntro;
  final MapRegion? initialRegion;
  
  const OfflineMapsApp({
    super.key,
    required this.hasSeenIntro,
    this.initialRegion,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Maps India',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF141922),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4C8DFF),
          secondary: Color(0xFF00C48C),
          surface: Color(0xFF1B2330),
          onSurface: Colors.white,
          surfaceContainer: Color(0xFF202938),
          outline: Color(0xFF2B3647),
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141922),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: Colors.white70, size: 22),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1B2330),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1B2330),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2B3647), width: 0.5),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2B3647),
          thickness: 0.5,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white70,
          ),
        ),
      ),
      // ── Dynamic Entry Point ──────────────────────────────────────────────
      home: initialRegion != null 
          ? VectorMapScreen(region: initialRegion!)
          : (hasSeenIntro ? const CountriesScreen() : const IntroScreen()),

      // ── Legacy routes ──────────────────────────────────────────────────────
      routes: {
        '/search': (context) => const SearchScreen(),
        '/downloads': (context) => const DownloadMapsScreen(),
        '/saved': (context) => const SavedLocationsScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
