import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/utils/ids.dart';
import '../../../core/utils/time.dart';

import '../data/reports_repository.dart';
import '../data/templates_repository.dart';

import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/models/template_doc.dart';
import '../domain/models/subject_info_def.dart';
import '../domain/models/subject_info_value.dart';

class ReportEditorProvider extends ChangeNotifier {
  final ReportsRepository repo;
  final TemplatesRepository templatesRepo;

  late ReportDoc _doc;

  /// Selected node can be a SectionNode OR ContentNode id.
  String? _selectedNodeId;

  ReportEditorProvider({
    required this.repo,
    required this.templatesRepo,
  }) {
    newReport();
  }

  // =========================
  // Getters
  // =========================

  ReportDoc get doc => _doc;
  String? get selectedNodeId => _selectedNodeId;

  /// Subject info schema (defs) + values.
  SubjectInfoBlockDef get subjectInfoDef => _doc.subjectInfoDef;
  SubjectInfoValues get subjectInfoValues => _doc.subjectInfo;

  // =========================
  // Selection
  // =========================

  void selectNode(String? id) {
    _selectedNodeId = id;
    notifyListeners();
  }

  void clearSelection() => selectNode(null);

  // =========================
  // Create / Load / Save
  // =========================

  ReportDoc _newEmptyDoc() {
    final now = nowIso();
    return ReportDoc(
      reportId: newId('rpt'),
      createdAtIso: now,
      updatedAtIso: now,
      roots: const [],
      images: const [],
      placementChoice: ImagePlacementChoice.attachmentsOnly,
      signature: const SignatureBlock(),
      subjectInfoDef: SubjectInfoBlockDef.kDefaults,
      subjectInfo: const SubjectInfoValues({}),
    );
  }

  void newReport() {
    _doc = _newEmptyDoc();
    _selectedNodeId = null;
    notifyListeners();
  }

  /// Start report from a template:
  /// - structure from template.roots
  /// - subjectInfoDef from template.subjectInfo
  /// - subjectInfo values start empty
  void newReportFromTemplate(TemplateDoc template) {
    final now = nowIso();
    _doc = ReportDoc(
      reportId: newId('rpt'),
      createdAtIso: now,
      updatedAtIso: now,
      roots: template.roots,
      images: const [],
      placementChoice: ImagePlacementChoice.attachmentsOnly,
      signature: const SignatureBlock(),
      subjectInfoDef: template.subjectInfo,
      subjectInfo: const SubjectInfoValues({}),
    );
    _selectedNodeId = null;
    notifyListeners();
  }

  Future<void> save() async {
    _doc = _doc.copyWith(updatedAtIso: nowIso());
    await repo.saveReport(_doc);
    notifyListeners();
  }

  Future<void> loadById(String reportId) async {
    _doc = await repo.loadReport(reportId);
    _selectedNodeId = null;
    notifyListeners();
  }

  Future<void> loadTemplateAndStartReport(String templateId) async {
    final template = await templatesRepo.loadTemplate(templateId);
    newReportFromTemplate(template);
  }

  // =========================
  // Subject Info (schema + values)
  // =========================

