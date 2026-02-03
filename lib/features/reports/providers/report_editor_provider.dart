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

  SubjectInfoBlockDef get subjectInfoDef => _doc.subjectInfoDef;
  SubjectInfoValues get subjectInfoValues => _doc.subjectInfo;

  bool get selectedIsSection {
    final id = _selectedNodeId;
    if (id == null) return false;
    return _findNodeById(_doc.roots, id) is SectionNode;
  }

  bool get selectedIsContent {
    final id = _selectedNodeId;
    if (id == null) return false;
    return _findNodeById(_doc.roots, id) is ContentNode;
  }

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
void newReportFromTemplate(TemplateDoc template) {
  final now = nowIso();

  _doc = ReportDoc(
    reportId: newId('rpt'),
    createdAtIso: now,
    updatedAtIso: now,

    // 🔥 FIX 1: deep clone
    roots: template.roots
        .map((s) => s.cloneNodeTree())
        .toList(growable: false),

    images: const [],
    placementChoice: ImagePlacementChoice.attachmentsOnly,
    signature: const SignatureBlock(),

    subjectInfoDef: template.subjectInfo,

    // 🔥 FIX 2: safe value initialization
    subjectInfo: SubjectInfoValues.emptyFromDef(template.subjectInfo),
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
    final target = fields.firstWhere(
      (f) => f.key == fieldKey,
      orElse: () => const SubjectFieldDef(key: '', title: '', required: false, order: 0, isSystem: false),
    );
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

    final nextFields = _doc.subjectInfoDef.fields.map((f) {
      return f.key == fieldKey ? f.copyWith(title: t) : f;
    }).toList();

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: nextFields),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

  void toggleSubjectRequired(String fieldKey, bool required) {
    final nextFields = _doc.subjectInfoDef.fields.map((f) {
      return f.key == fieldKey ? f.copyWith(required: required) : f;
    }).toList();

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

  Future<void> saveAsTemplate({
  required String name,
  required bool includeContent,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return;

  final t = TemplateDoc(
    templateId: newId('tpl'),
    updatedAt: DateTime.now(),
    name: trimmed,

    // structure OR structure+content
    roots: _doc.roots
        .map((r) => r.toTemplateNode(includeContent: includeContent))
        .toList(growable: false),

    subjectInfo: _doc.subjectInfoDef,
  );

  await templatesRepo.saveTemplate(t);
}


  // =========================
  // Tree: IDs
  // =========================

  String _id(String prefix) => newId(prefix);

  // =========================
  // Tree: Global Add (structure)
  // =========================

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

  /// Add same-level section after the selected node.
  /// - If selected is root section: insert in roots.
  /// - If selected is nested section/content: insert as sibling under the same parent section.
  void addSameLevelSection(String title) {
    final t = title.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final newSec = SectionNode(id: _id('sec'), title: t);

    final nextRoots = _insertSibling(_doc.roots, targetId, newSec);
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    notifyListeners();
  }

  /// Wrap selected SECTION in a new parent SECTION.
  /// - Only works if selected is SectionNode.
  /// - Wrapper replaces the selected node in place.
  /// - Slight auto-indentation applied (child subtree indent +1).
  void wrapSelectedSection(String wrapperTitle) {
    final t = wrapperTitle.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final node = _findNodeById(_doc.roots, targetId);
    if (node is! SectionNode) return;

    final wrappedChild = _shiftIndentSectionSubtree(node, 1);

    final wrapper = SectionNode(
      id: _id('sec'),
      title: t,
      indent: node.indent,
      children: [wrappedChild],
      collapsed: false,
      style: node.style, // keeps consistent style; adjust later if desired
    );

    final nextRoots = _replaceNode(_doc.roots, targetId, wrapper);
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    notifyListeners();
  }

  /// Delete selected node (section or content).
  void deleteSelected() {
    final targetId = _selectedNodeId;
    if (targetId == null) return;

    final nextRoots = _deleteNode(_doc.roots, targetId);
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    _selectedNodeId = null;
    notifyListeners();
  }

  // =========================
  // Tree: Add Here (context)
  // =========================
  //
  // Rules:
  // If selected node is SectionNode:
  //   - Add subsection => CHILD SectionNode
  //   - Add content    => CHILD ContentNode
  //
  // If selected node is ContentNode:
  //   - Add subsection => SIBLING SectionNode (same parent)
  //   - Add content    => SIBLING ContentNode (same parent)

  void addHereSubsection(String title) {
    final t = title.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final selected = _findNodeById(_doc.roots, targetId);
    final newSec = SectionNode(id: _id('sec'), title: t);

    if (selected is SectionNode) {
      // child
      _doc = _doc.copyWith(
        roots: _updateSectionTree(
          _doc.roots,
          targetId,
          (s) => s.copyWith(children: [...s.children, newSec], collapsed: false),
        ),
        updatedAtIso: nowIso(),
      );
      notifyListeners();
      return;
    }

    if (selected is ContentNode) {
      // sibling
      final nextRoots = _insertSibling(_doc.roots, targetId, newSec);
      _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
      notifyListeners();
      return;
    }
  }

  void addHereContent({String initialText = ''}) {
    final targetId = _selectedNodeId;
    if (targetId == null) return;

    final selected = _findNodeById(_doc.roots, targetId);
    final newTxt = ContentNode(id: _id('txt'), text: initialText);

    if (selected is SectionNode) {
      // child
      _doc = _doc.copyWith(
        roots: _updateSectionTree(
          _doc.roots,
          targetId,
          (s) => s.copyWith(children: [...s.children, newTxt], collapsed: false),
        ),
        updatedAtIso: nowIso(),
      );
      notifyListeners();
      return;
    }

    if (selected is ContentNode) {
      // sibling
      final nextRoots = _insertSibling(_doc.roots, targetId, newTxt);
      _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
      notifyListeners();
      return;
    }
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
  // Tree helpers (existing)
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

  // =========================
  // Tree helpers (NEW)
  // =========================

  Node? _findNodeById(List<SectionNode> roots, String id) {
    for (final s in roots) {
      if (s.id == id) return s;
      final found = _findNodeInChildren(s.children, id);
      if (found != null) return found;
    }
    return null;
  }

  Node? _findNodeInChildren(List<Node> children, String id) {
    for (final n in children) {
      if (n.id == id) return n;
      if (n is SectionNode) {
        final found = _findNodeInChildren(n.children, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Insert sibling after a target node id (works for roots + nested).
  List<SectionNode> _insertSibling(List<SectionNode> roots, String targetId, Node newNode) {
    // root-level insert
    for (int i = 0; i < roots.length; i++) {
      if (roots[i].id == targetId && newNode is SectionNode) {
        final next = [...roots];
        next.insert(i + 1, newNode);
        return next;
      }
    }

    // nested insert
    return roots.map((s) => s.copyWith(children: _insertSiblingInChildren(s.children, targetId, newNode))).toList();
  }

  List<Node> _insertSiblingInChildren(List<Node> children, String targetId, Node newNode) {
    for (int i = 0; i < children.length; i++) {
      final n = children[i];
      if (n.id == targetId) {
        final next = [...children];
        next.insert(i + 1, newNode);
        return next;
      }
      if (n is SectionNode) {
        final updated = _insertSiblingInChildren(n.children, targetId, newNode);
        if (!identical(updated, n.children)) {
          final next = [...children];
          next[i] = n.copyWith(children: updated);
          return next;
        }
      }
    }
    return children;
  }

  /// Replace a node (root or nested) by id.
  List<SectionNode> _replaceNode(List<SectionNode> roots, String targetId, SectionNode replacement) {
    // root replace
    for (int i = 0; i < roots.length; i++) {
      if (roots[i].id == targetId) {
        final next = [...roots];
        next[i] = replacement;
        return next;
      }
    }

    // nested replace
    return roots.map((s) => s.copyWith(children: _replaceNodeInChildren(s.children, targetId, replacement))).toList();
  }

  List<Node> _replaceNodeInChildren(List<Node> children, String targetId, SectionNode replacement) {
    for (int i = 0; i < children.length; i++) {
      final n = children[i];
      if (n.id == targetId) {
        final next = [...children];
        next[i] = replacement;
        return next;
      }
      if (n is SectionNode) {
        final updated = _replaceNodeInChildren(n.children, targetId, replacement);
        if (!identical(updated, n.children)) {
          final next = [...children];
          next[i] = n.copyWith(children: updated);
          return next;
        }
      }
    }
    return children;
  }

  /// Delete a node (root or nested) by id.
  List<SectionNode> _deleteNode(List<SectionNode> roots, String targetId) {
    // root delete
    final rootIndex = roots.indexWhere((s) => s.id == targetId);
    if (rootIndex != -1) {
      final next = [...roots]..removeAt(rootIndex);
      return next;
    }

    // nested delete
    return roots.map((s) => s.copyWith(children: _deleteNodeInChildren(s.children, targetId))).toList();
  }

  List<Node> _deleteNodeInChildren(List<Node> children, String targetId) {
    final idx = children.indexWhere((n) => n.id == targetId);
    if (idx != -1) {
      final next = [...children]..removeAt(idx);
      return next;
    }

    // recurse
    for (int i = 0; i < children.length; i++) {
      final n = children[i];
      if (n is SectionNode) {
        final updated = _deleteNodeInChildren(n.children, targetId);
        if (!identical(updated, n.children)) {
          final next = [...children];
          next[i] = n.copyWith(children: updated);
          return next;
        }
      }
    }

    return children;
  }

  /// Shift indent for an entire section subtree (including nested children)
  SectionNode _shiftIndentSectionSubtree(SectionNode node, int delta) {
    int clampIndent(int v) => v.clamp(0, 20);

    Node shift(Node n) {
      if (n is ContentNode) return n.copyWith(indent: clampIndent(n.indent + delta));
      if (n is SectionNode) {
        final nextChildren = n.children.map(shift).toList();
        return n.copyWith(
          indent: clampIndent(n.indent + delta),
          children: nextChildren,
        );
      }
      return n;
    }

    return shift(node) as SectionNode;
  }
}
