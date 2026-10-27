import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

class AcceptInvitationScreen extends ConsumerStatefulWidget {
  const AcceptInvitationScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends ConsumerState<AcceptInvitationScreen> {
  late final _code = TextEditingController(text: widget.initialToken);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final business = await ref.read(apiProvider).acceptInvitation(_code.text.trim());
      final session = ref.read(sessionProvider.notifier);
      await session.refreshProfile();
      await session.selectBusiness(business.id);
      ref.invalidate(currentBusinessProvider);
      if (mounted) {
        showMessage(context, 'You joined ${business.name}');
        context.go('/home');
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(sessionProvider.select((s) => s.user?.email));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a business')),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          PageBody(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Paste the invitation code you received.', style: t.bodyLarge),
                if (email != null) ...[
                  const SizedBox(height: Space.xs),
                  Text('The invitation must have been sent to $email.', style: t.bodySmall),
                ],
                const SizedBox(height: Space.lg),
                TextField(
                  controller: _code,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: 'Invitation code', errorText: _error),
                ),
                const SizedBox(height: Space.lg),
                PrimaryButton(label: 'Join business', loading: _busy, onPressed: _accept),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
