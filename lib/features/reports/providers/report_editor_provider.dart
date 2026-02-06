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

/// ✅ NEW RULES:
/// - Subsections can ALWAYS be added to a SectionNode (even if it already has intro content)
/// - Content can be added only if the section has NO content yet (max 1 content per section)
bool get canAddSubsectionHere {
  final id = _selectedNodeId;
  if (id == null) return false;
  final n = _findNodeById(_doc.roots, id);
  return n is SectionNode;
}

bool get canAddContentHere {
  final id = _selectedNodeId;
  if (id == null) return false;
  final n = _findNodeById(_doc.roots, id);
  if (n is! SectionNode) return false;

  // ✅ one content per section (intro OR leaf content)
  

  return true;
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

    // 1) Deep-clone template structure
    final cloned = template.roots.map((s) => s.cloneNodeTree()).toList(growable: false);

    // 2) Hydrate leaf sections with exactly one content node (Form Mode)
    final hydrated = cloned.map(_hydrateTemplateSectionForForm).toList(growable: false);

    _doc = ReportDoc(
      reportId: newId('rpt'),
      createdAtIso: now,
      updatedAtIso: now,
      roots: hydrated,
      images: const [],
      placementChoice: ImagePlacementChoice.attachmentsOnly,
      signature: const SignatureBlock(),
      subjectInfoDef: template.subjectInfo,
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
  // ✅ Form Mode helper
  // =========================

  /// Ensures a leaf section has exactly ONE ContentNode.
  /// Safe to call repeatedly (no duplicates created).
  void ensureLeafHasContent(String sectionId) {
    final s = _findSectionById(_doc.roots, sectionId);
    if (s == null) return;

    // only leaf sections get content
    if (_sectionHasSectionChildren(s)) return;

    final contentNodes = s.children.whereType<ContentNode>().toList();
    if (contentNodes.isNotEmpty) {
      // already has one -> enforce exactly one by keeping first
      if (contentNodes.length == 1 && s.children.length == 1) return;

      final keep = contentNodes.first;
      _doc = _doc.copyWith(
        roots: _updateSectionTree(
          _doc.roots,
          sectionId,
          (sec) => sec.copyWith(children: [keep], collapsed: false),
        ),
        updatedAtIso: nowIso(),
      );
      notifyListeners();
      return;
    }

    // create one
    final newTxt = ContentNode(id: _id('txt'), text: '', indent: s.indent);
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (sec) => sec.copyWith(children: [newTxt], collapsed: false),
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
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
      orElse: () => const SubjectFieldDef(
        key: '',
        title: '',
        required: false,
        order: 0,
        isSystem: false,
      ),
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

  // =========================
  // Template save (ok as-is)
  // =========================

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
      roots: _doc.roots
          .map((r) => r.toTemplateNode(includeContent: includeContent))
          .toList(growable: false),
      subjectInfo: _doc.subjectInfoDef,
    );

    await templatesRepo.saveTemplate(t);
  }

  // =========================
  // Template -> Report hydration (Form Mode)
  // =========================

  SectionNode _hydrateTemplateSectionForForm(SectionNode s) {
    final sectionKids = s.children.whereType<SectionNode>().toList(growable: false);
    if (sectionKids.isNotEmpty) {
      return s.copyWith(
        children: sectionKids.map(_hydrateTemplateSectionForForm).toList(growable: false),
        collapsed: false,
      );
    }

    // Leaf section: keep only the first ContentNode (if any), else create one.
    final firstContent = s.children.whereType<ContentNode>().isNotEmpty
        ? s.children.whereType<ContentNode>().first
        : null;

    final content = firstContent ?? ContentNode(id: _id('txt'), text: '', indent: s.indent);
    return s.copyWith(children: [content], collapsed: false);
  }

  bool _sectionHasSectionChildren(SectionNode s) => s.children.any((n) => n is SectionNode);
  bool _sectionHasContentChild(SectionNode s) => s.children.any((n) => n is ContentNode);

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

  void addSameLevelSection(String title) {
    final t = title.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final newSec = SectionNode(id: _id('sec'), title: t);

    final selected = _findNodeById(_doc.roots, targetId);
    final effectiveTargetId = (selected is ContentNode)
        ? _findOwningSectionId(_doc.roots, targetId) ?? targetId
        : targetId;

    final nextRoots = _insertSibling(_doc.roots, effectiveTargetId, newSec);
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    notifyListeners();
  }

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
      style: node.style,
    );

    final nextRoots = _replaceNode(_doc.roots, targetId, wrapper);
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    notifyListeners();
  }

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

  /// ✅ NEW RULES ENFORCED:
  /// - You can’t add a subsection if the section already has content.
  /// - You can’t add content if the section has subsections.
  /// - Only one content per section.
  /// - Selection being a ContentNode does NOT allow adding more content/subsections.
  void addHereSubsection(String title) {
    final t = title.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final selected = _findNodeById(_doc.roots, targetId);
    if (selected is! SectionNode) return;

    //if (_sectionHasContentChild(selected)) return; // content is final

    final newSec = SectionNode(id: _id('sec'), title: t);

    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        targetId,
        (s) => s.copyWith(children: [...s.children, newSec], collapsed: false),
      ),
      updatedAtIso: nowIso(),
    );
    notifyListeners();
  }

