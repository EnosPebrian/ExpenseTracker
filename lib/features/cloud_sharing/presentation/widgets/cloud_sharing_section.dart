import 'package:flutter/material.dart';

import '../../../backup/presentation/controllers/backup_export_controller.dart';
import '../../../backup/domain/restore_lifecycle_service.dart';
import '../../../backup/presentation/controllers/restore_lifecycle_controller.dart';
import '../../../backup/presentation/widgets/restore_lifecycle_panel.dart';
import '../../../master_data/domain/entities/financial_book.dart';
import '../../../master_data/domain/entities/household_member.dart';
import '../../../sync/presentation/controllers/sync_controller.dart';
import '../../../sync/presentation/controllers/initial_sync_controller.dart';
import '../../../sync/presentation/widgets/initial_sync_section.dart';
import '../../../sync/presentation/widgets/sync_status_section.dart';
import '../controllers/cloud_sharing_controller.dart';

class CloudSharingSection extends StatelessWidget {
  const CloudSharingSection({
    super.key,
    required this.controller,
    required this.book,
    required this.members,
    required this.activeMemberId,
    this.syncController,
    this.initialSyncController,
    this.backupExportController,
    this.restoreLifecycleController,
    this.onOpenRecovery,
    this.onReviewConflicts,
  });

  final CloudSharingController controller;
  final FinancialBook book;
  final List<HouseholdMember> members;
  final String? activeMemberId;
  final SyncController? syncController;
  final InitialSyncController? initialSyncController;
  final BackupExportController? backupExportController;
  final RestoreLifecycleController? restoreLifecycleController;
  final VoidCallback? onOpenRecovery;
  final VoidCallback? onReviewConflicts;

  HouseholdMember? get _activeMember {
    for (final member in members) {
      if (member.id == activeMemberId) return member;
    }
    return null;
  }

  Future<void> _requestOtp(BuildContext context) async {
    final email = await _TextPrompt.show(
      context,
      title: 'Sign in to cloud sharing',
      label: 'Email',
      keyboardType: TextInputType.emailAddress,
    );
    if (email != null) await controller.requestOtp(email);
  }

  Future<void> _verifyOtp(BuildContext context) async {
    final token = await _TextPrompt.show(
      context,
      title: 'Enter verification code',
      label: 'One-time code',
      keyboardType: TextInputType.number,
    );
    if (token != null) await controller.verifyOtp(token);
  }

