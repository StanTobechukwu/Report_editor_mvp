import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'features/reports/data/letterhead_repository.dart';

import 'features/reports/data/reports_repository.dart';
import 'features/reports/data/templates_repository.dart';
import 'features/reports/providers/report_editor_provider.dart';
import 'features/reports/providers/reports_list_provider.dart';
import 'features/reports/providers/template_list_provider.dart';
import 'features/reports/ui/reports_list_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final reportsRepo = ReportsRepository();
    final templatesRepo = TemplatesRepository();
    final letterheadsRepo = LetterheadsRepository();


    return MultiProvider(
      providers: [
        Provider.value(value: reportsRepo),
        Provider.value(value: templatesRepo),
        Provider.value(value: letterheadsRepo),

        ChangeNotifierProvider(
          create: (_) => ReportEditorProvider(
            repo: reportsRepo,
            templatesRepo: templatesRepo,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ReportsListProvider(repo: reportsRepo)..refresh(),
        ),
        ChangeNotifierProvider(
          create: (_) => TemplateListProvider(repo: templatesRepo)..load(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Reporter MVP',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const ReportsListScreen(),
      ),
    );
  }
}
