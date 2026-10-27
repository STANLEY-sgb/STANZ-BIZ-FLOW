import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

class BusinessCategory {
  const BusinessCategory(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;
}

const businessCategories = [
  BusinessCategory('retail', 'General retail', Icons.storefront_rounded),
  BusinessCategory('supermarket', 'Supermarket', Icons.shopping_cart_rounded),
  BusinessCategory('electronics', 'Phones & electronics', Icons.smartphone_rounded),
  BusinessCategory('fashion', 'Clothing & fashion', Icons.checkroom_rounded),
  BusinessCategory('wholesale', 'Wholesale', Icons.local_shipping_rounded),
  BusinessCategory('beauty', 'Salon & beauty', Icons.content_cut_rounded),
  BusinessCategory('restaurant', 'Restaurant & food', Icons.restaurant_rounded),
  BusinessCategory('services', 'Services', Icons.handyman_rounded),
  BusinessCategory('other', 'Something else', Icons.category_rounded),
];

/// Region presets. Uganda first; everything remains configurable per business.
const regions = [
  (country: 'UG', name: 'Uganda', currency: 'UGX', timezone: 'Africa/Kampala'),
  (country: 'KE', name: 'Kenya', currency: 'KES', timezone: 'Africa/Nairobi'),
  (country: 'TZ', name: 'Tanzania', currency: 'TZS', timezone: 'Africa/Dar_es_Salaam'),
  (country: 'RW', name: 'Rwanda', currency: 'RWF', timezone: 'Africa/Kigali'),
  (country: 'SS', name: 'South Sudan', currency: 'SSP', timezone: 'Africa/Juba'),
  (country: 'CD', name: 'DR Congo (east)', currency: 'CDF', timezone: 'Africa/Lubumbashi'),
  (country: 'NG', name: 'Nigeria', currency: 'NGN', timezone: 'Africa/Lagos'),
  (country: 'GB', name: 'United Kingdom', currency: 'GBP', timezone: 'Europe/London'),
  (country: 'US', name: 'United States (Eastern)', currency: 'USD', timezone: 'America/New_York'),
];

const paymentMethodLabels = {
  'cash': ('Cash', Icons.payments_rounded),
  'mobile_money': ('Mobile money', Icons.phone_android_rounded),
  'bank_transfer': ('Bank transfer', Icons.account_balance_rounded),
  'card': ('Card', Icons.credit_card_rounded),
  'other': ('Other', Icons.more_horiz_rounded),
};

class CreateBusinessScreen extends ConsumerStatefulWidget {
  const CreateBusinessScreen({super.key});

