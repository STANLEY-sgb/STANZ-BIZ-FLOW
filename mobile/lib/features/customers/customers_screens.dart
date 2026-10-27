import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

final customersProvider = FutureProvider.autoDispose.family<PageResult<Customer>, String>((ref, q) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).customers(bid, q: q.trim().isEmpty ? null : q.trim());
});

final customerProvider = FutureProvider.autoDispose.family<Customer, String>((ref, id) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).customer(bid, id);
});

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider(_q));
    final canManage = ref.watch(currentBusinessProvider).value?.can('customers.manage') ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: BizColors.primary,
              foregroundColor: Colors.white,
              onPressed: () async {
                final created = await showCustomerForm(context, ref);
                if (created != null) ref.invalidate(customersProvider);
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add customer'),
            )
          : null,
      body: Column(
        children: [
          PageBody(
            child: TextField(
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v));
              },
              decoration: const InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: customers,
              onRetry: () => ref.invalidate(customersProvider(_q)),
              data: (page) => page.items.isEmpty
                  ? EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: _q.isEmpty ? 'No customers yet' : 'No matches',
                      message: _q.isEmpty
                          ? 'Save regular customers to see what they buy and attach them to receipts.'
                          : 'Try another name or number.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, 96),
                      itemCount: page.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
                      itemBuilder: (_, i) => _CustomerTile(
                        customer: page.items[i],
                        onTap: () => context.push('/customers/${page.items[i].id}'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap, this.trailing});

  final Customer customer;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.all(Space.sm),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: BizColors.secondaryContainer,
          foregroundColor: BizColors.secondary,
          child: Text(customer.name.characters.first.toUpperCase()),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(customer.name, style: Theme.of(context).textTheme.titleSmall),
              if (customer.phone != null) Text(customer.phone!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        trailing ?? const Icon(Icons.chevron_right_rounded, color: BizColors.textSecondary),
      ],
    ),
  );
}

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(customerId));
    final currency = ref.watch(currentBusinessProvider).value?.currency ?? '';
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: AsyncView(
        value: customer,
        onRetry: () => ref.invalidate(customerProvider(customerId)),
        data: (c) => ListView(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(c.name, style: t.headlineSmall),
                  if (c.phone != null) Text(c.phone!, style: t.bodyMedium),
                  if (c.email != null) Text(c.email!, style: t.bodyMedium),
                  const SizedBox(height: Space.lg),
                  Row(
                    children: [
                      Expanded(
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Purchases', style: t.bodySmall),
                              MoneyText('${c.salesCount ?? 0}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total spent (after refunds)', style: t.bodySmall),
                              MoneyText((c.totalSpent ?? Money.zero).format(currency)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (c.notes != null && c.notes!.isNotEmpty) ...[
                    const SectionHeader('Notes'),
                    AppCard(child: Text(c.notes!)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick "new customer" form. Returns the created customer, or null if cancelled.
Future<Customer?> showCustomerForm(BuildContext context, WidgetRef ref, {String initialName = ''}) =>
    showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerForm(initialName: initialName),
    );

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  late final _name = TextEditingController(text: widget.initialName);
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter the customer\'s name');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref.read(apiProvider).createCustomer(ref.read(activeBusinessIdProvider), {
        'name': _name.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, c);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, MediaQuery.viewInsetsOf(context).bottom + Space.lg),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New customer', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(_error!, style: const TextStyle(color: BizColors.error)),
          ],
          const SizedBox(height: Space.lg),
          PrimaryButton(label: 'Save customer', loading: _busy, onPressed: _save),
        ],
      ),
    ),
  );
}

/// Bottom-sheet picker used at checkout. Returns the chosen customer, or null.
Future<Customer?> pickCustomer(BuildContext context, WidgetRef ref) => showModalBottomSheet<Customer>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _CustomerPicker()),
);

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider(_q));
    final canManage = ref.watch(currentBusinessProvider).value?.can('customers.manage') ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose customer', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.sm),
          TextField(
            autofocus: true,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v));
            },
            decoration: const InputDecoration(hintText: 'Search name or phone', prefixIcon: Icon(Icons.search_rounded)),
          ),
          if (canManage)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final created = await showCustomerForm(context, ref, initialName: _q);
                  if (created != null && context.mounted) Navigator.pop(context, created);
                },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(_q.trim().isEmpty ? 'New customer' : 'Add "${_q.trim()}" as a new customer'),
              ),
            ),
          Expanded(
            child: AsyncView(
              value: customers,
              loading: const Center(child: CircularProgressIndicator()),
              onRetry: () => ref.invalidate(customersProvider(_q)),
              data: (page) => ListView.separated(
                padding: const EdgeInsets.only(bottom: Space.lg),
                itemCount: page.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
                itemBuilder: (_, i) => _CustomerTile(
                  customer: page.items[i],
                  trailing: const SizedBox.shrink(),
                  onTap: () => Navigator.pop(context, page.items[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