  void updateSubjectInfoValue(String fieldKey, String value) {
    _doc = _doc.copyWith(
      subjectInfo: _doc.subjectInfo.copyWithValue(fieldKey, value),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void setSubjectInfoEnabled(bool enabled) {
    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(enabled: enabled),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void setSubjectInfoColumns(int columns) {
    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(columns: columns),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void addSubjectField({String title = 'New field', bool required = false}) {
    final fields = _doc.subjectInfoDef.fields;
    final nextOrder = _nextOrder(fields);
    final key = _generateCustomFieldKey();

    final field = SubjectFieldDef(
      key: key,
      title: title.trim().isEmpty ? 'New field' : title.trim(),
      required: required,
      order: nextOrder,
      isSystem: false,
    );

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: [...fields, field]),
      subjectInfo: _doc.subjectInfo.copyWithValue(key, ''),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void removeSubjectField(String fieldKey) {
    final fields = _doc.subjectInfoDef.fields;
    final target = fields.firstWhere((f) => f.key == fieldKey, orElse: () => const SubjectFieldDef(key: '', title: '', required: false, order: 0, isSystem: false));
    if (target.key.isEmpty) return;
    if (target.isSystem) return;

    final nextFields = fields.where((f) => f.key != fieldKey).toList();

    final nextValues = Map<String, String>.from(_doc.subjectInfo.values);
    nextValues.remove(fieldKey);

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: nextFields),
      subjectInfo: SubjectInfoValues(nextValues),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void renameSubjectField(String fieldKey, String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    final nextFields = _doc.subjectInfoDef.fields
        .map((f) => f.key == fieldKey ? f.copyWith(title: t) : f)
        .toList();

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: nextFields),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void toggleSubjectRequired(String fieldKey, bool required) {
    final nextFields = _doc.subjectInfoDef.fields
        .map((f) => f.key == fieldKey ? f.copyWith(required: required) : f)
        .toList();

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: nextFields),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void reorderSubjectFields(int oldIndex, int newIndex) {
    final ordered = [..._doc.subjectInfoDef.orderedFields];

    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    if (newIndex < 0 || newIndex > ordered.length) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final item = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, item);

    final resequenced = <SubjectFieldDef>[];
    for (int i = 0; i < ordered.length; i++) {
      resequenced.add(ordered[i].copyWith(order: i));
    }

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: resequenced),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  int _nextOrder(List<SubjectFieldDef> fields) {
    if (fields.isEmpty) return 0;
    final maxOrder = fields.map((f) => f.order).reduce((a, b) => a > b ? a : b);
    return maxOrder + 1;
  }

  String _generateCustomFieldKey() {
    final r = Random();
    final chunk = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
    return 'custom_$chunk';
  }

  // =========================
  // Tree: Add
  // =========================

  String _id(String prefix) => newId(prefix);

  void addTopLevelSection(String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    final sec = SectionNode(id: _id('sec'), title: t);

    _doc = _doc.copyWith(
      roots: [..._doc.roots, sec],
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void addSubsectionUnderSelected(String title) {
    final parentId = _selectedNodeId;
    final t = title.trim();
    if (parentId == null || t.isEmpty) return;

    final child = SectionNode(id: _id('sec'), title: t);

    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        parentId,
        (s) => s.copyWith(
          children: [...s.children, child],
          collapsed: false,
        ),
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void addContentUnderSelected({String initialText = ''}) {
    final parentId = _selectedNodeId;
    if (parentId == null) return;

    final child = ContentNode(id: _id('txt'), text: initialText);

    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        parentId,
        (s) => s.copyWith(
          children: [...s.children, child],
          collapsed: false,
        ),
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  // =========================
  // Tree: Edit
  // =========================

  void toggleCollapsed(String sectionId) {
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(collapsed: !s.collapsed),
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void renameSection(String sectionId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(title: t),
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void updateSectionStyle(String sectionId, TitleStyle style) {
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(style: style),
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void updateContent(String contentId, String text) {
    _doc = _doc.copyWith(
      roots: _updateContentTree(_doc.roots, contentId, text),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  // =========================
  // Indent / Outdent nodes
  // =========================

  void indentNode(String nodeId) => _shiftIndent(nodeId, 1);
  void outdentNode(String nodeId) => _shiftIndent(nodeId, -1);

  void _shiftIndent(String nodeId, int delta) {
    int clampIndent(int v) => v.clamp(0, 20);

    Node transform(Node n) {
      if (n.id == nodeId) {
        if (n is SectionNode) return n.copyWith(indent: clampIndent(n.indent + delta));
        if (n is ContentNode) return n.copyWith(indent: clampIndent(n.indent + delta));
      }

      if (n is SectionNode) {
        final updatedChildren = n.children.map(transform).toList();
        return n.copyWith(children: updatedChildren);
      }

      return n;
    }

    final updatedRoots = _doc.roots.map((s) => transform(s) as SectionNode).toList();

    _doc = _doc.copyWith(
      roots: updatedRoots,
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  // =========================
  // Images
  // =========================

  void setPlacementChoice(ImagePlacementChoice choice) {
    if (choice == ImagePlacementChoice.attachmentsOnly && _doc.images.length > 8) {
      throw Exception('Attachments-only mode allows max 8 images. Remove some images first.');
    }

    _doc = _doc.copyWith(
      placementChoice: choice,
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void addImages(List<String> filePaths) {
    final clean = filePaths.where((p) => p.trim().isNotEmpty).toList();
    if (clean.isEmpty) return;

    final cap = _doc.maxImages;
    if (_doc.images.length + clean.length > cap) {
      throw Exception('Maximum of $cap images allowed for this mode.');
    }

    final newImgs = clean.map((p) => ImageAttachment(id: _id('img'), filePath: p)).toList();

    _doc = _doc.copyWith(
      images: [..._doc.images, ...newImgs],
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void removeImage(String imageId) {
    _doc = _doc.copyWith(
      images: _doc.images.where((i) => i.id != imageId).toList(),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  // =========================
  // Signature / Signer
  // =========================

  void updateSigner({String? roleTitle, String? name, String? credentials}) {
    _doc = _doc.copyWith(
      signature: _doc.signature.copyWith(
        roleTitle: roleTitle,
        name: name,
        credentials: credentials,
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void setSignatureFilePath(String? path) {
    _doc = _doc.copyWith(
      signature: _doc.signature.copyWith(signatureFilePath: path),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  // =========================
  // Tree helpers
  // =========================

  List<SectionNode> _updateSectionTree(
    List<SectionNode> roots,
    String targetId,
    SectionNode Function(SectionNode) updater,
  ) {
    return roots.map((s) => _updateSectionNode(s, targetId, updater)).toList();
  }

  SectionNode _updateSectionNode(
    SectionNode node,
    String targetId,
    SectionNode Function(SectionNode) updater,
  ) {
    var current = node;

    if (node.id == targetId) {
      current = updater(node);
    }

    final updatedChildren = current.children.map((child) {
      if (child is SectionNode) return _updateSectionNode(child, targetId, updater);
      return child;
    }).toList();

    return current.copyWith(children: updatedChildren);
  }

  List<SectionNode> _updateContentTree(
    List<SectionNode> roots,
    String contentId,
    String text,
  ) {
    List<Node> walk(List<Node> children) {
      return children.map((n) {
        if (n is ContentNode && n.id == contentId) {
          return n.copyWith(text: text);
        }
        if (n is SectionNode) {
          return n.copyWith(children: walk(n.children));
        }
        return n;
      }).toList();
    }

    return roots.map((s) => s.copyWith(children: walk(s.children))).toList();
  }
}