  @override
  ConsumerState<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends ConsumerState<CreateBusinessScreen> {
  static const _steps = 3;
  int _step = 0;
  final _nameForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String? _category;
  var _region = regions.first;
  final Set<String> _methods = {'cash', 'mobile_money'};
  bool _enforceStock = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && !(_nameForm.currentState!.validate() && _category != null)) {
      if (_category == null) setState(() => _error = 'Choose the type of business');
      return;
    }
    setState(() => _error = null);
    if (_step < _steps - 1) {
      setState(() => _step++);
    } else {
      _create();
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final business = await api.createBusiness({
        'name': _name.text.trim(),
        'category': _category,
        'country_code': _region.country,
        'currency': _region.currency,
        'timezone': _region.timezone,
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
        'payment_methods': _methods.toList(),
        'enforce_stock': _enforceStock,
      });
      final session = ref.read(sessionProvider.notifier);
      await session.refreshProfile();
      await session.selectBusiness(business.id);
      if (mounted) context.go('/setup');
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasOtherBusinesses = ref.watch(sessionProvider.select((s) => s.businesses.isNotEmpty));
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step > 0
              ? BackButton(onPressed: () => setState(() => _step--))
              : hasOtherBusinesses
              ? CloseButton(onPressed: () => context.go('/home'))
              : null,
          title: Text('Step ${_step + 1} of $_steps'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (_step + 1) / _steps),
              duration: Motion.normal,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 4,
                backgroundColor: BizColors.border,
                semanticsLabel: 'Setup progress',
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: PageBody(
                    padding: const EdgeInsets.all(Space.lg),
                    child: AnimatedSwitcher(
                      duration: Motion.normal,
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: switch (_step) {
                          0 => _detailsStep(t),
                          1 => _regionStep(t),
                          _ => _paymentStep(t),
                        },
                      ),
                    ),
                  ),
                ),
              ),
              PageBody(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.md),
                child: Column(
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Text(_error!, style: const TextStyle(color: BizColors.error)),
                      ),
                    PrimaryButton(
                      label: _step == _steps - 1 ? 'Create my business' : 'Continue',
                      loading: _busy,
                      onPressed: _next,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(TextTheme t, String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: t.headlineSmall),
      const SizedBox(height: Space.xs),
      Text(subtitle, style: t.bodyMedium?.copyWith(color: BizColors.textSecondary)),
      const SizedBox(height: Space.lg),
    ],
  );

  Widget _detailsStep(TextTheme t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(t, 'Tell us about your business', 'This appears on receipts and can be changed later.'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => context.push('/invite'),
          icon: const Icon(Icons.mail_outline_rounded, size: 18),
          label: const Text('Joining your employer? Enter an invitation code'),
        ),
      ),
      const SizedBox(height: Space.xs),
      Form(
        key: _nameForm,
        child: TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your business name' : null,
          decoration: const InputDecoration(labelText: 'Business name', hintText: 'e.g. Nakato Phone World'),
        ),
      ),
      const SizedBox(height: Space.lg),
      Text('What kind of business is it?', style: t.titleSmall),
      const SizedBox(height: Space.sm),
      LayoutBuilder(
        builder: (context, c) {
          final columns = c.maxWidth > 520 ? 3 : 2;
          final width = (c.maxWidth - Space.sm * (columns - 1)) / columns;
          return Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final cat in businessCategories)
                SizedBox(
                  width: width,
                  child: _SelectTile(
                    icon: cat.icon,
                    label: cat.label,
                    selected: _category == cat.code,
                    onTap: () => setState(() {
                      _category = cat.code;
                      _error = null;
                    }),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _regionStep(TextTheme t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(t, 'Where do you operate?', 'Sets your currency and when your business day starts and ends.'),
      DropdownButtonFormField(
        initialValue: _region,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Country'),
        items: [for (final r in regions) DropdownMenuItem(value: r, child: Text(r.name))],
        onChanged: (r) => setState(() => _region = r!),
      ),
      const SizedBox(height: Space.md),
      AppCard(
        color: BizColors.secondaryContainer,
        child: Row(
          children: [
            const Icon(Icons.public_rounded, color: BizColors.secondary),
            const SizedBox(width: Space.sm),
            Expanded(child: Text('Currency ${_region.currency} · Time zone ${_region.timezone}')),
          ],
        ),
      ),
      const SizedBox(height: Space.md),
      TextFormField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Business phone (optional)'),
      ),
      const SizedBox(height: Space.md),
      TextFormField(
        controller: _address,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Location / address (optional)',
          hintText: 'e.g. Kikuubo, Kampala',
        ),
      ),
    ],
  );

  Widget _paymentStep(TextTheme t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(t, 'How do customers pay you?', 'Choose the methods your cashiers can record.'),
      for (final entry in paymentMethodLabels.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: _SelectTile(
            icon: entry.value.$2,
            label: entry.value.$1,
            selected: _methods.contains(entry.key),
            horizontal: true,
            onTap: () => setState(() {
              if (_methods.contains(entry.key)) {
                if (_methods.length > 1) _methods.remove(entry.key);
              } else {
                _methods.add(entry.key);
              }
            }),
          ),
        ),
      const SizedBox(height: Space.md),
      AppCard(
        padding: EdgeInsets.zero,
        child: SwitchListTile(
          value: _enforceStock,
          onChanged: (v) => setState(() => _enforceStock = v),
          title: const Text('Block sales when out of stock'),
          subtitle: const Text('Recommended. Prevents selling items you do not have.'),
        ),
      ),
      const SizedBox(height: Space.sm),
      Text('Recording a payment does not charge the customer — it keeps your records accurate.', style: t.bodySmall),
    ],
  );
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.horizontal = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final iconBox = AnimatedContainer(
      duration: Motion.fast,
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: selected ? BizColors.primary : BizColors.secondaryContainer,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Icon(icon, color: selected ? Colors.white : BizColors.secondary, size: Sizes.iconMd),
    );
    final text = Text(
      label,
      style: Theme.of(context).textTheme.titleSmall,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? BizColors.primaryContainer : BizColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.control,
          side: BorderSide(color: selected ? BizColors.primary : BizColors.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: Radii.control,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: horizontal
                ? Row(
                    children: [
                      iconBox,
                      const SizedBox(width: Space.sm),
                      Expanded(child: text),
                      Icon(
                        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                        color: selected ? BizColors.primary : BizColors.borderStrong,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconBox,
                      const SizedBox(height: Space.sm),
                      SizedBox(height: 40, child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Post-creation checklist. Progress is saved on the server so users can resume later.
class SetupChecklistScreen extends ConsumerWidget {
  const SetupChecklistScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref, String bid) async {
    try {
      await ref.read(apiProvider).setOnboardingStep(bid, 'done');
      await ref.read(sessionProvider.notifier).refreshProfile();
      ref.invalidate(currentBusinessProvider);
      if (context.mounted) context.go('/home');
    } on ApiError catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final business = ref.watch(currentBusinessProvider);
    return Scaffold(
      body: SafeArea(
        child: AsyncView(
          value: business,
          onRetry: () => ref.invalidate(currentBusinessProvider),
          data: (b) => SingleChildScrollView(
            child: PageBody(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: BrandLogo(size: 32)),
                  const SizedBox(height: Space.xl),
                  Text('${b.name} is ready', style: t.headlineMedium),
                  const SizedBox(height: Space.xs),
                  Text(
                    'A few quick steps make BizFlow useful from day one. You can skip any of them.',
                    style: t.bodyMedium?.copyWith(color: BizColors.textSecondary),
                  ),
                  const SizedBox(height: Space.lg),
                  _ChecklistItem(
                    icon: Icons.add_box_rounded,
                    title: 'Add your first product',
                    subtitle: 'Name, price and how many you have in stock.',
                    done: b.onboardingStep != 'first_product',
                    onTap: () => context.push('/products/new'),
                  ),
                  _ChecklistItem(
                    icon: Icons.upload_file_rounded,
                    title: 'Import a product list',
                    subtitle: 'Already have your stock in Excel or CSV? Bring it in at once.',
                    onTap: () => context.push('/products/import'),
                  ),
                  _ChecklistItem(
                    icon: Icons.group_add_rounded,
                    title: 'Invite your team',
                    subtitle: 'Give cashiers access without sharing your password.',
                    onTap: () => context.push('/team'),
                  ),
                  _ChecklistItem(
                    icon: Icons.tune_rounded,
                    title: 'Review business settings',
                    subtitle: 'Receipt details, tax rate and payment methods.',
                    onTap: () => context.push('/settings'),
                  ),
                  const SizedBox(height: Space.lg),
                  PrimaryButton(label: 'Go to my dashboard', onPressed: () => _finish(context, ref, b.id)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.done = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool done;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(color: BizColors.primaryContainer, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Icon(done ? Icons.check_rounded : icon, color: done ? BizColors.success : BizColors.primaryPressed),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (done)
            const StatusChip('Done', tone: Tone.success)
          else
            const Icon(Icons.chevron_right_rounded, color: BizColors.textSecondary),
        ],
      ),
    ),
  );
}

class SelectBusinessScreen extends ConsumerWidget {
  const SelectBusinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a business')),
      body: ListView(
        padding: const EdgeInsets.all(Space.page),
        children: [
          Text('You belong to more than one business. Pick one to continue.', style: t.bodyMedium),
          const SizedBox(height: Space.md),
          for (final b in session.businesses)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                onTap: () async {
                  await ref.read(sessionProvider.notifier).selectBusiness(b.businessId);
                  ref.invalidate(currentBusinessProvider);
                  if (context.mounted) context.go('/home');
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: BizColors.secondaryContainer,
                      foregroundColor: BizColors.secondary,
                      child: Text(b.businessName.characters.first.toUpperCase()),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(b.businessName, style: t.titleSmall)),
                    StatusChip(b.role.replaceAll('_', ' '), tone: Tone.info),
                    if (b.businessId == session.activeBusinessId) ...[
                      const SizedBox(width: Space.xs),
                      const Icon(Icons.check_circle_rounded, color: BizColors.primary),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () => context.push('/onboarding'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create another business'),
          ),
        ],
      ),
    );
  }
}
