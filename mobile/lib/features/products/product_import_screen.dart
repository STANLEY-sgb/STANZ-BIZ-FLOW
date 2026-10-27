import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_error.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/offline_providers.dart';
import '../../data/models.dart';
import 'product_providers.dart';

/// Guided import: pick a CSV/Excel file → server dry run → review → confirm.
class ProductImportScreen extends ConsumerStatefulWidget {
  const ProductImportScreen({super.key});

  @override
  ConsumerState<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends ConsumerState<ProductImportScreen> {
  String? _filename;
  List<int>? _bytes;
  ImportReport? _report;
  bool _updateExisting = false;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv', 'xlsx']);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _filename = file.name;
      _bytes = bytes;
      _report = null;
    });
    await _check();
  }

  Future<void> _check() async {
    if (_bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(apiProvider)
          .importProducts(
            ref.read(activeBusinessIdProvider),
            filename: _filename!,
            bytes: _bytes!,
            updateExisting: _updateExisting,
          );
      if (mounted) setState(() => _report = report);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _report = null;
          _error = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final report = _report!;
    if (report.invalid > 0 &&
        !await confirm(
          context,
          title: 'Skip ${report.invalid} rows with errors?',
          message:
              'Only the ${report.importable} valid rows will be imported. You can fix the others and import them later.',
          confirmLabel: 'Import valid rows',
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(apiProvider)
          .importProducts(
            ref.read(activeBusinessIdProvider),
            filename: _filename!,
            bytes: _bytes!,
            dryRun: false,
            updateExisting: _updateExisting,
            skipInvalid: report.invalid > 0,
          );
      invalidateCatalog(ref);
      unawaited(ref.read(syncControllerProvider.notifier).run(refreshCatalog: true));
      if (!mounted) return;
      showMessage(
        context,
        [
          if (result.created > 0) '${result.created} products added',
          if (result.updated > 0) '${result.updated} updated',
        ].join(' · ').ifEmpty('Nothing to import'),
      );
      context.pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Import products')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        children: [
          PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  color: BizColors.secondaryContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Use a spreadsheet you already have', style: t.titleSmall),
                      const SizedBox(height: Space.xxs),
                      Text(
                        'CSV or Excel (.xlsx), up to 5,000 products. The first row must contain headings. Required: '
                        'Name and Selling price. Optional: Cost price, Quantity, Category, SKU, Barcode, Unit, '
                        'Low-stock alert, Brand, Model, Storage, Colour, Condition, Warranty, IMEI.',
                        style: t.bodySmall?.copyWith(color: BizColors.textPrimary),
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(
                        'Tip: export your products first to get a ready-made template.',
                        style: t.bodySmall?.copyWith(color: BizColors.onSecondaryContainer),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(_filename == null ? 'Choose a file' : 'Choose a different file'),
                ),
                if (_filename != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(_filename!, style: t.bodySmall, textAlign: TextAlign.center),
                ],
                if (_busy && report == null) ...[
                  const SizedBox(height: Space.lg),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: Space.xs),
                  Text('Checking every row…', style: t.bodySmall, textAlign: TextAlign.center),
                ],
                if (_error != null) ...[
                  const SizedBox(height: Space.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: const TextStyle(color: BizColors.error)),
                  ),
                ],
                if (report != null) ..._reportView(t, report),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _reportView(TextTheme t, ImportReport r) => [
    const SectionHeader('Check results'),
    Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        StatusChip('${r.toCreate} new', tone: Tone.success, icon: Icons.add_rounded),
        if (r.toUpdate > 0) StatusChip('${r.toUpdate} to update', tone: Tone.info, icon: Icons.edit_rounded),
        if (r.skipped > 0) StatusChip('${r.skipped} already exist', icon: Icons.remove_rounded),
        if (r.invalid > 0) StatusChip('${r.invalid} with errors', tone: Tone.error, icon: Icons.error_outline_rounded),
      ],
    ),
    const SizedBox(height: Space.sm),
    AppCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        value: _updateExisting,
        onChanged: _busy
            ? null
            : (v) {
                setState(() => _updateExisting = v);
                _check();
              },
        title: const Text('Update products that already exist'),
        subtitle: const Text('Matched by SKU or barcode. Stock differences are recorded as a stock count.'),
      ),
    ),
    if (r.planLimitExceeded) ...[
      const SizedBox(height: Space.sm),
      AppCard(
        color: BizColors.warningContainer,
        child: Text(
          'This import would go over your plan\'s product limit. Start a trial or upgrade under Plan & usage, '
          'or import fewer rows.',
          style: t.bodyMedium,
        ),
      ),
    ],
    if (r.errors.isNotEmpty) ...[
      SectionHeader('Rows to fix (${r.invalid})'),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, e) in r.errors.take(50).indexed) ...[
              if (i > 0) const Divider(indent: Space.md, endIndent: Space.md),
              ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline_rounded, color: BizColors.error),
                title: Text('Row ${e.row} · ${humanize(e.column)}'),
                subtitle: Text(e.message),
              ),
            ],
          ],
        ),
      ),
      if (r.errors.length > 50)
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text('…and ${r.errors.length - 50} more.', style: t.bodySmall),
        ),
    ],
    SectionHeader('Preview (first ${r.preview.length} rows)'),
    AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, row) in r.preview.indexed) ...[
            if (i > 0) const Divider(indent: Space.md, endIndent: Space.md),
            ListTile(
              dense: true,
              title: Text(row.name ?? '(no name)', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  'Row ${row.row}',
                  if (row.price != null) row.price!.format(''),
                  if (row.quantity != null) 'qty ${row.quantity}',
                  ?row.message,
                ].join(' · ').replaceAll('·  ', '· '),
                maxLines: 2,
              ),
              trailing: StatusChip(
                switch (row.action) {
                  'create' => 'New',
                  'update' => 'Update',
                  'skip' => 'Skip',
                  _ => 'Error',
                },
                tone: switch (row.action) {
                  'create' => Tone.success,
                  'update' => Tone.info,
                  'skip' => Tone.neutral,
                  _ => Tone.error,
                },
              ),
            ),
          ],
        ],
      ),
    ),
    const SizedBox(height: Space.lg),
    PrimaryButton(
      label: r.importable == 0
          ? 'Nothing to import'
          : (r.invalid > 0 ? 'Import ${r.importable} valid rows' : 'Import ${r.importable} products'),
      loading: _busy,
      onPressed: r.importable == 0 || r.planLimitExceeded ? null : _import,
    ),
  ];
}

/// Shares a CSV of all products via the system share sheet (WhatsApp, Drive, email…).
Future<void> exportProducts(BuildContext context, WidgetRef ref) async {
  try {
    final bytes = await ref.read(apiProvider).exportProductsCsv(ref.read(activeBusinessIdProvider));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'text/csv')],
        fileNameOverrides: const ['products.csv'],
        subject: 'Product list',
      ),
    );
  } on ApiError catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
