import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:offlinemaps/main.dart';
import 'package:offlinemaps/viewmodels/auth_viewmodel.dart';
import 'package:offlinemaps/download/download_manager.dart';
import 'package:offlinemaps/storage/storage_manager.dart';

void main() {
  testWidgets('Offline Maps smoke test', (WidgetTester tester) async {
    // Build our app with required providers
    final storageManager = StorageManager();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageManager>(create: (_) => storageManager),
          ChangeNotifierProxyProvider<StorageManager, DownloadManager>(
            create: (ctx) => DownloadManager(ctx.read<StorageManager>()),
            update: (_, storage, prev) => prev ?? DownloadManager(storage),
          ),
          ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ],
        child: const OfflineMapsApp(hasSeenIntro: true),
      ),
    );

    // Verify that the Countries screen appears with key UI elements
    expect(find.text('Offline Maps'), findsOneWidget);
    expect(find.byIcon(Icons.public), findsOneWidget); // Globe icon
    expect(find.byIcon(Icons.search), findsOneWidget); // Search icon

    // Let any animations settle
    await tester.pump();
  });
}
