import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/media/media.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import 'product_providers.dart';

final _moneyInput = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];
final _qtyInput = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))];

String? requiredMoney(String? v) {
  final m = Money.tryParse(v);
  if (m == null) return 'Enter an amount';
  if (m.isNegative) return 'Amount cannot be negative';
  return null;
}

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in [
      'name',
      'price',
      'cost',
      'stock',
      'reorder',
      'sku',
      'barcode',
      'unit',
      'description',
      'brand',
      'model',
      'storage',
      'colour',
      'warranty',
      'imei',
    ])
      k: TextEditingController(),
  };
  String? _categoryId;
  String _condition = 'new';
  bool _trackStock = true;
  bool _showDetails = false;
  bool _busy = false;
  Product? _editing;
  Map<String, String> _fieldErrors = const {};

  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    _c['unit']!.text = 'pcs';
    _c['reorder']!.text = '0';
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    final p = await ref.read(productProvider(widget.productId!).future);
    setState(() {
      _editing = p;
      _c['name']!.text = p.name;
      _c['price']!.text = p.sellingPrice.toApi();
      _c['cost']!.text = p.costPrice?.toApi() ?? '';
      _c['reorder']!.text = p.reorderLevel.toString();
      _c['sku']!.text = p.sku ?? '';
      _c['barcode']!.text = p.barcode ?? '';
      _c['unit']!.text = p.unit;
      _c['description']!.text = p.description ?? '';
      for (final k in ['brand', 'model', 'storage', 'colour', 'imei']) {
        _c[k]!.text = '${p.attributes[k] ?? ''}';
      }
      _c['warranty']!.text = '${p.attributes['warranty_months'] ?? ''}';
      _condition = (p.attributes['condition'] as String?) ?? 'new';
      _categoryId = p.categoryId;
      _trackStock = p.trackStock;
      _showDetails = p.attributes.isNotEmpty;
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  Future<void> _save(Business business) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _fieldErrors = const {};
    });
    final attributes = <String, Object?>{
      for (final k in ['brand', 'model', 'storage', 'colour']) k: ?_text(k),
      if (_showDetails) 'condition': _condition,
      if (_text('warranty') != null) 'warranty_months': int.tryParse(_text('warranty')!),
      if (_text('imei') != null) 'imei': _text('imei'),
    };
    final body = <String, Object?>{
      'name': _text('name'),
      'selling_price': Money.parse(_c['price']!.text).toApi(),
      if (business.can(Perm.productsViewCost)) 'cost_price': (Money.tryParse(_c['cost']!.text) ?? Money.zero).toApi(),
      'reorder_level': (Quantity.tryParse(_c['reorder']!.text) ?? Quantity.whole(0)).toString(),
      'sku': _text('sku'),
      'barcode': _text('barcode'),
      'unit': _text('unit') ?? 'pcs',
      'description': _text('description'),
      'category_id': _categoryId,
      'track_stock': _trackStock,
      'attributes': attributes,
    };
    try {
      final api = ref.read(apiProvider);
      final Product saved;
      if (_isEdit) {
        saved = await api.updateProduct(business.id, _editing!.id, {...body, 'version': _editing!.version});
      } else {
        saved = await api.createProduct(business.id, {
          ...body,
          'opening_stock': (Quantity.tryParse(_c['stock']!.text) ?? Quantity.whole(0)).toString(),
        });
        if (business.onboardingStep == 'first_product') {
          await api.setOnboardingStep(business.id, 'payment_methods');
        }
      }
      invalidateCatalog(ref);
      if (!mounted) return;
      showMessage(context, _isEdit ? 'Product updated' : '${saved.name} added');
      context.pop();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _fieldErrors = e.fieldErrors);
      showMessage(
        context,
        e.code == 'version_conflict' ? 'Someone else changed this product. Reopen it and try again.' : e.message,
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCategory(String bid) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final cat = await ref.read(apiProvider).createCategory(bid, name);
      ref.invalidate(categoriesProvider);
      setState(() => _categoryId = cat.id);
    } on ApiError catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
    String? prefix,
    String? helper,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Space.md),
    child: TextFormField(
      controller: _c[key],
      keyboardType: keyboard,
      inputFormatters: formatters,
      validator: validator,
      textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        helperText: helper,
        suffixIcon: suffix,
        errorText: _fieldErrors[{'price': 'selling_price', 'cost': 'cost_price'}[key] ?? key],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final businessValue = ref.watch(currentBusinessProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit product' : 'New product')),
      body: AsyncView(
        value: businessValue,
        data: (business) {
          if (_isEdit && _editing == null) return const SkeletonList(count: 4);
          final currency = '${business.currency} ';
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              children: [
                PageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(
                        'name',
                        'Product name',
                        hint: 'e.g. Samsung Galaxy A15 128GB',
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a product name' : null,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              'price',
                              'Selling price',
                              prefix: currency,
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                              formatters: _moneyInput,
                              validator: requiredMoney,
                            ),
                          ),
                          if (business.can(Perm.productsViewCost)) ...[
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: _field(
                                'cost',
                                'Cost price',
                                prefix: currency,
                                helper: 'Used for profit',
                                keyboard: const TextInputType.numberWithOptions(decimal: true),
                                formatters: _moneyInput,
                              ),
                            ),
                          ],
                        ],
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('No category')),
                          for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _addCategory(business.id),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New category'),
                        ),
                      ),
                      const SectionHeader('Stock'),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: SwitchListTile(
                          value: _trackStock,
                          onChanged: (v) => setState(() => _trackStock = v),
                          title: const Text('Track stock for this item'),
                          subtitle: const Text('Turn off for services or made-to-order items.'),
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      if (_trackStock) ...[
                        // Two fields per row at most, so labels stay readable with large system text.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_isEdit) ...[
                              Expanded(
                                child: _field(
                                  'stock',
                                  'Opening stock',
                                  hint: '0',
                                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                                  formatters: _qtyInput,
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                            ],
                            Expanded(child: _field('unit', 'Unit', hint: 'pcs, kg, box')),
                          ],
                        ),
                        _field(
                          'reorder',
                          'Low-stock alert level',
                          helper: 'You will be warned when stock falls to this number.',
                          keyboard: const TextInputType.numberWithOptions(decimal: true),
                          formatters: _qtyInput,
                        ),
                      ],
                      if (_isEdit && _trackStock)
                        Text(
                          'To change quantities, use Adjust stock on the product page so every change is recorded.',
                          style: t.bodySmall,
                        ),
                      const SectionHeader('Codes'),
                      _field('sku', 'SKU / item code (optional)'),
                      _field(
                        'barcode',
                        'Barcode (optional)',
                        keyboard: TextInputType.number,
                        suffix: IconButton(
                          tooltip: 'Scan with camera',
                          icon: const Icon(Icons.qr_code_scanner_rounded, color: BizColors.primary),
                          onPressed: () async {
                            final code = await scanBarcode(context);
                            if (code != null) setState(() => _c['barcode']!.text = code);
                          },
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: ExpansionTile(
                          initiallyExpanded: _showDetails,
                          onExpansionChanged: (v) => setState(() => _showDetails = v),
                          shape: const Border(),
                          title: const Text('Device & variant details'),
                          subtitle: const Text('Brand, model, storage, colour, warranty, IMEI'),
                          childrenPadding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
                          children: [
                            Row(
                              children: [
                                Expanded(child: _field('brand', 'Brand')),
                                const SizedBox(width: Space.sm),
                                Expanded(child: _field('model', 'Model')),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(child: _field('storage', 'Storage / size')),
                                const SizedBox(width: Space.sm),
                                Expanded(child: _field('colour', 'Colour')),
                              ],
                            ),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'new', label: Text('New')),
                                ButtonSegment(value: 'refurbished', label: Text('Refurb')),
                                ButtonSegment(value: 'used', label: Text('Used')),
                              ],
                              selected: {_condition},
                              onSelectionChanged: (s) => setState(() => _condition = s.first),
                            ),
                            const SizedBox(height: Space.md),
                            _field(
                              'warranty',
                              'Warranty (months)',
                              keyboard: TextInputType.number,
                              formatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                            _field(
                              'imei',
                              'IMEI / serial number',
                              helper: 'Visible only to owners, managers and inventory staff.',
                              keyboard: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      _field('description', 'Description (optional)'),
                      const SizedBox(height: Space.sm),
                      PrimaryButton(
                        label: _isEdit ? 'Save changes' : 'Add product',
                        loading: _busy,
                        onPressed: () => _save(business),
                      ),
                      const SizedBox(height: Space.lg),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
