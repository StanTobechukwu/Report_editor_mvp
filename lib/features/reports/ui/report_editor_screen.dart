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

  // Keeps typing stable for Signer fields.
  late final TextEditingController _roleTitleC;
  late final TextEditingController _signerNameC;
  late final TextEditingController _credentialsC;

  bool _hintShown = false;

  @override
  void initState() {
    super.initState();
    _roleTitleC = TextEditingController();
    _signerNameC = TextEditingController();
    _credentialsC = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in _subjectControllers.values) {
      c.dispose();
    }
    _roleTitleC.dispose();
    _signerNameC.dispose();
    _credentialsC.dispose();
    super.dispose();
  }

  Color _accent(BuildContext context) => Theme.of(context).colorScheme.primary;

  TextEditingController _controllerFor(String key, String initial) {
    return _subjectControllers.putIfAbsent(
      key,
      () => TextEditingController(text: initial),
    );
  }

  void _syncSubjectControllers(ReportEditorProvider vm) {
    for (final f in vm.subjectInfoDef.orderedFields) {
      final current = vm.subjectInfoValues.valueOf(f.key);
      final c = _controllerFor(f.key, current);
      if (c.text != current) c.text = current;
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

  // ---------------- Dialogs / Sheets ----------------

  Future<void> _addSubjectFieldDialog(ReportEditorProvider vm) async {
    final titleC = TextEditingController();
    bool required = false;

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
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
                ),
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
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    final titleText = titleC.text.trim();
    titleC.dispose();

    if (res != true) return;

    vm.addSubjectField(
      title: titleText.isEmpty ? 'New field' : titleText,
      required: required,
    );
  }

  Future<void> _editSubjectFieldsSheet(ReportEditorProvider vm) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _SubjectFieldsEditor(vm: vm),
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _subjectErrors = _validateSubjectInfo(vm));
  }

  Future<String?> _promptText(BuildContext context, String title, {String hint = 'Type a name…'}) async {
    final c = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Add')),
        ],
      ),
    );
    c.dispose();
    return res;
  }
