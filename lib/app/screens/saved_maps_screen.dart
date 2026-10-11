import 'package:flutter/material.dart';

import '../map_library.dart';
import '../theme.dart';
import '../wiring.dart';

/// D33: every recorded map, newest first. Tap a map to make it the one
/// Navigate and the floor map use; rename or delete from its menu.
class SavedMapsScreen extends StatefulWidget {
  const SavedMapsScreen({super.key, this.library});

  /// Tests pass a library over a temporary directory.
  final MapLibrary? library;

  @override
  State<SavedMapsScreen> createState() => _SavedMapsScreenState();
}

class _SavedMapsScreenState extends State<SavedMapsScreen> {
  late final MapLibrary _library =
      widget.library ??
      MapLibrary(documentsDirectory: Wiring.instance.documentsDirectory);
  List<SavedMap>? _maps;
  String? _activeId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final maps = await _library.list();
      final active = await _library.activeId();
      if (!mounted) return;
      setState(() {
        _maps = maps;
        _activeId = active;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read saved maps: $e');
    }
  }

  /// Applies a library change, then reloads the list and the app's map.
  Future<void> _change(Future<void> Function() action) async {
    String? error;
    try {
      await action();
      await Wiring.instance.reloadActiveMap();
    } catch (e) {
      error = '$e';
    }
    await _load();
    if (error != null && mounted) setState(() => _error = error);
  }

  Future<void> _rename(SavedMap saved) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: saved.name),
    );
    if (name == null || name.trim().isEmpty) return;
    await _change(() => _library.rename(saved.id, name));
  }

  Future<void> _delete(SavedMap saved) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${saved.name}"?'),
        content: const Text('This map is removed from the phone.'),
        actions: [
          TextButton(
            key: const ValueKey('delete-no'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('delete-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _change(() => _library.delete(saved.id));
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day}/${t.month} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final maps = _maps;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved maps')),
      body: SafeArea(
        top: false,
        child: maps == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Text(_error!),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  BreadcrumbTheme.screenPadding,
                  8,
                  BreadcrumbTheme.screenPadding,
                  24,
                ),
                children: [
                  Text(
                    maps.isEmpty
                        ? 'No recorded maps yet. Navigate uses the demo map.'
                        : 'Tap a map to use it for Navigate and the floor map.',
                    style: BreadcrumbTheme.bodySecondary,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: BreadcrumbTheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (final saved in maps)
                    _MapTile(
                      saved: saved,
                      active: saved.id == _activeId,
                      when: _when(saved.savedAt),
                      onTap: () => _change(() => _library.setActive(saved.id)),
                      onRename: () => _rename(saved),
                      onDelete: () => _delete(saved),
                    ),
                ],
              ),
      ),
    );
  }
}

class _MapTile extends StatelessWidget {
  const _MapTile({
    required this.saved,
    required this.active,
    required this.when,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final SavedMap saved;
  final bool active;
  final String when;
  final VoidCallback onTap, onRename, onDelete;

  @override
  Widget build(BuildContext context) {
    final places = saved.placeCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey('saved-map-${saved.id}'),
        minTileHeight: BreadcrumbTheme.minTouch,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(
            color: active
                ? BreadcrumbTheme.textPrimary
                : BreadcrumbTheme.border,
          ),
        ),
        selected: active,
        selectedColor: BreadcrumbTheme.textPrimary,
        leading: Icon(
          active ? Icons.radio_button_checked : Icons.radio_button_off,
          color: active
              ? BreadcrumbTheme.textPrimary
              : BreadcrumbTheme.textSecondary,
        ),
        title: Text(
          saved.name,
          style: TextStyle(
            fontSize: 18,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: BreadcrumbTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          '${active ? 'In use · ' : ''}$when · '
          '$places ${places == 1 ? 'place' : 'places'}',
          style: const TextStyle(
            fontSize: 14,
            color: BreadcrumbTheme.textSecondary,
          ),
        ),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          key: ValueKey('saved-map-menu-${saved.id}'),
          tooltip: 'Map options',
          onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

/// Owns its text controller, so it is disposed only after the dialog closes.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename map'),
    content: TextField(
      key: const ValueKey('rename-field'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Map name'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('rename-save'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
