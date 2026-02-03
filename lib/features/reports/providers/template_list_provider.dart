import 'package:flutter/foundation.dart';
import '../data/templates_repository.dart';

class TemplateListProvider extends ChangeNotifier {
  final TemplatesRepository repo;

  TemplateListProvider({required this.repo});

  List<TemplateSummary> _templates = [];
  bool _loading = false;

  List<TemplateSummary> get templates => _templates;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    _templates = await repo.listTemplates();

    _loading = false;
    notifyListeners();
  }

  Future<void> delete(String templateId) async {
    await repo.deleteTemplate(templateId);
    await load();
  }
}
