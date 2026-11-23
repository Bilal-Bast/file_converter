import 'package:flutter/material.dart';

import '../models.dart';
import '../services/conversion_service.dart';
import '../services/file_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = ConversionService();
  final List<InputFile> _files = [];
  List<ConversionResult> _results = [];
  OutputFormat? _target;
  bool _mergeImages = true;
  bool _busy = false;
  int _done = 0;
  int _total = 0;

  List<OutputFormat> get _targets => commonTargets(_files);
  bool get _allImages =>
      _files.isNotEmpty && _files.every((f) => f.kind == InputKind.image);
  bool get _canMerge =>
      _allImages && _files.length > 1 && _target == OutputFormat.pdf;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _header(String text) => Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Future<void> _pick() async {
    try {
      final picked = await FileService.pickFiles();
      if (!mounted) return;
      if (picked.skipped.isNotEmpty) {
        _snack('Not supported: ${picked.skipped.join(', ')}');
      }
      if (picked.files.isEmpty) return;
      setState(() {
        _files.addAll(picked.files);
        _results = [];
        _fixTarget();
      });
    } catch (e) {
      _snack('Could not open files: $e');
    }
  }

  void _fixTarget() {
    final targets = _targets;
    if (!targets.contains(_target)) {
      _target = targets.isEmpty ? null : targets.first;
    }
  }

  void _remove(int index) => setState(() {
        _files.removeAt(index);
        _results = [];
        _fixTarget();
      });

  void _clear() => setState(() {
        _files.clear();
        _results = [];
        _target = null;
      });

  Future<void> _convert() async {
    final target = _target;
    if (target == null || _busy) return;
    setState(() {
      _busy = true;
      _results = [];
      _done = 0;
      _total = _files.length;
    });

    final results = await _service.convert(
      List.of(_files),
      target,
      mergeImagesToPdf: _canMerge && _mergeImages,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = results;
    });
    final failed = results.where((r) => !r.ok).length;
    _snack(failed == 0
        ? 'Done! ${results.length} file(s) ready.'
        : '$failed file(s) failed.');
  }

  Future<void> _save(ConvertedFile f) async {
    try {
      final ok = await FileService.save(f);
      if (ok && mounted) _snack('Saved ${f.name}');
    } catch (e) {
      if (mounted) _snack('Save failed: $e');
    }
  }

  Future<void> _saveAll(List<ConvertedFile> files) async {
    try {
      final msg = await FileService.saveAll(files);
      if (msg != null && mounted) _snack(msg);
    } catch (e) {
      if (mounted) _snack('Save failed: $e');
    }
  }

  Future<void> _share(List<ConvertedFile> files) async {
    try {
      await FileService.share(files);
    } catch (e) {
      if (mounted) _snack('Share failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Converter'),
        actions: [
          if (_files.isNotEmpty && !_busy)
            IconButton(
                tooltip: 'Clear all',
                icon: const Icon(Icons.clear_all),
                onPressed: _clear),
        ],
      ),
      floatingActionButton: _files.isEmpty || _busy
          ? null
          : FloatingActionButton.extended(
              onPressed: _pick,
              icon: const Icon(Icons.add),
              label: const Text('Add files'),
            ),
      body: _files.isEmpty ? _emptyState() : _content(),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(
                child: Icon(Icons.swap_horiz_rounded,
                    size: 88, color: scheme.primary)),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text('Convert files offline',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: 8),
            Semantics(
                label:
                    'Supported conversions. E-P-U-B to text or PDF. Word docx to text or PDF. '
                    'Text to PDF. Images, J-P-G, PNG, WEBP, BMP or GIF, to JPG, PNG, BMP or PDF.',
                excludeSemantics: true,
                child: Text(
                  'EPUB → TXT / PDF\nDOCX → TXT / PDF\nTXT → PDF\nJPG · PNG · WEBP · BMP · GIF → JPG / PNG / BMP / PDF',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
                )),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose files'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _content() {
    final theme = Theme.of(context);
    final targets = _targets;
    final successful =
        _results.where((r) => r.ok).map((r) => r.output!).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _header('Selected (${_files.length})'),
        const SizedBox(height: 4),
        Card(
          child: Column(children: [
            for (var i = 0; i < _files.length; i++)
              ListTile(
                leading: Icon(_iconFor(_files[i].kind)),
                title: Text(_files[i].name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatBytes(_files[i].bytes.length)),
                trailing: _busy
                    ? null
                    : IconButton(
                        tooltip: 'Remove ${_files[i].name}',
                        icon: const Icon(Icons.close),
                        onPressed: () => _remove(i),
                      ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        _header('Convert to'),
        const SizedBox(height: 8),
        if (targets.isEmpty)
          Text(
            'These files have no output format in common. Convert them in separate batches.',
            style: TextStyle(color: theme.colorScheme.error),
          )
        else
          Semantics(
            container: true,
            label: 'Output format',
            child: Wrap(spacing: 8, children: [
              for (final t in targets)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _target == t,
                  onSelected: _busy ? null : (_) => setState(() => _target = t),
                ),
            ]),
          ),
        if (_canMerge)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Combine into one PDF'),
            value: _mergeImages,
            onChanged: _busy ? null : (v) => setState(() => _mergeImages = v),
          ),
        const SizedBox(height: 16),
        if (_busy) ...[
          LinearProgressIndicator(
            value: _total == 0 ? null : _done / _total,
            semanticsLabel: 'Conversion progress',
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child:
                Text('Converting ${(_done + 1).clamp(1, _total)} of $_total…'),
          ),
        ] else
          FilledButton.icon(
            onPressed: _target == null ? null : _convert,
            icon: const Icon(Icons.autorenew),
            label: const Text('Convert'),
          ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _header('Results')),
            if (successful.length > 1)
              Wrap(children: [
                TextButton.icon(
                  onPressed: () => _saveAll(successful),
                  icon: const Icon(Icons.download),
                  label: const Text('Save all'),
                ),
                TextButton.icon(
                  onPressed: () => _share(successful),
                  icon: const Icon(Icons.share),
                  label: const Text('Share all'),
                ),
              ]),
          ]),
          Card(
            child: Column(children: [for (final r in _results) _resultTile(r)]),
          ),
        ],
      ],
    );
  }

  Widget _resultTile(ConversionResult r) {
    final scheme = Theme.of(context).colorScheme;
    final out = r.output;
    if (out == null) {
      return Semantics(
        label: 'Failed: ${r.sourceName}. ${r.error ?? ''}',
        excludeSemantics: true,
        child: ListTile(
          leading: Icon(Icons.error_outline, color: scheme.error),
          title:
              Text(r.sourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text(r.error ?? 'Failed', style: TextStyle(color: scheme.error)),
        ),
      );
    }
    return ListTile(
      leading: Icon(Icons.check_circle,
          color: scheme.primary, semanticLabel: 'Converted'),
      title: Text(out.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatBytes(out.bytes.length)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Save ${out.name}',
          icon: const Icon(Icons.download),
          onPressed: () => _save(out),
        ),
        IconButton(
          tooltip: 'Share ${out.name}',
          icon: const Icon(Icons.share),
          onPressed: () => _share([out]),
        ),
      ]),
    );
  }

  IconData _iconFor(InputKind kind) => switch (kind) {
        InputKind.epub => Icons.menu_book,
        InputKind.docx => Icons.description,
        InputKind.txt => Icons.notes,
        InputKind.image => Icons.image,
      };
}
