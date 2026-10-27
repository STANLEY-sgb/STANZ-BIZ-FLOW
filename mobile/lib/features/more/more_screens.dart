import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_error.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

const roleLabels = {
  'owner': 'Owner',
  'admin': 'Administrator',
  'manager': 'Manager',
  'cashier': 'Cashier',
  'inventory_manager': 'Inventory manager',
  'accountant': 'Accountant',
};

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final b = ref.watch(currentBusinessProvider).value;
    final t = Theme.of(context).textTheme;
    bool can(String p) => b?.can(p) ?? false;

    final groups = <(String, List<(IconData, String, String, bool)>)>[
      (
        'Business',
        [
          (Icons.receipt_long_outlined, 'Sales history', '/sales', can(Perm.salesCreate)),
          (Icons.receipt_outlined, 'Expenses', '/expenses', can(Perm.expensesView)),
          (Icons.insights_rounded, 'Reports', '/reports', can(Perm.reportsView)),
        ],
      ),
      (
        'Administration',
        [
          (Icons.group_outlined, 'Team & roles', '/team', can(Perm.teamView)),
          (Icons.workspace_premium_outlined, 'Plan & usage', '/subscription', true),
          (Icons.tune_rounded, 'Business settings', '/settings', can(Perm.businessManage)),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: BizColors.primaryContainer,
                        foregroundColor: BizColors.onPrimaryContainer,
                        child: Text(
                          (session.user?.fullName ?? '?').characters.first.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(session.user?.fullName ?? '', style: t.titleSmall),
                            Text(session.user?.email ?? '', style: t.bodySmall),
                            if (b != null) ...[
                              const SizedBox(height: Space.xxs),
                              StatusChip('${roleLabels[b.role] ?? b.role} · ${b.name}', tone: Tone.info),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.businesses.length > 1 || (b?.role == 'owner')) ...[
                  const SizedBox(height: Space.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.push(session.businesses.length > 1 ? '/select-business' : '/onboarding'),
                    icon: Icon(session.businesses.length > 1 ? Icons.swap_horiz_rounded : Icons.add_business_outlined),
                    label: Text(session.businesses.length > 1 ? 'Switch business' : 'Add another business'),
                  ),
                ],
                for (final (title, items) in groups)
                  if (items.any((i) => i.$4)) ...[
                    SectionHeader(title),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, item) in items.where((i) => i.$4).indexed) ...[
                            if (i > 0) const Divider(indent: 56),
                            ListTile(
                              leading: Icon(item.$1, color: BizColors.secondary),
                              title: Text(item.$2),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => context.push(item.$3),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                const SizedBox(height: Space.lg),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: BizColors.error),
                  onPressed: () async {
                    if (await confirm(
                      context,
                      title: 'Sign out?',
                      message: 'You will need your password to sign in again.',
                      confirmLabel: 'Sign out',
                    )) {
                      await ref.read(sessionProvider.notifier).logout();
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
                const SizedBox(height: Space.lg),
                Text(
                  'STANZ BizFlow · A product of STANZ DIGITAL CONNECT',
                  style: t.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final membersProvider = FutureProvider.autoDispose<List<Member>>((ref) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).members(bid);
});

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  Future<void> _invite(BuildContext context, WidgetRef ref, Business b) async {
    final email = TextEditingController();
    var role = 'cashier';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Invite a team member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Their email address'),
              ),
              const SizedBox(height: Space.md),
              DropdownButtonFormField(
                initialValue: role,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final e in roleLabels.entries)
                    if (e.key != 'owner' || b.role == 'owner') DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send invite')),
          ],
        ),
      ),
    );
    final address = email.text.trim();
    email.dispose();
    if (submitted != true || address.isEmpty || !context.mounted) return;
    try {
      final res = await ref.read(apiProvider).invite(b.id, address, role);
      if (!context.mounted) return;
      final delivered = res['email_delivered'] == true;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invitation created'),
          content: Text(
            delivered
                ? 'We emailed $address. The invitation expires in 7 days.'
                : 'Email delivery is not set up yet, so nothing was emailed. Copy this invitation code and send it to $address '
                      '(for example on WhatsApp). They sign in with that email and enter the code.',
          ),
          actions: [
            if (!delivered)
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: res['accept_token'] as String));
                  Navigator.pop(context);
                  showMessage(context, 'Invitation code copied');
                },
                child: const Text('Copy code'),
              ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      );
    } on ApiError catch (e) {
      if (context.mounted) {
        showMessage(
          context,
          e.code == 'feature_not_in_plan'
              ? 'Team members need the Starter plan or higher. Start a free trial under Plan & usage.'
              : e.message,
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    final b = ref.watch(currentBusinessProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Team & roles')),
      floatingActionButton: (b?.can(Perm.teamManage) ?? false)
          ? FloatingActionButton.extended(
              backgroundColor: BizColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _invite(context, ref, b!),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Invite'),
            )
          : null,
      body: AsyncView(
        value: members,
        onRetry: () => ref.invalidate(membersProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.all(Space.page),
          children: [
            Text(
              'Each person signs in with their own account. Permissions are enforced by the server for every action.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, m) in list.indexed) ...[
                    if (i > 0) const Divider(indent: 72),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: BizColors.secondaryContainer,
                        foregroundColor: BizColors.secondary,
                        child: Text(m.fullName.characters.first.toUpperCase()),
                      ),
                      title: Text(m.fullName),
                      subtitle: Text(m.email),
                      trailing: StatusChip(
                        roleLabels[m.role] ?? m.role,
                        tone: m.role == 'owner' ? Tone.brand : Tone.info,
                      ),
                    ),
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

final subscriptionProvider = FutureProvider.autoDispose<SubscriptionInfo>((ref) {
  final bid = ref.watch(activeBusinessIdProvider);
  return ref.watch(apiProvider).subscription(bid);
});

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider);
    final b = ref.watch(currentBusinessProvider).value;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan & usage')),
      body: AsyncView(
        value: sub,
        onRetry: () => ref.invalidate(subscriptionProvider),
        data: (s) => ListView(
          padding: const EdgeInsets.all(Space.page),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${s.planName} plan', style: t.titleLarge),
                      const Spacer(),
                      StatusChip(humanize(s.status), tone: s.status == 'active' ? Tone.success : Tone.warning),
                    ],
                  ),
                  if (s.trialEndsAt != null)
                    Text('Trial ends ${DateFormat.yMMMd().format(s.trialEndsAt!)}', style: t.bodySmall),
                  const SizedBox(height: Space.md),
                  for (final (key, label) in [
                    ('products', 'Active products'),
                    ('members', 'Team members'),
                    ('sales_this_month', 'Sales this month'),
                  ])
                    _UsageBar(label: label, used: s.usage[key] ?? 0, limit: s.limits[key]),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            if (b?.can(Perm.subscriptionManage) ?? false) ...[
              if (s.planCode == 'free' && s.trialEndsAt == null) ...[
                PrimaryButton(
                  label: 'Start 14-day Starter trial',
                  onPressed: () async {
                    try {
                      await ref.read(apiProvider).startTrial(b!.id, 'starter');
                      ref.invalidate(subscriptionProvider);
                      if (context.mounted) showMessage(context, 'Starter trial started');
                    } on ApiError catch (e) {
                      if (context.mounted) showMessage(context, e.message, error: true);
                    }
                  },
                ),
                const SizedBox(height: Space.sm),
              ],
              Text(
                'Paid plans are activated by STANZ DIGITAL CONNECT once a verified payment is received. '
                'In-app payment is not available yet.',
                style: t.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.label, required this.used, required this.limit});

  final String label;
  final int used;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ratio = limit == null || limit == 0 ? 0.0 : (used / limit!).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: t.bodyMedium)),
              Text(limit == null ? '$used · unlimited' : '$used of $limit', style: t.bodySmall),
            ],
          ),
          const SizedBox(height: Space.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: limit == null ? 0 : ratio,
              minHeight: 6,
              color: ratio >= 0.9 ? BizColors.warning : BizColors.secondary,
              backgroundColor: BizColors.secondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  ConsumerState<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends ConsumerState<BusinessSettingsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _footer = TextEditingController();
  final _tax = TextEditingController();
  bool? _enforceStock;
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _footer, _tax]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Business b) {
    if (_loaded) return;
    _loaded = true;
    _name.text = b.name;
    _phone.text = b.phone ?? '';
    _address.text = b.address ?? '';
    _footer.text = b.receiptFooter ?? '';
    _tax.text = b.taxRatePercent;
    _enforceStock = b.enforceStock;
  }

  Future<void> _save(Business b) async {
    setState(() => _busy = true);
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(apiProvider).updateBusiness(b.id, {
        'name': _name.text.trim(),
        'phone': opt(_phone),
        'address': opt(_address),
        'receipt_footer': opt(_footer),
        'tax_rate_percent': opt(_tax) ?? '0',
        'enforce_stock': _enforceStock,
      });
      ref.invalidate(currentBusinessProvider);
      await ref.read(sessionProvider.notifier).refreshProfile();
      if (mounted) showMessage(context, 'Settings saved');
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
      appBar: AppBar(title: const Text('Business settings')),
      body: AsyncView(
        value: business,
        data: (b) {
          _fill(b);
          Widget field(TextEditingController c, String label, {String? helper, TextInputType? type}) => Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: TextField(
              controller: c,
              keyboardType: type,
              decoration: InputDecoration(labelText: label, helperText: helper),
            ),
          );
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            children: [
              PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field(_name, 'Business name'),
                    field(_phone, 'Phone shown on receipts', type: TextInputType.phone),
                    field(_address, 'Address shown on receipts'),
                    field(
                      _footer,
                      'Receipt message',
                      helper: 'e.g. Thank you! Goods once sold are not returnable after 7 days.',
                    ),
                    field(
                      _tax,
                      'Tax rate included in prices (%)',
                      helper: 'Use 0 if you are not VAT-registered. 18 for standard Uganda VAT.',
                      type: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: SwitchListTile(
                        value: _enforceStock ?? b.enforceStock,
                        onChanged: (v) => setState(() => _enforceStock = v),
                        title: const Text('Block sales when out of stock'),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    AppCard(
                      color: BizColors.surfaceMuted,
                      child: Text(
                        'Currency ${b.currency} · Time zone ${b.timezone}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    PrimaryButton(label: 'Save settings', loading: _busy, onPressed: () => _save(b)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
