import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/local_db.dart';
import '../../data/local/offline_providers.dart';

/// What a manager should do about each kind of rejected offline sale.
const rejectionAdvice = {
  'insufficient_stock':
      'Another sale used up this stock first. Receive the missing stock, then retry, or refund the customer.',
  'price_changed':
      'The price changed while you were offline. Ask a manager to re-enter the sale at the current price '
      '(with an approved discount if the customer paid less).',
  'product_archived': 'A product in this sale was archived. Restore it or re-enter the sale with another item.',
  'discount_not_allowed': 'Your role cannot give discounts. Ask a manager to re-enter this sale.',
  'payment_method_disabled': 'That payment method was turned off in settings. Re-enter the sale with another method.',
  'plan_limit': 'Your plan\'s monthly sales limit was reached. Upgrade the plan, then retry.',
};

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unresolved = ref.watch(unresolvedSalesProvider);
    final status = ref.watch(syncControllerProvider);
    final syncedAt = ref.watch(productsSyncedAtProvider).value;
    final currency = ref.watch(currentBusinessProvider).value?.currency ?? '';
    final t = Theme.of(context).textTheme;
    final last = status.lastReport;

    Future<void> syncNow() async {
      final report = await ref.read(syncControllerProvider.notifier).run(refreshCatalog: true, manual: true);
      if (!context.mounted || report == null) return;
      if (report.failed) {
        showMessage(context, report.error?.message ?? 'Still offline. BizFlow will keep trying.', error: true);
      } else {
        final parts = [
          if (report.accepted > 0) '${report.accepted} synced',
          if (report.rejected > 0) '${report.rejected} need review',
        ];
        showMessage(context, parts.isEmpty ? 'Everything is up to date' : parts.join(' · '));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Offline sync')),
      body: AsyncView(
        value: unresolved,
        data: (sales) {
          final pending = sales.where((s) => s.state != 'rejected').toList();
          final rejected = sales.where((s) => s.state == 'rejected').toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            children: [
              PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                sales.isEmpty ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
                                color: sales.isEmpty ? BizColors.success : BizColors.primary,
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Text(
                                  sales.isEmpty
                                      ? 'All sales are on the server'
                                      : '${pending.length} waiting · ${rejected.length} need review',
                                  style: t.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            [
                              if (syncedAt != null) 'Products saved ${DateFormat.MMMd().add_jm().format(syncedAt)}',
                              if (status.lastRunAt != null)
                                'last check ${DateFormat.jm().format(status.lastRunAt!)}'
                                    '${last?.failed == true ? ' (offline)' : ''}',
                            ].join(' · '),
                            style: t.bodySmall,
                          ),
                          const SizedBox(height: Space.md),
                          PrimaryButton(
                            label: status.running ? 'Syncing…' : 'Sync now',
                            icon: Icons.sync_rounded,
                            loading: status.running,
                            onPressed: syncNow,
                          ),
                        ],
                      ),
                    ),
                    if (rejected.isNotEmpty) ...[
                      const SectionHeader('Needs review'),
                      for (final s in rejected) _QueuedSaleCard(sale: s, currency: currency),
                    ],
                    if (pending.isNotEmpty) ...[
                      const SectionHeader('Waiting to sync'),
                      for (final s in pending) _QueuedSaleCard(sale: s, currency: currency),
                    ],
                    const SizedBox(height: Space.md),
                    Text(
                      'Sales made offline get their official receipt number when they reach the server. '
                      'Each sale is sent with a unique reference, so retrying never records it twice.',
                      style: t.bodySmall,
                    ),
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

class _QueuedSaleCard extends ConsumerWidget {
  const _QueuedSaleCard({required this.sale, required this.currency});

  final PendingSale sale;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final rejected = sale.state == 'rejected';
    final advice = rejectionAdvice[sale.lastErrorCode];
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(sale.summary, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Space.xs),
                MoneyText(Money.parse(sale.previewTotal).format(currency), style: t.titleSmall!.tabular),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Recorded ${DateFormat.MMMd().add_jm().format(sale.createdAt)}'
              '${sale.attempts > 0 && !rejected ? ' · ${sale.attempts} attempts' : ''}',
              style: t.bodySmall,
            ),
            const SizedBox(height: Space.xs),
            StatusChip(
              rejected ? 'Rejected by server' : (sale.state == 'syncing' ? 'Sending…' : 'Waiting for connection'),
              tone: rejected ? Tone.error : Tone.warning,
            ),
            if (rejected) ...[
              const SizedBox(height: Space.xs),
              Text(sale.lastErrorMessage ?? 'The server could not record this sale.', style: t.bodyMedium),
              if (advice != null) ...[const SizedBox(height: Space.xxs), Text(advice, style: t.bodySmall)],
              const SizedBox(height: Space.xs),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Space.xs,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: BizColors.error),
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        title: 'Remove this sale from the phone?',
                        message:
                            'It was NOT recorded by the server. If you took money for it, re-enter the sale or refund '
                            'the customer first.',
                        confirmLabel: 'Remove',
                        destructive: true,
                      );
                      if (ok) await ref.read(localDbProvider).discardSale(sale.clientReference);
                    },
                    child: const Text('Remove'),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      await ref.read(offlineSyncProvider).retryRejected(sale.clientReference);
                      final report = await ref.read(syncControllerProvider.notifier).run(refreshCatalog: true);
                      if (!context.mounted || report == null) return;
                      if (report.failed) {
                        showMessage(context, 'Still offline. It will be retried automatically.', error: true);
                      } else if (report.rejected > 0) {
                        showMessage(
                          context,
                          'The server still could not record it. See the reason below.',
                          error: true,
                        );
                      } else {
                        showMessage(context, 'Sale recorded on the server');
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
