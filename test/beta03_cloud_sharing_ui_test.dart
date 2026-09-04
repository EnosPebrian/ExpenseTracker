import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/data/unconfigured_cloud_sharing_repository.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/domain/cloud_models.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/domain/cloud_sharing_repository.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/presentation/controllers/cloud_sharing_controller.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/presentation/widgets/cloud_sharing_section.dart';
import 'package:pilgrim_tracker/features/backup/data/portable_file_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_service.dart';
import 'package:pilgrim_tracker/features/backup/presentation/controllers/backup_export_controller.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/household_member.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/screens/household_settings_page.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_coordinator.dart';
import 'package:pilgrim_tracker/features/sync/domain/cloud_sync_state_classifier.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/presentation/controllers/initial_sync_controller.dart';

void main() {
  final book = FinancialBook(id: 'book', name: 'My Household');
  final enos = HouseholdMember(
    id: 'enos',
    bookId: book.id,
    displayName: 'Enos',
    role: HouseholdMemberRole.owner,
  );
  final grace = HouseholdMember(
    id: 'grace',
    bookId: book.id,
    displayName: 'Grace',
  );

  testWidgets('missing cloud configuration leaves household controls usable', (
    tester,
  ) async {
    final controller = CloudSharingController(
      repository: const UnconfiguredCloudSharingRepository(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    HouseholdMember? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSettingsPage(
            book: book,
            members: [enos, grace],
            activeMemberId: enos.id,
            onRenameBook: (_) async {},
            onAddMember: (_) async {},
            onRenameMember: (_, _) async {},
            onSelectActiveMember: (member) async => selected = member,
            cloudSharingSection: CloudSharingSection(
              controller: controller,
              book: book,
              members: [enos, grace],
              activeMemberId: enos.id,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('This app build does not include cloud-sharing configuration.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('household-member-grace')));
    await tester.pump();
    expect(selected?.id, grace.id);
  });

  testWidgets(
    'saved remote link plus missing build configuration is explicit',
    (tester) async {
      final controller = CloudSharingController(
        repository: const UnconfiguredCloudSharingRepository(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudSharingSection(
              controller: controller,
              book: book.copyWith(remoteLinkedAt: DateTime(2026, 7, 30)),
              members: [enos],
              activeMemberId: enos.id,
            ),
          ),
        ),
      );
      expect(
        find.textContaining('saved cloud link, but this app build'),
        findsOneWidget,
      );
    },
  );

  testWidgets('linked household signed out copy separates link and session', (
    tester,
  ) async {
    final controller = CloudSharingController(
      repository: _WidgetCloudRepository(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSharingSection(
            controller: controller,
            book: book.copyWith(remoteLinkedAt: DateTime(2026, 7, 30)),
            members: [enos],
            activeMemberId: enos.id,
          ),
        ),
      ),
    );
    expect(find.text('Household linked · device signed out'), findsOneWidget);
    expect(find.textContaining('currently signed out'), findsOneWidget);
    expect(find.byKey(const Key('cloud-sharing-error')), findsNothing);
  });

  testWidgets('email OTP UI sends normalized email and reaches verify state', (
    tester,
  ) async {
    final repository = _WidgetCloudRepository();
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSharingSection(
            controller: controller,
            book: book,
            members: [enos],
            activeMemberId: enos.id,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('cloud-sign-in')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cloud-prompt-field')),
      ' Enos@Example.Test ',
    );
    await tester.tap(find.byKey(const Key('cloud-prompt-submit')));
    await tester.pumpAndSettle();

    expect(repository.requestedEmail, 'enos@example.test');
    expect(find.byKey(const Key('cloud-verify-otp')), findsOneWidget);
    expect(
      find.textContaining('Incremental financial synchronization starts only'),
      findsOneWidget,
    );
  });

  testWidgets('linked cloud identity shows its local member mapping', (
    tester,
  ) async {
    final repository = _WidgetCloudRepository(
      user: const CloudAuthUser(id: 'auth-enos', email: 'enos@example.test'),
      memberships: const [
        CloudBookMembership(
          id: 'membership',
          bookId: 'book',
          householdMemberId: 'enos',
          role: CloudMembershipRole.owner,
          status: 'active',
        ),
      ],
      invitations: [
        CloudBookInvitation(
          id: 'outgoing',
          bookId: 'book',
          email: 'grace@example.test',
          householdMemberId: 'grace',
          role: CloudMembershipRole.member,
          status: 'pending',
          expiresAt: DateTime(2026, 8, 1),
        ),
      ],
    );
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSharingSection(
            controller: controller,
            book: book,
            members: [enos, grace],
            activeMemberId: enos.id,
          ),
        ),
      ),
    );

    expect(find.text('Signed in as enos@example.test'), findsOneWidget);
    expect(find.text('Mapped to local member: Enos'), findsOneWidget);
    expect(find.byKey(const Key('cloud-invite-member')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('accept-invitation-outgoing')),
      findsNothing,
    );
  });

  testWidgets('invited member cannot link an independent local household', (
    tester,
  ) async {
    final repository = _WidgetCloudRepository(
      user: const CloudAuthUser(id: 'auth-grace', email: 'grace@example.test'),
      memberships: const [
        CloudBookMembership(
          id: 'remote-membership',
          bookId: 'remote-shared-book',
          householdMemberId: 'remote-grace',
          role: CloudMembershipRole.member,
          status: 'active',
        ),
      ],
    );
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSharingSection(
            controller: controller,
            book: book,
            members: [grace],
            activeMemberId: grace.id,
          ),
        ),
      ),
    );

    expect(find.text('Membership active'), findsOneWidget);
    expect(find.byKey(const Key('cloud-link-household')), findsNothing);
  });

  testWidgets('pending invitation suppresses local household linking', (
    tester,
  ) async {
    final repository = _WidgetCloudRepository(
      user: const CloudAuthUser(id: 'auth-grace', email: 'grace@example.test'),
      invitations: [
        CloudBookInvitation(
          id: 'pending-invitation',
          bookId: 'remote-shared-book',
          email: 'grace@example.test',
          householdMemberId: 'remote-grace',
          role: CloudMembershipRole.member,
          status: 'pending',
          expiresAt: DateTime(2026, 8, 4),
        ),
      ],
    );
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSharingSection(
            controller: controller,
            book: book,
            members: [grace],
            activeMemberId: grace.id,
          ),
        ),
      ),
    );

    expect(find.text('Invitation pending'), findsOneWidget);
    expect(find.byKey(const Key('cloud-link-household')), findsNothing);
    expect(
      find.byKey(const ValueKey('accept-invitation-pending-invitation')),
      findsOneWidget,
    );
  });

  testWidgets('signed-in local-only household exposes safe reconnect action', (
    tester,
  ) async {
    final repository = _WidgetCloudRepository(
      user: const CloudAuthUser(id: 'auth-enos', email: 'enos@example.test'),
      memberships: const [
        CloudBookMembership(
          id: 'membership-secret-id',
          bookId: 'book',
          householdMemberId: 'enos',
          role: CloudMembershipRole.owner,
          status: 'active',
        ),
      ],
    );
    final cloud = CloudSharingController(repository: repository);
    addTearDown(cloud.dispose);
    await cloud.initialize();
    final initial =
        InitialSyncController(
            coordinator: InitialSyncCoordinator(
              repository: _NoopInitialSyncRepository(),
              transport: const UnavailableInitialSyncTransport(
                configured: true,
              ),
            ),
          )
          ..primaryBook = book
          ..authUserId = 'auth-enos'
          ..decision = const CloudSyncDecision(
            CloudSyncClassification.reconnectSameHostedHousehold,
            reason: 'widget-test',
            targetBookId: 'book',
          )
          ..hostedManifests['book'] = const InitialSyncManifest(
            bookId: 'book',
            bookName: 'Hosted Household',
            baseCurrencyCode: 'IDR',
            counts: {'books': 1},
            snapshotSequence: 7,
            memberRole: 'owner',
            householdMemberId: 'enos',
            remoteInitializationComplete: true,
          );
    addTearDown(initial.dispose);
    final backup = BackupExportController(
      backupService: HouseholdBackupService(_NoopBackupStore()),
      fileService: const PortableFileService(),
    );
    addTearDown(backup.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSharingSection(
            controller: cloud,
            book: book,
            members: [enos],
            activeMemberId: enos.id,
            initialSyncController: initial,
            backupExportController: backup,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('cloud-reconnect-household')), findsOneWidget);
    expect(
      find.textContaining('hosted household is authoritative'),
      findsOneWidget,
    );
    expect(find.textContaining('membership-secret-id'), findsNothing);
  });
}

