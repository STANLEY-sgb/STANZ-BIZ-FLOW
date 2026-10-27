import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
  runApp(const ProviderScope(child: BizFlowApp()));
}

class BizFlowApp extends ConsumerWidget {
  const BizFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'STANZ BizFlow',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    themeMode: ThemeMode.light,
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) {
      // Respect large text settings but cap extreme scaling that would break dense POS layouts.
      final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: child!,
      );
    },
  );
}
