import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../reports/data/letterhead_repository.dart';
import '../../reports/domain/models/letterhead_template.dart';
import '../../../core/utils/ids.dart';

class LetterheadEditorScreen extends StatefulWidget {
  final String? letterheadId; // null => create

  const LetterheadEditorScreen({super.key, this.letterheadId});

  @override
  State<LetterheadEditorScreen> createState() => _LetterheadEditorScreenState();
}

class _LetterheadEditorScreenState extends State<LetterheadEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  late LetterheadTemplate _model;

  late final TextEditingController _nameC;
  late final TextEditingController _h1C;
  late final TextEditingController _h2C;
  late final TextEditingController _h3C;
  late final TextEditingController _fLeftC;
  late final TextEditingController _fRightC;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
    _h1C = TextEditingController();
    _h2C = TextEditingController();
    _h3C = TextEditingController();
    _fLeftC = TextEditingController();
    _fRightC = TextEditingController();

    _boot();
  }

  @override
  void dispose() {
    _nameC.dispose();
    _h1C.dispose();
    _h2C.dispose();
    _h3C.dispose();
    _fLeftC.dispose();
    _fRightC.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final repo = context.read<LetterheadsRepository>();

    if (widget.letterheadId == null) {
      _model = LetterheadTemplate(
        letterheadId: newId('lhd'),
        name: '',
      );
      _applyModelToControllers();
      setState(() => _loading = false);
      return;
    }

    try {
      final loaded = await repo.loadLetterhead(widget.letterheadId!);
      _model = loaded;
      _applyModelToControllers();
    } catch (e) {
      // fallback: new
      _model = LetterheadTemplate(
        letterheadId: widget.letterheadId!,
        name: '',
      );
      _applyModelToControllers();
    }

    setState(() => _loading = false);
  }

  void _applyModelToControllers() {
    _nameC.text = _model.name;
    _h1C.text = _model.headerLine1;
    _h2C.text = _model.headerLine2;
    _h3C.text = _model.headerLine3;
    _fLeftC.text = _model.footerLeft;
    _fRightC.text = _model.footerRight;
  }

  Future<void> _pickLogo() async {
    final repo = context.read<LetterheadsRepository>();

    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;

    // copy into app folder so it persists
    final imported = await repo.importLogoFile(
      sourcePath: x.path,
      letterheadId: _model.letterheadId,
    );

    setState(() {
      _model = _model.copyWith(logoFilePath: imported);
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _saving = true);

    final repo = context.read<LetterheadsRepository>();

    final updated = _model.copyWith(
      name: _nameC.text.trim(),
      headerLine1: _h1C.text.trim(),
      headerLine2: _h2C.text.trim(),
      headerLine3: _h3C.text.trim(),
      footerLeft: _fLeftC.text.trim(),
      footerRight: _fRightC.text.trim(),
    );

    await repo.saveLetterhead(updated);

    if (!mounted) return;
    setState(() {
      _model = updated;
      _saving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Letterhead saved')),
    );

    Navigator.pop(context, updated.letterheadId);
  }

  Future<void> _delete() async {
    final repo = context.read<LetterheadsRepository>();

    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete letterhead?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (sure != true) return;

    await repo.deleteLetterhead(_model.letterheadId);

    if (!mounted) return;
    Navigator.pop(context, '__deleted__');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasLogo = _model.logoFilePath != null && File(_model.logoFilePath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.letterheadId == null ? 'New Letterhead' : 'Edit Letterhead'),
        actions: [
          if (widget.letterheadId != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            tooltip: 'Save',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            title: 'Logo',
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: hasLogo
                        ? Image.file(File(_model.logoFilePath!), fit: BoxFit.cover)
                        : const Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Choose logo'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _card(
            title: 'Alignment',
            child: SegmentedButton<LetterheadLogoAlignment>(
              segments: const [
                ButtonSegment(value: LetterheadLogoAlignment.left, label: Text('Left')),
                ButtonSegment(value: LetterheadLogoAlignment.center, label: Text('Center')),
                ButtonSegment(value: LetterheadLogoAlignment.right, label: Text('Right')),
              ],
              selected: {_model.logoAlign},
              onSelectionChanged: (s) {
                setState(() => _model = _model.copyWith(logoAlign: s.first));
              },
            ),
          ),
          const SizedBox(height: 12),

          Form(
            key: _formKey,
            child: _card(
              title: 'Text',
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameC,
                    decoration: const InputDecoration(
                      labelText: 'Letterhead name (e.g., My Clinic)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _h1C,
                    decoration: const InputDecoration(
                      labelText: 'Header line 1 (Hospital/Company)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _h2C,
                    decoration: const InputDecoration(
                      labelText: 'Header line 2 (Address)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _h3C,
                    decoration: const InputDecoration(
                      labelText: 'Header line 3 (Phone/Email)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _fLeftC,
                          decoration: const InputDecoration(
                            labelText: 'Footer left',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _fRightC,
                          decoration: const InputDecoration(
                            labelText: 'Footer right',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
          _card(
            title: 'Preview (simple)',
            child: _miniPreview(context),
          ),
        ],
      ),
    );
  }

  Widget _miniPreview(BuildContext context) {
    final align = switch (_model.logoAlign) {
      LetterheadLogoAlignment.left => CrossAxisAlignment.start,
      LetterheadLogoAlignment.center => CrossAxisAlignment.center,
      LetterheadLogoAlignment.right => CrossAxisAlignment.end,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisAlignment: _model.logoAlign == LetterheadLogoAlignment.left
                ? MainAxisAlignment.start
                : _model.logoAlign == LetterheadLogoAlignment.center
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.end,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: const Icon(Icons.image_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_h1C.text.trim().isNotEmpty) Text(_h1C.text.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
          if (_h2C.text.trim().isNotEmpty) Text(_h2C.text.trim()),
          if (_h3C.text.trim().isNotEmpty) Text(_h3C.text.trim()),
          const SizedBox(height: 10),
          Divider(color: Theme.of(context).dividerColor),
          Row(
            children: [
              Expanded(child: Text(_fLeftC.text.trim(), overflow: TextOverflow.ellipsis)),
              Expanded(
                child: Text(
                  _fRightC.text.trim(),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