// function for saving template based on user choice
  Future<bool?> askTemplateSaveMode(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      title: const Text('Save template as'),
      content: const Text(
        'Choose whether to save just the structure, or include the current text content.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Structure only'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Include content'),
        ),
      ],
    ),
  );
}


  // ---------------- Global Add (fixed) ----------------

  Future<void> _showGlobalAddSheet(BuildContext context, ReportEditorProvider vm) async {
    final hasSelection = vm.selectedNodeId != null;
    final selectedIsSection = vm.selectedIsSection;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Structure')),
            ListTile(
              leading: const Icon(Icons.view_agenda_outlined),
              title: const Text('Add top-level section'),
              onTap: () => Navigator.pop(context, 'add_top'),
            ),
            if (hasSelection) ...[
              ListTile(
                leading: const Icon(Icons.library_add_outlined),
                title: const Text('Add same-level section'),
                onTap: () => Navigator.pop(context, 'add_same'),
              ),
              if (selectedIsSection)
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Wrap selected section'),
                  onTap: () => Navigator.pop(context, 'wrap'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete selected'),
                onTap: () => Navigator.pop(context, 'delete'),
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
      if (title != null && title.trim().isNotEmpty) vm.addTopLevelSection(title);
      return;
    }

    if (!hasSelection) return;

    if (action == 'add_same') {
      final title = await _promptText(context, 'New same-level section');
      if (title != null && title.trim().isNotEmpty) {
        vm.addSameLevelSection(title);
      }
      return;
    }

    if (action == 'wrap') {
      final title = await _promptText(context, 'Wrapper section title', hint: 'e.g., Findings');
      if (title != null && title.trim().isNotEmpty) {
        vm.wrapSelectedSection(title);
      }
      return;
    }

    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete selected?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) vm.deleteSelected();
      return;
    }
  }

  // ---------------- Add Here (context) ----------------

  Future<void> _showAddHereSheet(BuildContext context, ReportEditorProvider vm) async {
    if (vm.selectedNodeId == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Add here')),
            ListTile(
              leading: const Icon(Icons.subdirectory_arrow_right),
              title: const Text('Add subsection'),
              onTap: () => Navigator.pop(context, 'subsection'),
            ),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Add content'),
              onTap: () => Navigator.pop(context, 'content'),
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
        vm.addHereSubsection(title);
      }
      return;
    }

    if (action == 'content') {
      vm.addHereContent();
      return;
    }
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportEditorProvider>();
    _syncSubjectControllers(vm);
    _syncSignerControllers(vm);

    if (!_hintShown && vm.doc.roots.isNotEmpty && vm.selectedNodeId == null) {
      _hintShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tip: Tap a section, then use Add here for content/subsections.')),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Editor'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              final errs = _validateSubjectInfo(vm);
              if (errs.isNotEmpty) {
                setState(() => _subjectErrors = errs);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please complete required Subject Info fields.')),
                );
                return;
              }

              await vm.save();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved')),
              );
            },
          ),
          IconButton(
            tooltip: 'Preview',
            icon: const Icon(Icons.preview_outlined),
            onPressed: () {
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
          IconButton(
  tooltip: 'Save as template',
  icon: const Icon(Icons.bookmark_add_outlined),
  onPressed: () async {
    final name = await _promptText(context, 'Template name', hint: 'e.g., Upper GI Template');
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

      // ✅ Global Add is FIXED and always useful.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGlobalAddSheet(context, vm),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),

      body: GestureDetector(
        onTap: vm.clearSelection,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _subjectInfoCard(vm),
            const SizedBox(height: 12),

            _card(
              title: 'Outline',
              child: Column(
                children: [
                  if (vm.doc.roots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('No sections yet. Tap Add to create the first section.'),
                    ),
                  ...vm.doc.roots.map((s) => _sectionWidget(context, vm, s)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _imagesCard(context, vm),
            const SizedBox(height: 12),

            _card(title: 'Signer', child: _signerCard(vm)),
          ],
        ),
      ),
    );
  }

  // ---------------- Subject Info UI ----------------

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
      final c = _controllerFor(f.key, current);
      final err = _subjectErrors[f.key];

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: f.required ? '${f.title} *' : f.title,
            errorText: err,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            vm.updateSubjectInfoValue(f.key, v);
            if (_subjectErrors.isNotEmpty) {
              setState(() => _subjectErrors = _validateSubjectInfo(vm));
            }
          },
        ),
      );
    }).toList();

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
          // ✅ Wrap prevents buttons going off-screen.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: def.enabled,
                    onChanged: vm.setSubjectInfoEnabled,
                  ),
                  const SizedBox(width: 6),
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
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  // ---------------- Outline widgets ----------------

  Widget _contextAddHereButton(BuildContext context, ReportEditorProvider vm) {
    final accent = _accent(context);
    return Padding(
      padding: const EdgeInsets.only(left: 40, top: 6),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: accent),
        onPressed: () => _showAddHereSheet(context, vm),
        icon: const Icon(Icons.add),
        label: const Text('Add here'),
      ),
    );
  }

  Widget _sectionWidget(BuildContext context, ReportEditorProvider vm, SectionNode section) {
    final indent = (section.indent) * 16.0;
    final selected = vm.selectedNodeId == section.id;
    final hasChildren = section.children.isNotEmpty;
    final accent = _accent(context);

    final style = TextStyle(
      fontWeight: section.style.bold ? FontWeight.w800 : FontWeight.w600,
      fontSize: section.style.level == HeadingLevel.h1
          ? 18
          : section.style.level == HeadingLevel.h2
              ? 16
              : 14,
    );

    final align = switch (section.style.align) {
      TitleAlign.left => Alignment.centerLeft,
      TitleAlign.center => Alignment.center,
      TitleAlign.right => Alignment.centerRight,
    };

    return Padding(
      padding: EdgeInsets.only(left: indent, top: 8),
      child: Column(
        children: [
          Material(
            color: selected ? accent.withOpacity(0.10) : Colors.transparent,
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
                        alignment: align,
                        child: Text(section.title, style: style),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () => _showSectionEditMenu(context, vm, section),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ✅ Add Here = only subsection/content logic
          if (selected) _contextAddHereButton(context, vm),

          if (!section.collapsed)
            ...section.children.map((child) {
              if (child is ContentNode) {
                final childIndent = (child.indent) * 16.0;
                final contentSelected = vm.selectedNodeId == child.id;

                return Padding(
                  padding: EdgeInsets.only(left: childIndent + 26, top: 8),
                  child: Column(
                    children: [
                      Material(
                        color: contentSelected ? accent.withOpacity(0.07) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => vm.selectNode(child.id),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: TextField(
                              controller: TextEditingController(text: child.text)
                                ..selection = TextSelection.collapsed(offset: child.text.length),
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

                      // ✅ If content is selected, Add Here still works (adds siblings)
                      if (contentSelected) _contextAddHereButton(context, vm),
                    ],
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

  // ---------------- Other UI blocks ----------------

  Widget _imagesCard(BuildContext context, ReportEditorProvider vm) {
    return Card(
      child: ListTile(
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
      builder: (_) => SafeArea(
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
          ),
          controller: _roleTitleC,
          onChanged: (v) => vm.updateSigner(roleTitle: v),
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          controller: _signerNameC,
          onChanged: (v) => vm.updateSigner(name: v),
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Credentials (optional)',
            border: OutlineInputBorder(),
          ),
          controller: _credentialsC,
          onChanged: (v) => vm.updateSigner(credentials: v),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final path = await Navigator.push<String?>(
                    context,
                    MaterialPageRoute(builder: (_) => const SignatureCaptureScreen()),
                  );
                  if (path != null) vm.setSignatureFilePath(path);
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
          const SizedBox(height: 10),
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

  Widget _card({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _showSectionEditMenu(BuildContext context, ReportEditorProvider vm, SectionNode section) async {
    final res = await showModalBottomSheet<_SectionEditResult>(
      context: context,
      showDragHandle: true,
      builder: (_) => _SectionEditSheet(section: section),
    );
    if (res == null) return;

    if (res.rename != null && res.rename!.trim().isNotEmpty) {
      vm.renameSection(section.id, res.rename!);
    }
    if (res.style != null) {
      vm.updateSectionStyle(section.id, res.style!);
    }
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
      builder: (_) => AlertDialog(
        title: const Text('Rename field'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = c.text.trim().isEmpty ? currentTitle : c.text.trim();
              widget.vm.renameSubjectField(fieldKey, t);
              Navigator.pop(context);
              setState(() {});
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(
          title: Text('Subject Fields'),
          subtitle: Text('Add, rename, reorder, set required.'),
        ),
        Flexible(
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
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<HeadingLevel>(
                    value: _level,
                    decoration: const InputDecoration(labelText: 'Size'),
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
                    decoration: const InputDecoration(labelText: 'Align'),
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
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  _SectionEditResult(
                    rename: _title.text.trim(),
                    style: widget.section.style.copyWith(level: _level, bold: _bold, align: _align),
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
                  ButtonSegment(value: ImagePlacementChoice.attachmentsOnly, label: Text('Attachments only')),
                  ButtonSegment(value: ImagePlacementChoice.inlinePage1, label: Text('Inline Page 1')),
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
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: vm.doc.images.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
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
          ),
      ],
    );
  }
}