void addHereContent({String initialText = ''}) {
  final targetId = _selectedNodeId;
  if (targetId == null) return;

  final selected = _findNodeById(_doc.roots, targetId);
  if (selected is! SectionNode) return;

  // ✅ only one content per section
  if (_sectionHasContentChild(selected)) return;

  final newTxt = ContentNode(
    id: _id('txt'),
    text: initialText,
    indent: selected.indent,
  );

  _doc = _doc.copyWith(
    roots: _updateSectionTree(
      _doc.roots,
      targetId,
      (s) {
        // ✅ Insert content BEFORE subsections (intro content)
        // If subsections exist, we keep them and put content first.
        // If no subsections, it becomes leaf content.
        final nextChildren = <Node>[newTxt, ...s.children.whereType<SectionNode>()];
        return s.copyWith(children: nextChildren, collapsed: false);
      },
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
// Delete single content node (NEW)
// =========================

/// Removes a ContentNode from its parent section.
/// Used when user taps "Delete content" in outline.
/// Safe: only deletes that content, keeps section.
void deleteContentNode(String contentId) {
  List<Node> walk(List<Node> children) {
    return children.where((n) {
      // remove only the targeted content
      return !(n is ContentNode && n.id == contentId);
    }).map((n) {
      if (n is SectionNode) {
        return n.copyWith(children: walk(n.children));
      }
      return n;
    }).toList();
  }

  _doc = _doc.copyWith(
    roots: _doc.roots.map((s) => s.copyWith(children: walk(s.children))).toList(),
    updatedAtIso: nowIso(),
  );

  // reset selection to avoid stale id
  _selectedNodeId = null;

  notifyListeners();
}
bool get selectedSectionHasContent {
  final id = _selectedNodeId;
  if (id == null) return false;

  final n = _findNodeById(_doc.roots, id);
  if (n is! SectionNode) return false;

  return n.children.any((c) => c is ContentNode);
}

void deleteContentForSelectedSection() {
  final id = _selectedNodeId;
  if (id == null) return;

  final n = _findNodeById(_doc.roots, id);
  if (n is! SectionNode) return;

  _doc = _doc.copyWith(
    roots: _updateSectionTree(
      _doc.roots,
      id,
      (s) {
        final kept = s.children.where((c) => c is! ContentNode).toList();
        return s.copyWith(children: kept, collapsed: false);
      },
    ),
    updatedAtIso: nowIso(),
  );

  notifyListeners();
}


  // =========================
  // Images / Signature (unchanged)
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

  Node? _findNodeById(List<SectionNode> roots, String id) {
    for (final s in roots) {
      if (s.id == id) return s;
      final found = _findNodeInChildren(s.children, id);
      if (found != null) return found;
    }
    return null;
  }

  SectionNode? _findSectionById(List<SectionNode> roots, String id) {
    final n = _findNodeById(roots, id);
    return (n is SectionNode) ? n : null;
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

  String? _findOwningSectionId(List<SectionNode> roots, String nodeId) {
    for (final s in roots) {
      final found = _findOwningSectionIdInSection(s, nodeId);
      if (found != null) return found;
    }
    return null;
  }

  String? _findOwningSectionIdInSection(SectionNode section, String nodeId) {
    for (final n in section.children) {
      if (n.id == nodeId) return section.id;
      if (n is SectionNode) {
        final found = _findOwningSectionIdInSection(n, nodeId);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<SectionNode> _insertSibling(List<SectionNode> roots, String targetId, Node newNode) {
    for (int i = 0; i < roots.length; i++) {
      if (roots[i].id == targetId && newNode is SectionNode) {
        final next = [...roots];
        next.insert(i + 1, newNode);
        return next;
      }
    }

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

  List<SectionNode> _replaceNode(List<SectionNode> roots, String targetId, SectionNode replacement) {
    for (int i = 0; i < roots.length; i++) {
      if (roots[i].id == targetId) {
        final next = [...roots];
        next[i] = replacement;
        return next;
      }
    }

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

  List<SectionNode> _deleteNode(List<SectionNode> roots, String targetId) {
    final rootIndex = roots.indexWhere((s) => s.id == targetId);
    if (rootIndex != -1) {
      final next = [...roots]..removeAt(rootIndex);
      return next;
    }

    return roots.map((s) => s.copyWith(children: _deleteNodeInChildren(s.children, targetId))).toList();
  }

  List<Node> _deleteNodeInChildren(List<Node> children, String targetId) {
    final idx = children.indexWhere((n) => n.id == targetId);
    if (idx != -1) {
      final next = [...children]..removeAt(idx);
      return next;
    }

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
