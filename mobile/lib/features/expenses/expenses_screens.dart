import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../onboarding/onboarding_screens.dart' show paymentMethodLabels;
import '../products/product_form_screen.dart' show requiredMoney;

const expenseCategories = {
  'rent': ('Rent', Icons.home_work_outlined),
  'salaries': ('Salaries & wages', Icons.badge_outlined),
  'utilities': ('Electricity & water', Icons.bolt_rounded),
  'transport': ('Transport', Icons.two_wheeler_rounded),
  'stock_purchase': ('Stock purchase', Icons.inventory_outlined),
  'marketing': ('Marketing', Icons.campaign_outlined),
  'airtime_data': ('Airtime & data', Icons.sim_card_outlined),
  'repairs': ('Repairs', Icons.build_outlined),
  'taxes_fees': ('Taxes & fees', Icons.account_balance_outlined),
  'supplies': ('Supplies', Icons.shopping_bag_outlined),
  'other': ('Other', Icons.more_horiz_rounded),
};

final expensesProvider = FutureProvider.autoDispose<PageResult<Expense>>((ref) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).expenses(bid);
});

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    final business = ref.watch(currentBusinessProvider).value;
    final canManage = business?.can(Perm.expensesManage) ?? false;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: BizColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/expenses/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Record expense'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(expensesProvider.future),
        child: AsyncView(
          value: expenses,
          onRetry: () => ref.invalidate(expensesProvider),
          data: (page) => page.items.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: Space.xl),
                    EmptyState(
                      icon: Icons.receipt_outlined,
                      title: 'No expenses recorded',
                      message: 'Track rent, transport, salaries and more to see your real profit.',
                      actionLabel: canManage ? 'Record an expense' : null,
                      onAction: () => context.push('/expenses/new'),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, 96),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
                  itemBuilder: (_, i) {
                    final e = page.items[i];
                    final cat = expenseCategories[e.category];
                    return AppCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(Space.xs),
                            decoration: BoxDecoration(
                              color: BizColors.secondaryContainer,
                              borderRadius: BorderRadius.circular(Radii.sm),
                            ),
                            child: Icon(cat?.$2 ?? Icons.receipt_outlined, color: BizColors.secondary),
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cat?.$1 ?? humanize(e.category), style: t.titleSmall),
                                Text(
                                  [DateFormat.yMMMd().format(e.date), ?e.description].join(' · '),
                                  style: t.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          MoneyText(e.amount.format(business?.currency ?? ''), style: t.titleSmall),
                          if (canManage)
                            IconButton(
                              tooltip: 'Delete expense',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () async {
                                if (!await confirm(
                                  context,
                                  title: 'Delete this expense?',
                                  message: 'It will be removed from reports. The change is kept in the audit log.',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                )) {
                                  return;
                                }
                                try {
                                  await ref.read(apiProvider).deleteExpense(business!.id, e.id);
                                  ref.invalidate(expensesProvider);
                                } on ApiError catch (err) {
                                  if (context.mounted) showMessage(context, err.message, error: true);
                                }
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _supplier = TextEditingController();
  String _category = 'transport';
  String? _method = 'cash';
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _supplier.dispose();
    super.dispose();
  }

  Future<void> _save(Business b) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).createExpense(b.id, {
        'category': _category,
        'amount': Money.parse(_amount.text).toApi(),
        'expense_date': DateFormat('yyyy-MM-dd').format(_date),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        if (_supplier.text.trim().isNotEmpty) 'supplier': _supplier.text.trim(),
        'payment_method': _method,
      });
      ref.invalidate(expensesProvider);
      if (mounted) {
        showMessage(context, 'Expense recorded');
        context.pop();
      }
    } on ApiError catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(currentBusinessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Record expense')),
      body: AsyncView(
        value: business,
        data: (b) => Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            children: [
              PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      validator: (v) =>
                          requiredMoney(v) ?? (Money.parse(v!).isZero ? 'Amount must be more than zero' : null),
                      decoration: InputDecoration(labelText: 'Amount', prefixText: '${b.currency} '),
                    ),
                    const SizedBox(height: Space.md),
                    DropdownButtonFormField(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final e in expenseCategories.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                Icon(e.value.$2, size: 20),
                                const SizedBox(width: Space.sm),
                                Text(e.value.$1),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                    const SizedBox(height: Space.md),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.event_rounded),
                        title: const Text('Date'),
                        subtitle: Text(DateFormat.yMMMMd().format(_date)),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    TextFormField(
                      controller: _description,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'e.g. Boda to Kikuubo for stock',
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    TextFormField(
                      controller: _supplier,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Paid to (optional)'),
                    ),
                    const SizedBox(height: Space.md),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        for (final e in paymentMethodLabels.entries)
                          ChoiceChip(
                            label: Text(e.value.$1),
                            selected: _method == e.key,
                            onSelected: (_) => setState(() => _method = e.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.lg),
                    PrimaryButton(label: 'Save expense', loading: _busy, onPressed: () => _save(b)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
