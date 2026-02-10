import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/letterhead_repository.dart';
import '../domain/models/letterhead_template.dart';
import 'letterhead_editor_screen.dart';


class ManageLetterheadsScreen extends StatefulWidget {
  const ManageLetterheadsScreen({super.key});

  @override
  State<ManageLetterheadsScreen> createState() => _ManageLetterheadsScreenState();
}

class _ManageLetterheadsScreenState extends State<ManageLetterheadsScreen> {
  bool _loading = true;
  List<LetterheadTemplate> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<LetterheadsRepository>();
    final list = await repo.listLetterheads(); // implement if not yet
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _createNew() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LetterheadEditorScreen()),
    );
    await _load();
  }

  Future<void> _edit(LetterheadTemplate t) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LetterheadEditorScreen(letterheadId: t.letterheadId),
      ),
    );
    await _load();
  }

  Future<void> _delete(LetterheadTemplate t) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete letterhead?'),
        content: Text('Delete "${t.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (sure != true) return;

    final repo = context.read<LetterheadsRepository>();
    await repo.deleteLetterhead(t.letterheadId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Letterheads'),
        actions: [
          IconButton(
            tooltip: 'Add',
            icon: const Icon(Icons.add),
            onPressed: _createNew,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No letterheads yet. Tap + to create one.'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = _items[i];
                    return ListTile(
                      title: Text(t.name.isEmpty ? '(Unnamed)' : t.name),
                      subtitle: Text(t.headerLine1),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(t),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(t),
                          ),
                        ],
                      ),
                      onTap: () => _edit(t),
                    );
                  },
                ),
    );
  }
}