  Future<void> _invite(BuildContext context) async {
    final request = await showDialog<_InvitationRequest>(
      context: context,
      builder: (_) => _InvitationDialog(members: members),
    );
    if (request != null) {
      await controller.inviteMember(
        book: book,
        member: request.member,
        email: request.email,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        ?initialSyncController,
        ?restoreLifecycleController,
      ]),
      builder: (context, _) {
        final user = controller.user;
        final linked =
            controller.isLinked(book.id) || book.remoteLinkedAt != null;
        final configurationUnavailable =
            controller.status == CloudSharingStatus.notConfigured ||
            controller.status == CloudSharingStatus.invalidConfiguration ||
            controller.status == CloudSharingStatus.initializationFailed;
        HouseholdMember? mappedMember;
        if (user != null) {
          for (final member in members) {
            final mappedByLocalLink = member.authUserId == user.id;
            final mappedByMembership = controller.memberships.any(
              (membership) =>
                  membership.bookId == book.id &&
                  membership.householdMemberId == member.id,
            );
            if (mappedByLocalLink || mappedByMembership) {
              mappedMember = member;
              break;
            }
          }
        }
        final reconnectAvailable =
            !configurationUnavailable &&
            user != null &&
            mappedMember != null &&
            initialSyncController?.canReconnect == true &&
            backupExportController != null;
        final restoreLifecycleVisible =
            restoreLifecycleController?.preview?.sourceBookId == book.id;
        final restoredLocalOnly = RestoreLifecycleService.isRestoredLocalOnly(
          book,
        );
        return Card(
          key: const Key('cloud-sharing-section'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cloud Sharing',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(_statusText(controller.status, linked)),
                const SizedBox(height: 6),
                Text(
                  _guidanceText(controller.status, linked),
                  key: const Key('cloud-sharing-guidance'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Configuration: '
                  '${controller.diagnostics.isConfigured ? 'configured' : 'unavailable'} · '
                  'URL valid: ${controller.diagnostics.urlValid ? 'yes' : 'no'} · '
                  'publishable key present: '
                  '${controller.diagnostics.publishableKeyPresent ? 'yes' : 'no'} · '
                  'Auth initialization: '
                  '${controller.diagnostics.authInitialization.name} · '
                  'session: ${controller.authSessionDiagnostic}',
                  key: const Key('cloud-safe-diagnostics'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (user != null) ...[
                  const SizedBox(height: 6),
                  Text('Signed in as ${user.email}'),
                  if (mappedMember != null)
                    Text('Mapped to local member: ${mappedMember.displayName}'),
                ],
                if (controller.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    controller.error!,
                    key: const Key('cloud-sharing-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (configurationUnavailable)
                  Text(
                    _configurationMessage(controller.status, linked),
                    key: const Key('cloud-configuration-message'),
                  )
                else if (controller.status ==
                    CloudSharingStatus.restoringSession)
                  const LinearProgressIndicator(
                    key: Key('cloud-session-restoring'),
                  )
                else if (controller.status ==
                    CloudSharingStatus.connectivityError)
                  OutlinedButton(
                    key: const Key('cloud-retry'),
                    onPressed: controller.busy ? null : controller.retry,
                    child: const Text('Try again'),
                  )
                else if (user == null &&
                    controller.status != CloudSharingStatus.otpSent)
                  FilledButton(
                    key: const Key('cloud-sign-in'),
                    onPressed: controller.busy
                        ? null
                        : () => _requestOtp(context),
                    child: const Text('Sign in with email'),
                  )
                else if (controller.status == CloudSharingStatus.otpSent)
                  FilledButton(
                    key: const Key('cloud-verify-otp'),
                    onPressed: controller.busy
                        ? null
                        : () => _verifyOtp(context),
                    child: const Text('Verify code'),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!linked &&
                          !restoredLocalOnly &&
                          controller.memberships.isEmpty &&
                          controller.invitations.isEmpty)
                        FilledButton(
                          key: const Key('cloud-link-household'),
                          onPressed: controller.busy || _activeMember == null
                              ? null
                              : () => controller.linkHousehold(
                                  book: book,
                                  activeMember: _activeMember!,
                                ),
                          child: const Text('Link this household'),
                        ),
                      if (linked)
                        FilledButton.tonal(
                          key: const Key('cloud-invite-member'),
                          onPressed: controller.busy || members.isEmpty
                              ? null
                              : () => _invite(context),
                          child: const Text('Invite local member'),
                        ),
                      if (reconnectAvailable && !restoreLifecycleVisible)
                        FilledButton(
                          key: const Key('cloud-reconnect-household'),
                          onPressed:
                              controller.busy || initialSyncController!.busy
                              ? null
                              : () => _ReconnectDialog.show(
                                  context,
                                  activeBook: book,
                                  cloudController: controller,
                                  initialSyncController: initialSyncController!,
                                  backupController: backupExportController!,
                                ),
                          child: const Text('Reconnect cloud sharing'),
                        ),
                      TextButton(
                        key: const Key('cloud-sign-out'),
                        onPressed: controller.busy ? null : controller.signOut,
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ],
                if (reconnectAvailable) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'The hosted household is authoritative. Create an encrypted safety backup, then download it to reconnect this device without uploading local-only changes.',
                    key: Key('cloud-reconnect-guidance'),
                  ),
                ],
                for (final invitation in controller.invitations) ...[
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(invitation.email),
                    subtitle: Text(
                      '${invitation.status} · expires '
                      '${MaterialLocalizations.of(context).formatMediumDate(invitation.expiresAt)}',
                    ),
                    trailing:
                        user == null ||
                            invitation.email != user.email.trim().toLowerCase()
                        ? null
                        : FilledButton.tonal(
                            key: ValueKey('accept-invitation-${invitation.id}'),
                            onPressed: controller.busy
                                ? null
                                : () => controller.acceptInvitation(invitation),
                            child: const Text('Accept'),
                          ),
                  ),
                ],
                if (restoreLifecycleVisible) ...[
                  const SizedBox(height: 12),
                  RestoreLifecyclePanel(
                    controller: restoreLifecycleController!,
                    bookId: book.id,
                    authenticatedEmail: user?.email,
                    onReconnect: reconnectAvailable
                        ? () => _ReconnectDialog.show(
                            context,
                            activeBook: book,
                            cloudController: controller,
                            initialSyncController: initialSyncController!,
                            backupController: backupExportController!,
                          )
                        : null,
                    onRecoverMissing: onOpenRecovery,
                  ),
                ],
                const SizedBox(height: 12),
                if (syncController != null) ...[
                  SyncStatusSection(
                    controller: syncController!,
                    cloudDecision: initialSyncController?.decision,
                    onReviewConflicts: onReviewConflicts,
                  ),
                  const SizedBox(height: 12),
                ],
                if (initialSyncController != null) ...[
                  InitialSyncSection(controller: initialSyncController!),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Incremental financial synchronization starts only after a '
                  'validated initial upload or download. Realtime is an optional '
                  'wake-up signal; cursor synchronization remains authoritative.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _statusText(CloudSharingStatus status, bool linked) {
    if (linked && status == CloudSharingStatus.signedOut) {
      return 'Household linked · device signed out';
    }
    return switch (status) {
      CloudSharingStatus.notConfigured => 'Not configured',
      CloudSharingStatus.invalidConfiguration => 'Invalid configuration',
      CloudSharingStatus.initializationFailed => 'Cloud initialization failed',
      CloudSharingStatus.restoringSession => 'Restoring cloud session',
      CloudSharingStatus.signedOut => 'Sign in required',
      CloudSharingStatus.otpSent => 'Verification code sent',
      CloudSharingStatus.signedInUnlinked => 'Signed in · household not linked',
      CloudSharingStatus.householdLinked => 'Household linked',
      CloudSharingStatus.invitationPending => 'Invitation pending',
      CloudSharingStatus.membershipActive => 'Membership active',
      CloudSharingStatus.connectivityError => 'Supabase Auth unavailable',
      CloudSharingStatus.sessionExpired => 'Session expired',
      CloudSharingStatus.error => 'Error or offline',
    };
  }

  static String _guidanceText(CloudSharingStatus status, bool linked) {
    return switch (status) {
      CloudSharingStatus.notConfigured ||
      CloudSharingStatus.invalidConfiguration ||
      CloudSharingStatus.initializationFailed =>
        linked
            ? 'The saved household link is unchanged; local data remains available.'
            : 'Local data remains available on this device.',
      CloudSharingStatus.restoringSession =>
        'Checking for a saved sign-in on this device.',
      CloudSharingStatus.signedOut =>
        linked
            ? 'This household is linked to cloud sharing, but this device is '
                  'currently signed out.'
            : 'Sign in to synchronize this household across your devices.',
      CloudSharingStatus.sessionExpired =>
        'Your cloud session expired. Sign in again. Your local data is safe.',
      CloudSharingStatus.connectivityError =>
        'Local data remains available while Supabase Auth is unreachable.',
      _ => 'Cloud configuration and the current device session are active.',
    };
  }

  static String _configurationMessage(CloudSharingStatus status, bool linked) {
    if (status == CloudSharingStatus.initializationFailed) {
      return 'Cloud sharing is configured, but Auth initialization failed. '
          'Local data remains available.';
    }
    if (status == CloudSharingStatus.invalidConfiguration) {
      return 'This app build contains invalid cloud-sharing configuration.';
    }
    return linked
        ? 'This household has a saved cloud link, but this app build was '
              'created without cloud configuration.'
        : 'This app build does not include cloud-sharing configuration.';
  }
}

class _ReconnectDialog extends StatefulWidget {
  const _ReconnectDialog({
    required this.activeBook,
    required this.cloudController,
    required this.initialSyncController,
    required this.backupController,
  });

  final FinancialBook activeBook;
  final CloudSharingController cloudController;
  final InitialSyncController initialSyncController;
  final BackupExportController backupController;

  static Future<void> show(
    BuildContext context, {
    required FinancialBook activeBook,
    required CloudSharingController cloudController,
    required InitialSyncController initialSyncController,
    required BackupExportController backupController,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReconnectDialog(
      activeBook: activeBook,
      cloudController: cloudController,
      initialSyncController: initialSyncController,
      backupController: backupController,
    ),
  );

  @override
  State<_ReconnectDialog> createState() => _ReconnectDialogState();
}

class _ReconnectDialogState extends State<_ReconnectDialog> {
  final password = TextEditingController();
  String? selectedBookId;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final preferred = widget.initialSyncController.decision.targetBookId;
    final ids = widget.initialSyncController.reconnectManifests.keys;
    if (preferred != null && ids.contains(preferred)) {
      selectedBookId = preferred;
      return;
    }
    if (ids.isNotEmpty) selectedBookId = ids.first;
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bookId = selectedBookId;
    if (bookId == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await widget.backupController.createReconnectSafetyBackup(
        password.text,
      );
      if (saved == null) {
        throw StateError(
          'Reconnect cancelled because the safety backup was not saved.',
        );
      }
      await widget.initialSyncController.reconnect(bookId);
      final failure = widget.initialSyncController.error;
      if (failure != null) throw StateError(failure);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialSyncController.lastResult?.message ??
                'Cloud sharing reconnected successfully.',
          ),
        ),
      );
    } catch (caught) {
      if (mounted) {
        setState(() {
          error = caught is StateError
              ? caught.message.toString()
              : caught.toString();
          busy = false;
        });
      }
    }
  }

  String _roleFor(String bookId) {
    for (final membership in widget.cloudController.memberships) {
      if (membership.bookId == bookId && membership.status == 'active') {
        return membership.role.name;
      }
    }
    return 'membership unavailable';
  }

  @override
  Widget build(BuildContext context) {
    final manifests = widget.initialSyncController.reconnectManifests;
    final selected = selectedBookId == null ? null : manifests[selectedBookId];
    const synchronizedEntities = <String>{
      'household',
      'members',
      'categories',
      'budgets',
      'projects',
      'accounts',
      'asset_definitions',
      'transactions',
    };
    final localCount =
        widget.backupController.snapshot?.entries
            .where((entry) => synchronizedEntities.contains(entry.key))
            .fold<int>(0, (total, entry) => total + entry.value.length) ??
        0;
    return AlertDialog(
      key: const Key('cloud-reconnect-dialog'),
      title: const Text('Reconnect cloud sharing'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Downloading the existing shared household will replace this '
                'restored local snapshot. Records found only in this restored '
                'snapshot will not be uploaded automatically. Use Recover '
                'missing records if you need to add records from a backup to '
                'the shared household. A required encrypted safety backup is '
                'created first.',
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: selectedBookId,
                onChanged: (value) {
                  if (!busy) setState(() => selectedBookId = value);
                },
                child: Column(
                  children: [
                    for (final entry in manifests.entries)
                      RadioListTile<String>(
                        key: Key(
                          'hosted-household-${entry.key == widget.activeBook.id ? 'matching' : 'additional'}',
                        ),
                        value: entry.key,
                        enabled: !busy,
                        title: Text(entry.value.bookName),
                        subtitle: Text(
                          '${entry.value.baseCurrencyCode} \u00b7 '
                          '${_roleFor(entry.key)} \u00b7 '
                          '${entry.key == widget.activeBook.id ? 'Matches this local household' : 'Additional hosted household'}',
                        ),
                      ),
                  ],
                ),
              ),
              if (selected != null) ...[
                const Divider(),
                Text('Local records: $localCount'),
                Text('Hosted records: ${selected.totalCount}'),
                const Text(
                  'Local-only, hosted-only, and differing records are validated during the protected download.',
                ),
                Text('Expected downloaded total: ${selected.totalCount}'),
              ],
              const SizedBox(height: 12),
              Text(
                widget.backupController.backupDestination?.displayValue ??
                    'No safety-backup folder selected.',
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : widget.backupController.chooseBackupDestination,
                child: const Text('Choose safety-backup folder'),
              ),
              TextField(
                key: const Key('cloud-reconnect-password'),
                controller: password,
                obscureText: true,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Safety-backup password',
                  helperText: 'Use at least 8 characters.',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  key: const Key('cloud-reconnect-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('cloud-reconnect-download'),
          onPressed: busy || selected == null ? null : _submit,
          child: const Text('Back up and download'),
        ),
      ],
    );
  }
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.keyboardType,
  });

  final String title;
  final String label;
  final TextInputType keyboardType;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String label,
    required TextInputType keyboardType,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _TextPrompt(title: title, label: label, keyboardType: keyboardType),
  );

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final text = TextEditingController();

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('cloud-prompt-field'),
        controller: text,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('cloud-prompt-submit'),
          onPressed: () => Navigator.pop(context, text.text.trim()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _InvitationRequest {
  const _InvitationRequest(this.member, this.email);
  final HouseholdMember member;
  final String email;
}

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog({required this.members});
  final List<HouseholdMember> members;

  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  late HouseholdMember selected = widget.members.first;
  final email = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite household member'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<HouseholdMember>(
            key: const Key('cloud-invite-member-field'),
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Local member'),
            items: [
              for (final member in widget.members)
                DropdownMenuItem(
                  value: member,
                  child: Text(member.displayName),
                ),
            ],
            onChanged: (value) => setState(() => selected = value ?? selected),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('cloud-invite-email-field'),
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('cloud-send-invitation'),
          onPressed: () => Navigator.pop(
            context,
            _InvitationRequest(selected, email.text.trim()),
          ),
          child: const Text('Send invitation'),
        ),
      ],
    );
  }
}
