import 'dart:math';
import 'package:flutter/foundation.dart';

import '../domain/models/template_doc.dart';
import '../domain/models/subject_info_def.dart';
import '../domain/models/nodes.dart';


class TemplateEditorProvider extends ChangeNotifier {
  TemplateDoc _template;

  TemplateEditorProvider(this._template);

  TemplateDoc get template => _template;
  SubjectInfoBlockDef get subjectInfo => _template.subjectInfo;

  // ---------- block settings ----------
  void toggleSubjectInfo(bool enabled) {
    _template = _template.copyWith(
      subjectInfo: subjectInfo.copyWith(enabled: enabled),
    );
    notifyListeners();
  }
  void setSubjectInfoColumns(int columns) {
  final safe = (columns == 2) ? 2 : 1;
  _template = _template.copyWith(
    subjectInfo: subjectInfo.copyWith(columns: safe),
  );
  notifyListeners();
}


  // ---------- field edits ----------
  void renameField(String fieldId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    final updated = subjectInfo.fields
        .map((f) => f.key == fieldId ? f.copyWith(title: t) : f)
        .toList();

    _updateFields(updated);
  }

  void toggleRequired(String fieldId, bool required) {
    final updated = subjectInfo.fields
        .map((f) => f.key == fieldId ? f.copyWith(required: required) : f)
        .toList();

    _updateFields(updated);
  }

  void addCustomField({String title = 'Custom Field', bool required = false}) {
    final order = _nextOrder(subjectInfo.fields);
    final fieldId = _generateCustomFieldId();

    final field = SubjectFieldDef(
      key: fieldId,
      title: title,
      required: required,
      order: order,
      isSystem: false,
    );

    _updateFields([...subjectInfo.fields, field]);
  }

  void removeField(String fieldId) {
    final field = subjectInfo.fields.firstWhere((f) => f.key == fieldId);
    if (field.isSystem) return; // protect stable system fields

    _updateFields(subjectInfo.fields.where((f) => f.key != fieldId).toList());
  }

  /// Reorder fields in the template UI (ReorderableListView)
  void reorderFields(int oldIndex, int newIndex) {
    final list = [...subjectInfo.fields]..sort((a, b) => a.order.compareTo(b.order));

    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex > list.length) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final resequenced = <SubjectFieldDef>[];
    for (int i = 0; i < list.length; i++) {
      resequenced.add(list[i].copyWith(order: i));
    }

    _updateFields(resequenced);
  }
  // ---------- save/export ----------
  /// Builds a TemplateDoc ready for persistence.
  ///
  /// includeContent:
  ///  - false: structure only (SectionNodes only)
  ///  - true : include ContentNode text (SectionNodes + ContentNodes)
  ///
  /// Images are never part of TemplateDoc, so they are excluded automatically.
  TemplateDoc buildForSave({
    required String name,
    required bool includeContent,
  }) {
    final trimmed = name.trim();

    return _template.copyWith(
      name: trimmed.isEmpty ? _template.name : trimmed,
      updatedAt: DateTime.now(),
      roots: _template.roots
          .map((r) => r.toTemplateNode(includeContent: includeContent))
          .toList(growable: false),
      subjectInfo: _template.subjectInfo,
    );
  }

  // ---------- internal ----------
  void _updateFields(List<SubjectFieldDef> fields) {
    _template = _template.copyWith(
      subjectInfo: subjectInfo.copyWith(fields: fields),
    );
    notifyListeners();
  }

  int _nextOrder(List<SubjectFieldDef> fields) {
    if (fields.isEmpty) return 0;
    final maxOrder = fields.map((f) => f.order).reduce((a, b) => a > b ? a : b);
    return maxOrder + 1;
  }

  String _generateCustomFieldId() {
    final r = Random();
    final chunk = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
    return 'custom_$chunk';
  }
}
