import 'package:flutter/material.dart';

import '../services/tag_store.dart';

class ManageTagsDialog extends StatefulWidget {
  final TagStore tagStore;
  final String songFileName;

  const ManageTagsDialog({
    super.key,
    required this.tagStore,
    required this.songFileName,
  });

  @override
  State<ManageTagsDialog> createState() => _ManageTagsDialogState();
}

class _ManageTagsDialogState extends State<ManageTagsDialog> {
  final _newTagCtrl = TextEditingController();
  List<String> _all = [];
  Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newTagCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await widget.tagStore.allTags();
    final checked = await widget.tagStore.tagsOf(widget.songFileName);
    if (!mounted) return;
    setState(() {
      _all = all;
      _checked = checked.toSet();
    });
  }

  Future<void> _toggle(String tag, bool? value) async {
    setState(() {
      if (value!) {
        _checked.add(tag);
      } else {
        _checked.remove(tag);
      }
    });
    await widget.tagStore.setTags(widget.songFileName, _checked.toList());
  }

  Future<void> _add() async {
    await widget.tagStore.setTags(
      widget.songFileName,
      [..._checked, _newTagCtrl.text],
    );
    _newTagCtrl.clear();
    await _load();
  }

  Future<void> _showTagMenu(String tag, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
    if (action == 'rename') await _renameTag(tag);
    if (action == 'delete') {
      await widget.tagStore.deleteTag(tag);
      await _load();
    }
  }

  Future<void> _renameTag(String tag) async {
    final controller = TextEditingController(text: tag);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Переименовать «$tag»'),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newName == null) return;
    await widget.tagStore.renameTag(tag, newName);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Управлять тэгами'),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final tag in _all)
              GestureDetector(
                onLongPressStart: (d) => _showTagMenu(tag, d.globalPosition),
                onSecondaryTapUp: (d) => _showTagMenu(tag, d.globalPosition),
                child: CheckboxListTile(
                  value: _checked.contains(tag),
                  onChanged: (v) => _toggle(tag, v),
                  title: Text(tag),
                ),
              ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: 200,
            child: TextField(
              controller: _newTagCtrl,
              decoration: const InputDecoration(hintText: 'Новый тэг'),
            ),
          ),
        ),
        TextButton(
          onPressed: _add,
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
