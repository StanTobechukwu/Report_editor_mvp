




import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../providers/report_editor_provider.dart';
import '../services/image_services.dart';
import 'report_preview_screen.dart';
import '../ui/signature_capture.dart';

class ReportEditorScreen extends StatefulWidget {
  const ReportEditorScreen({super.key});

  @override
  State<ReportEditorScreen> createState() => _ReportEditorScreenState();
}

class _ReportEditorScreenState extends State<ReportEditorScreen> {
  // Keeps typing stable for Subject Info values.
  final Map<String, TextEditingController> _subjectControllers = {};
  Map<String, String> _subjectErrors = {};

  // Keeps typing stable for ALL content fields.
  final Map<String, TextEditingController> _contentControllers = {};

  // Keeps typing stable for Signer fields.
  late final TextEditingController _roleTitleC;
  late final TextEditingController _signerNameC;
  late final TextEditingController _credentialsC;
  late final TextEditingController _reportTitleC;

  bool _hintShown = false;
  bool _editorMode = false;

  // Spacing constants
  static const _pagePad = 16.0;
  static const _cardPad = 16.0;
  static const _gap = 12.0;
  static const _bigGap = 16.0;

  @override
  void initState() {
    super.initState();
    _roleTitleC = TextEditingController();
    _signerNameC = TextEditingController();
    _credentialsC = TextEditingController();
    _reportTitleC = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in _subjectControllers.values) {
      c.dispose();
    }
    for (final c in _contentControllers.values) {
      c.dispose();
    }
    _roleTitleC.dispose();
    _signerNameC.dispose();
    _credentialsC.dispose();
    _reportTitleC.dispose();
    super.dispose();
  }

  Color _accent(BuildContext context) => Theme.of(context).colorScheme.primary;

  // =========================================================
  // ✅ Run provider mutations AFTER routes/sheets/dialogs close
  // =========================================================
  void _afterClose(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fn();
    });
  }

  // ---------------- Controllers sync ----------------

  TextEditingController _subjectControllerFor(String key, String initial) {
    return _subjectControllers.putIfAbsent(
      key,
      () => TextEditingController(text: initial),
    );
  }

  void _syncSubjectControllers(ReportEditorProvider vm) {
    for (final f in vm.subjectInfoDef.orderedFields) {
      final current = vm.subjectInfoValues.valueOf(f.key);
      final c = _subjectControllerFor(f.key, current);
      if (c.text != current) c.text = current;
    }
  }

  void _syncReportTitleController(ReportEditorProvider vm) {
    final t = vm.doc.reportTitle;
    if (_reportTitleC.text != t) _reportTitleC.text = t;
  }

  TextEditingController _contentControllerFor(String key, String initial) {
    return _contentControllers.putIfAbsent(
      key,
      () => TextEditingController(text: initial),
    );
  }

  void _syncContentControllers(ReportEditorProvider vm) {
    void walkSection(SectionNode s) {
      for (final n in s.children) {
        if (n is ContentNode) {
          final c = _contentControllerFor(n.id, n.text);
          if (c.text != n.text) c.text = n.text;
        } else if (n is SectionNode) {
          walkSection(n);
        }
      }
    }

    for (final r in vm.doc.roots) {
      walkSection(r);
    }
  }

  void _syncSignerControllers(ReportEditorProvider vm) {
    final role = vm.doc.signature.roleTitle;
    if (_roleTitleC.text != role) _roleTitleC.text = role;

    final name = vm.doc.signature.name;
    if (_signerNameC.text != name) _signerNameC.text = name;

    final creds = vm.doc.signature.credentials;
    if (_credentialsC.text != creds) _credentialsC.text = creds;
  }

  Map<String, String> _validateSubjectInfo(ReportEditorProvider vm) {
    final def = vm.subjectInfoDef;
    final values = vm.subjectInfoValues;

    final errors = <String, String>{};
    if (!def.enabled) return errors;

    for (final f in def.orderedFields) {
      if (!f.required) continue;
      final v = values.valueOf(f.key).trim();
      if (v.isEmpty) errors[f.key] = 'Required';
    }
    return errors;
  }

  // =========================
  // ✅ Mode switching (safe)
  // =========================
  void _toggleMode(ReportEditorProvider vm) {
    final goingToFormMode = _editorMode == true;
    if (goingToFormMode) {
      vm.ensureFormReady();
      vm.clearSelection();
    }
    setState(() => _editorMode = !_editorMode);
  }

  // ---------------- Dialog helpers ----------------

  Future<String?> _promptText(
    BuildContext context,
    String title, {
    String hint = 'Type…',
  }) async {
    final c = TextEditingController();

    final res = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, c.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    c.dispose();
    return res;
  }

  Future<bool?> askTemplateSaveMode(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save template as'),
        content: const Text(
          'Choose whether to save just the structure, or include the current text content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Structure only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Include content'),
          ),
        ],
      ),
    );
  }

  // ---------------- Subject Info dialogs / sheets ----------------

  Future<void> _addSubjectFieldDialog(ReportEditorProvider vm) async {
    final titleC = TextEditingController();
    bool required = false;

    final res = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add Subject Field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleC,
                decoration: const InputDecoration(
                  labelText: 'Field title (e.g., Address)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: required,
                onChanged: (v) => setLocal(() => required = v ?? false),
                title: const Text('Required'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    final titleText = titleC.text.trim();
    titleC.dispose();

    if (res != true) return;

    _afterClose(() {
      vm.addSubjectField(
        title: titleText.isEmpty ? 'New field' : titleText,
        required: required,
      );
      if (!mounted) return;
      setState(() => _subjectErrors = _validateSubjectInfo(vm));
    });
  }

  Future<void> _editSubjectFieldsSheet(ReportEditorProvider vm) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _SubjectFieldsEditor(vm: vm),
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _subjectErrors = _validateSubjectInfo(vm));
  }

  // ---------------- Global Add (structure) ----------------

  Future<void> _showGlobalAddSheet(BuildContext context, ReportEditorProvider vm) async {
    final hasSelection = vm.selectedNodeId != null;
    final selectedIsSection = vm.selectedIsSection;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Structure')),
            ListTile(
              leading: const Icon(Icons.view_agenda_outlined),
              title: const Text('Add top-level section'),
              onTap: () => Navigator.pop(sheetContext, 'add_top'),
            ),
            if (hasSelection) ...[
              ListTile(
                leading: const Icon(Icons.library_add_outlined),
                title: const Text('Add same-level section'),
                onTap: () => Navigator.pop(sheetContext, 'add_same'),
              ),
              if (selectedIsSection)
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Wrap selected section'),
                  onTap: () => Navigator.pop(sheetContext, 'wrap'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete selected'),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'add_top') {
      final title = await _promptText(context, 'New top-level section');
      if (title != null && title.trim().isNotEmpty) {
        _afterClose(() => vm.addTopLevelSection(title.trim()));
      }
      return;
    }

    if (!hasSelection) return;

    if (action == 'add_same') {
      final title = await _promptText(context, 'New same-level section');
      if (title != null && title.trim().isNotEmpty) {
        _afterClose(() => vm.addSameLevelSection(title.trim()));
      }
      return;
    }

    if (action == 'wrap') {
      final title = await _promptText(context, 'Wrapper section title', hint: 'e.g., Findings');
      if (title != null && title.trim().isNotEmpty) {
        _afterClose(() => vm.wrapSelectedSection(title.trim()));
      }
      return;
    }

    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete selected?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) _afterClose(vm.deleteSelected);
      return;
    }
  }

  // ---------------- Add Here (context) ----------------

  Future<void> _showAddHereSheet(BuildContext context, ReportEditorProvider vm) async {
    if (vm.selectedNodeId == null) return;

    final canSub = vm.canAddSubsectionHere;
    final canContent = vm.canAddContentHere;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Add here')),
            if (canSub)
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_right),
                title: const Text('Add subsection'),
                onTap: () => Navigator.pop(sheetContext, 'subsection'),
              ),
            if (canContent)
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Add content'),
                onTap: () => Navigator.pop(sheetContext, 'content'),
              ),
            if (!canSub && !canContent)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text('Nothing can be added here.'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'subsection') {
      final title = await _promptText(context, 'New subsection');
      if (title != null && title.trim().isNotEmpty) {
        _afterClose(() => vm.addHereSubsection(title.trim()));
      }
      return;
    }

    if (action == 'content') {
      _afterClose(vm.addHereContent);
      return;
    }
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportEditorProvider>();

    _syncSubjectControllers(vm);
    _syncContentControllers(vm);
    _syncSignerControllers(vm);
    _syncReportTitleController(vm);

    if (_editorMode && !_hintShown && vm.doc.roots.isNotEmpty && vm.selectedNodeId == null) {
      _hintShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tip: Tap a section, then use Add here for content/subsections.'),
          ),
        );
      });
    }

    final outlineMinHeight = MediaQuery.of(context).size.height * 0.42;
    final hasSelection = vm.selectedNodeId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editorMode ? 'Editor Mode' : 'Form Mode'),
        actions: [
          IconButton(
            tooltip: _editorMode ? 'Switch to Form Mode' : 'Switch to Editor Mode',
            icon: Icon(_editorMode ? Icons.description_outlined : Icons.edit_note_outlined),
            onPressed: () => _toggleMode(vm),
          ),
          IconButton(
            tooltip: 'Preview',
            icon: const Icon(Icons.preview_outlined),
            onPressed: () {
              vm.ensureFormReady();

              final errs = _validateSubjectInfo(vm);
              if (errs.isNotEmpty) {
                setState(() => _subjectErrors = errs);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please complete required Subject Info fields.')),
                );
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportPreviewScreen()),
              );
            },
          ),
          if (_editorMode)
            IconButton(
              tooltip: 'Save as template',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () async {
                final name = await _promptText(
                  context,
                  'Template name',
                  hint: 'e.g., Upper GI Template',
                );
                if (name == null || name.trim().isEmpty) return;

                final includeContent = await askTemplateSaveMode(context);
                if (includeContent == null) return;

                await vm.saveAsTemplate(
                  name: name.trim(),
                  includeContent: includeContent,
                );

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Template saved')),
                );
              },
            ),
        ],
      ),
      floatingActionButton: _editorMode
          ? Padding(
              padding: EdgeInsets.only(bottom: hasSelection ? 180 : 0),
              child: FloatingActionButton(
                onPressed: () async {
                  if (!hasSelection) {
                    final title = await _promptText(context, 'New top-level section');
                    if (title != null && title.trim().isNotEmpty) {
                      _afterClose(() => vm.addTopLevelSection(title.trim()));
                    }
                  } else {
                    await _showGlobalAddSheet(context, vm);
                  }
                },
                child: Icon(hasSelection ? Icons.tune : Icons.add),
              ),
            )
          : null,
      floatingActionButtonLocation: _editorMode ? FloatingActionButtonLocation.endFloat : null,
      body: GestureDetector(
        onTap: vm.clearSelection,
        child: ListView(
          padding: const EdgeInsets.all(_pagePad),
          children: [
            _reportTitleCard(vm),
            const SizedBox(height: _bigGap),
            _subjectInfoCard(vm),
            const SizedBox(height: _bigGap),
            _card(
              title: _editorMode ? 'Outline' : 'Form',
              emphasized: true,
              minHeight: outlineMinHeight,
              child: _editorMode
                  ? Column(
                      children: [
                        if (vm.doc.roots.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Text('No sections yet. Tap Add to create the first section.'),
                          ),
                        ...vm.doc.roots.map((s) => _sectionWidget(context, vm, s)),
                      ],
                    )
                  : vm.doc.roots.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(
                            children: [
                              const Icon(Icons.edit_note_outlined, size: 42, color: Colors.grey),
                              const SizedBox(height: 12),
                              const Text('No sections yet', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              const Text(
                                'Switch to Edit Mode to start creating your template.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('Go to Edit Mode'),
                                onPressed: () => setState(() => _editorMode = true),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: vm.doc.roots
                              .map((s) => _formSection(context, vm, s))
                              .toList(growable: false),
                        ),
            ),
            const SizedBox(height: _bigGap),
            _imagesCard(context, vm),
            const SizedBox(height: _bigGap),
            _card(title: 'Signer', child: _signerCard(vm)),
          ],
        ),
      ),
    );
  }

  // ---------------- Form Mode UI ----------------

  Widget _formSection(BuildContext context, ReportEditorProvider vm, SectionNode s) {
    final sectionChildren = s.children.whereType<SectionNode>().toList(growable: false);
    final contentChildren = s.children.whereType<ContentNode>().toList(growable: false);

    final leftPad = 12.0 * s.indent;

    final title = Padding(
      padding: EdgeInsets.only(left: leftPad, bottom: 8),
      child: Text(s.title, style: Theme.of(context).textTheme.titleMedium),
    );

    if (sectionChildren.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _bigGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            ...sectionChildren.map((c) => _formSection(context, vm, c)),
          ],
        ),
      );
    }

    if (contentChildren.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _bigGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            Padding(
              padding: EdgeInsets.only(left: leftPad),
              child: const SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Preparing field…'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final node = contentChildren.first;
    final c = _contentControllerFor(node.id, node.text);

    return Padding(
      padding: const EdgeInsets.only(bottom: _bigGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          Padding(
            padding: EdgeInsets.only(left: leftPad),
            child: TextField(
              controller: c,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter text…',
                isDense: true,
              ),
              onChanged: (v) => vm.updateContent(node.id, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportTitleCard(ReportEditorProvider vm) {
    return _card(
      title: 'Report',
      child: TextField(
        controller: _reportTitleC,
        decoration: const InputDecoration(
          labelText: 'Report Title / Topic',
          hintText: 'e.g., Upper GI Endoscopy Report',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: vm.setReportTitle,
      ),
    );
  }

  Widget _subjectInfoCard(ReportEditorProvider vm) {
    final def = vm.subjectInfoDef;

    if (!def.enabled) {
      return _card(
        title: 'Subject Info',
        child: Row(
          children: [
            const Expanded(child: Text('Subject Info is disabled.')),
            FilledButton(
              onPressed: () => vm.setSubjectInfoEnabled(true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
    }

    final fields = def.orderedFields;

    final fieldWidgets = fields.map((f) {
      final current = vm.subjectInfoValues.valueOf(f.key);
      final c = _subjectControllerFor(f.key, current);
      final err = _subjectErrors[f.key];

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: f.required ? '${f.title} *' : f.title,
            errorText: err,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) {
            vm.updateSubjectInfoValue(f.key, v);
            if (_subjectErrors.isNotEmpty) {
              setState(() => _subjectErrors = _validateSubjectInfo(vm));
            }
          },
        ),
      );
    }).toList(growable: false);

    Widget body;
    if (def.columns == 2) {
      body = LayoutBuilder(
        builder: (context, c) {
          final half = (c.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 0,
            children: fieldWidgets.map((w) => SizedBox(width: half, child: w)).toList(),
          );
        },
      );
    } else {
      body = Column(children: fieldWidgets);
    }

    return _card(
      title: 'Subject Info',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: def.enabled,
                    onChanged: vm.setSubjectInfoEnabled,
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 col')),
                      ButtonSegment(value: 2, label: Text('2 col')),
                    ],
                    selected: {def.columns},
                    onSelectionChanged: (s) => vm.setSubjectInfoColumns(s.first),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () => _editSubjectFieldsSheet(vm),
                icon: const Icon(Icons.tune),
                label: const Text('Fields'),
              ),
              FilledButton.icon(
                onPressed: () => _addSubjectFieldDialog(vm),
                icon: const Icon(Icons.add),
                label: const Text('Add field'),
              ),
            ],
          ),
          const SizedBox(height: _bigGap),
          body,
        ],
      ),
    );
  }

  // ---------------- Outline widgets ----------------

  Widget _sectionWidget(BuildContext context, ReportEditorProvider vm, SectionNode section) {
    final accent = _accent(context);

    final selected = vm.selectedNodeId == section.id;
    final hasChildren = section.children.isNotEmpty;

    final sectionIndent = section.indent * 16.0;

    final titleStyle = TextStyle(
      fontWeight: section.style.bold ? FontWeight.w800 : FontWeight.w600,
      fontSize: section.style.level == HeadingLevel.h1
          ? 18
          : section.style.level == HeadingLevel.h2
              ? 16
              : 14,
    );

    final titleAlign = switch (section.style.align) {
      TitleAlign.left => Alignment.centerLeft,
      TitleAlign.center => Alignment.center,
      TitleAlign.right => Alignment.centerRight,
    };

    final sectionHasContent = section.children.any((n) => n is ContentNode);
    final showAddHere = selected && (vm.canAddSubsectionHere || vm.canAddContentHere);
    final showDeleteContent = selected && sectionHasContent;

    return Padding(
      padding: EdgeInsets.only(left: sectionIndent, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: selected ? accent.withOpacity(0.10) : accent.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => vm.selectNode(section.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    if (hasChildren)
                      InkWell(
                        onTap: () => vm.toggleCollapsed(section.id),
                        child: Icon(section.collapsed ? Icons.chevron_right : Icons.expand_more),
                      )
                    else
                      const SizedBox(width: 24),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Align(
                        alignment: titleAlign,
                        child: Text(section.title, style: titleStyle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (selected)
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Edit section',
                        onPressed: () => _showSectionEditMenu(context, vm, section),
                      )
                    else
                      const Icon(Icons.touch_app_outlined, size: 18, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Row(
                children: [
                  if (showAddHere)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showAddHereSheet(context, vm),
                        icon: const Icon(Icons.add),
                        label: const Text('Add here'),
                      ),
                    ),
                  if (showDeleteContent) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _afterClose(vm.deleteContentForSelectedSection),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete content'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (!section.collapsed)
            ...section.children.map((child) {
              if (child is ContentNode) {
                final contentLeft = sectionIndent + 24;
                final c = _contentControllerFor(child.id, child.text);

                return Padding(
                  padding: EdgeInsets.only(left: contentLeft, top: 8),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => vm.selectNode(section.id),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: TextField(
                          controller: c,
                          minLines: 2,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Enter text…',
                          ),
                          onChanged: (v) => vm.updateContent(child.id, v),
                        ),
                      ),
                    ),
                  ),
                );
              }

              if (child is SectionNode) return _sectionWidget(context, vm, child);

              return const SizedBox.shrink();
            }),
        ],
      ),
    );
  }

  Future<void> _showSectionEditMenu(
    BuildContext context,
    ReportEditorProvider vm,
    SectionNode section,
  ) async {
    final res = await showModalBottomSheet<_SectionEditResult>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _SectionEditSheet(section: section),
    );
    if (res == null) return;

    _afterClose(() {
      if (res.rename != null && res.rename!.trim().isNotEmpty) {
        vm.renameSection(section.id, res.rename!.trim());
      }
      if (res.style != null) {
        vm.updateSectionStyle(section.id, res.style!);
      }
    });
  }

  // ---------------- Other UI blocks ----------------

  Widget _imagesCard(BuildContext context, ReportEditorProvider vm) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: const Text('Images'),
        subtitle: Text(
          'Selected: ${vm.doc.images.length} • '
          'Mode: ${vm.doc.placementChoice == ImagePlacementChoice.inlinePage1 ? "Inline enabled (max 12)" : "Attachments only (max 8)"}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openImagesManager(context, vm),
      ),
    );
  }

  Future<void> _openImagesManager(BuildContext context, ReportEditorProvider vm) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _ImagesManager(vm: vm),
        ),
      ),
    );
  }

  Widget _signerCard(ReportEditorProvider vm) {
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Title (e.g., Reporter, Endoscopist, Radiologist)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          controller: _roleTitleC,
          onChanged: (v) => vm.updateSigner(roleTitle: v),
        ),
        const SizedBox(height: _gap),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          controller: _signerNameC,
          onChanged: (v) => vm.updateSigner(name: v),
        ),
        const SizedBox(height: _gap),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Credentials (optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          controller: _credentialsC,
          onChanged: (v) => vm.updateSigner(credentials: v),
        ),
        const SizedBox(height: _gap),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final path = await Navigator.push<String?>(
                    context,
                    MaterialPageRoute(builder: (_) => const SignatureCaptureScreen()),
                  );
                  if (path != null) {
                    _afterClose(() => vm.setSignatureFilePath(path));
                  }
                },
                icon: const Icon(Icons.draw_outlined),
                label: Text(
                  vm.doc.signature.signatureFilePath == null ? 'Add Signature' : 'Update Signature',
                ),
              ),
            ),
          ],
        ),
        if (vm.doc.signature.signatureFilePath != null) ...[
          const SizedBox(height: _gap),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(vm.doc.signature.signatureFilePath!),
              height: 110,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ],
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    bool emphasized = false,
    double? minHeight,
  }) {
    final border = emphasized
        ? BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.7), width: 1)
        : BorderSide.none;

    return Card(
      elevation: emphasized ? 2.5 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: border,
      ),
      child: Padding(
        padding: const EdgeInsets.all(_cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (minHeight != null)
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: child,
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

// ---------------- Subject Fields Editor ----------------

class _SubjectFieldsEditor extends StatefulWidget {
  final ReportEditorProvider vm;
  const _SubjectFieldsEditor({required this.vm});

  @override
  State<_SubjectFieldsEditor> createState() => _SubjectFieldsEditorState();
}

class _SubjectFieldsEditorState extends State<_SubjectFieldsEditor> {
  void _renameDialog(String fieldKey, String currentTitle) {
    final c = TextEditingController(text: currentTitle);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename field'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final t = c.text.trim().isEmpty ? currentTitle : c.text.trim();
              Navigator.pop(dialogContext);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.vm.renameSubjectField(fieldKey, t);
                if (mounted) setState(() {});
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) => c.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final fields = vm.subjectInfoDef.orderedFields;

    // Build the subject fields editor using a Column.  The reorderable list
    // view is wrapped in a ConstrainedBox to ensure it receives a bounded
    // height when displayed in a bottom sheet.  Without this constraint the
    // list would attempt to expand vertically without limit, causing the
    // framework to complain that a Flexible child of a Column has unbounded
    // constraints.  By limiting the maximum height based on the number of
    // fields and the screen height, we ensure the widget always has a finite
    // height and can scroll internally if necessary.
    final screenHeight = MediaQuery.of(context).size.height;
    // Estimate a sensible row height for each field.  ListTile's default
    // height is approximately 56 logical pixels; add extra space for
    // padding/spacers.
    const double rowHeight = 60.0;
    final double listHeight = fields.length * rowHeight;
    // Limit the list height to at most 50% of the available screen height.
    final double maxHeight = screenHeight * 0.5;
    final double constrainedHeight = listHeight < maxHeight ? listHeight : maxHeight;

    return Column(
      // Let the Column expand vertically so its children can receive
      // constraints from the bottom sheet.  Without setting mainAxisSize to
      // max, a Flexible/ConstrainedBox inside a Column with min size can
      // encounter unbounded height constraints.
      mainAxisSize: MainAxisSize.max,
      children: [
        const ListTile(
          title: Text('Subject Fields'),
          subtitle: Text('Add, rename, reorder, set required.'),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            // Provide both a max and min height.  The max height ensures the
            // list doesn't grow indefinitely, while the min height ensures
            // there is space for at least one item when fields is empty.
            maxHeight: constrainedHeight,
            minHeight: 0,
          ),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            itemCount: fields.length,
            onReorder: (oldIndex, newIndex) {
              vm.reorderSubjectFields(oldIndex, newIndex);
              setState(() {});
            },
            itemBuilder: (_, i) {
              final f = fields[i];
              return ListTile(
                key: ValueKey(f.key),
                title: Text(f.title),
                subtitle: Text(f.isSystem ? 'System field' : 'Custom field'),
                leading: const Icon(Icons.drag_handle),
                trailing: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Checkbox(
                      value: f.required,
                      onChanged: (v) {
                        vm.toggleSubjectRequired(f.key, v ?? false);
                        setState(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit),
                      onPressed: () => _renameDialog(f.key, f.title),
                    ),
                    if (!f.isSystem)
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          vm.removeSubjectField(f.key);
                          setState(() {});
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// ---------------- Section edit sheet ----------------

class _SectionEditResult {
  final String? rename;
  final TitleStyle? style;
  const _SectionEditResult({this.rename, this.style});
}

class _SectionEditSheet extends StatefulWidget {
  final SectionNode section;
  const _SectionEditSheet({required this.section});

  @override
  State<_SectionEditSheet> createState() => _SectionEditSheetState();
}

class _SectionEditSheetState extends State<_SectionEditSheet> {
  late final TextEditingController _title;
  late HeadingLevel _level;
  late bool _bold;
  late TitleAlign _align;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.section.title);
    _level = widget.section.style.level;
    _bold = widget.section.style.bold;
    _align = widget.section.style.align;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Edit section')),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<HeadingLevel>(
                    value: _level,
                    decoration: const InputDecoration(
                      labelText: 'Size',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: HeadingLevel.values
                        .map((h) => DropdownMenuItem(value: h, child: Text(h.name.toUpperCase())))
                        .toList(),
                    onChanged: (v) => setState(() => _level = v ?? _level),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<TitleAlign>(
                    value: _align,
                    decoration: const InputDecoration(
                      labelText: 'Align',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: TitleAlign.values
                        .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _align = v ?? _align),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              value: _bold,
              onChanged: (v) => setState(() => _bold = v),
              title: const Text('Bold title'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  _SectionEditResult(
                    rename: _title.text.trim(),
                    style: widget.section.style.copyWith(
                      level: _level,
                      bold: _bold,
                      align: _align,
                    ),
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Images Manager ----------------

class _ImagesManager extends StatefulWidget {
  final ReportEditorProvider vm;
  const _ImagesManager({required this.vm});

  @override
  State<_ImagesManager> createState() => _ImagesManagerState();
}

class _ImagesManagerState extends State<_ImagesManager> {
  final _imageService = ImageService();

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(title: Text('Images')),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<ImagePlacementChoice>(
                segments: const [
                  ButtonSegment(
                    value: ImagePlacementChoice.attachmentsOnly,
                    label: Text('Attachments only'),
                  ),
                  ButtonSegment(
                    value: ImagePlacementChoice.inlinePage1,
                    label: Text('Inline Page 1'),
                  ),
                ],
                selected: {vm.doc.placementChoice},
                onSelectionChanged: (s) {
                  try {
                    vm.setPlacementChoice(s.first);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Max images in this mode: ${vm.doc.maxImages}'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    final files = await _imageService.pickMultiFromGallery();
                    if (files.isEmpty) return;
                    vm.addImages(files.map((f) => f.path).toList());
                    setState(() {});
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    final file = await _imageService.pickFromCamera();
                    if (file == null) return;
                    vm.addImages([file.path]);
                    setState(() {});
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (vm.doc.images.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No images added yet.'),
          )
        else
          // Wrap the grid view in a ConstrainedBox to ensure it has a bounded
          // height.  Without this constraint the Flexible widget would be
          // provided with unbounded height inside a bottom sheet, leading to
          // an assertion error.  We compute the approximate height based on
          // the number of rows in the grid and limit it to half of the
          // available screen height so that the sheet doesn't overflow.
          Builder(builder: (context) {
            final int crossAxisCount = 3;
            final int itemCount = vm.doc.images.length;
            final int rowCount = (itemCount / crossAxisCount).ceil();
            // Each tile is roughly 100 pixels high plus spacing; adjust as needed.
            const double tileHeight = 110.0;
            // Compute the full height for all rows including spacing.
            final double computedHeight = rowCount * tileHeight + (rowCount - 1) * 8.0;
            final double maxHeight = MediaQuery.of(context).size.height * 0.5;
            final double gridHeight = computedHeight < maxHeight ? computedHeight : maxHeight;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: gridHeight,
                minHeight: 0,
              ),
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: itemCount,
                gridDelegate:  SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (_, i) {
                  final img = vm.doc.images[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(img.filePath),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(6),
                            minimumSize: const Size(32, 32),
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            vm.removeImage(img.id);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          }),
      ],
    );
  }
}