class _NoopInitialSyncRepository implements InitialSyncRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopBackupStore implements HouseholdBackupStore {
  @override
  int get schemaVersion => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WidgetCloudRepository implements CloudSharingRepository {
  _WidgetCloudRepository({
    this.user,
    this.memberships = const [],
    this.invitations = const [],
  });

  final CloudAuthUser? user;
  final List<CloudBookMembership> memberships;
  final List<CloudBookInvitation> invitations;
  String? requestedEmail;

  @override
  CloudConfigurationDiagnostics get diagnostics =>
      const CloudConfigurationDiagnostics(
        configuration: CloudConfigurationState.configured,
        urlValid: true,
        publishableKeyPresent: true,
        authInitialization: CloudAuthInitializationState.initialized,
      );
  @override
  CloudAuthUser? get currentUser => user;
  @override
  Stream<CloudAuthUser?> get authChanges => const Stream.empty();

  @override
  Future<void> restoreAuthSession() async {}

  @override
  Future<void> requestEmailOtp(String email) async => requestedEmail = email;
  @override
  Future<void> signOut() async {}
  @override
  Future<List<CloudBookMembership>> listMemberships() async => memberships;
  @override
  Future<List<CloudBookInvitation>> listPendingInvitations() async =>
      invitations;

  @override
  Future<CloudAuthUser> verifyEmailOtp({
    required String email,
    required String token,
  }) async => CloudAuthUser(id: 'user', email: email);

  @override
  Future<CloudLinkResult> linkHousehold({
    required FinancialBook book,
    required HouseholdMember activeMember,
  }) => throw UnimplementedError();

  @override
  Future<CloudBookInvitation> createInvitation({
    required String bookId,
    required String email,
    required HouseholdMember householdMember,
  }) => throw UnimplementedError();

  @override
  Future<CloudBookMembership> acceptInvitation(String invitationId) =>
      throw UnimplementedError();
}
