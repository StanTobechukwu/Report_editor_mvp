import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/report_editor_provider.dart';

class SubjectInfoBlock extends StatefulWidget {
  const SubjectInfoBlock({super.key});

  @override
  State<SubjectInfoBlock> createState() => _SubjectInfoBlockState();
}

class _SubjectInfoBlockState extends State<SubjectInfoBlock> {
  final Map<String, TextEditingController> _controllers = {};
  Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key, String initial) {
    return _controllers.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  void _syncControllers(ReportEditorProvider vm) {
    for (final f in vm.subjectInfoDef.fields) {
      final text = vm.subjectInfoValues.valueOf(f.key);
      final c = _controllerFor(f.key, text);
      if (c.text != text) c.text = text;
    }
  }

  Map<String, String> _validate(ReportEditorProvider vm) {
    final errors = <String, String>{};
    if (!vm.subjectInfoDef.enabled) return errors;

    for (final f in vm.subjectInfoDef.fields) {
      if (!f.required) continue;
      if (vm.subjectInfoValues.valueOf(f.key).trim().isEmpty) {
        errors[f.key] = 'Required';
      }
    }
    return errors;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReportEditorProvider>(
      builder: (context, vm, _) {
        if (!vm.subjectInfoDef.enabled) return const SizedBox.shrink();

        _syncControllers(vm);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Subject Info',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _errors = _validate(vm)),
                      child: const Text('Validate'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                ...vm.subjectInfoDef.fields.map((f) {
                  final controller = _controllerFor(f.key, vm.subjectInfoValues.valueOf(f.key));
                  final error = _errors[f.key];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: f.required ? '${f.title} *' : f.title,
                        errorText: error,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        vm.updateSubjectInfoValue(f.key, v);
                        if (_errors.isNotEmpty) {
                          setState(() => _errors = _validate(vm));
                        }
                      },
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }
}
