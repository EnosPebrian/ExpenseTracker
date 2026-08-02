import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../../domain/entities/financial_book.dart';
import '../../domain/entities/household_member.dart';

class HouseholdSettingsPage extends StatelessWidget {
  const HouseholdSettingsPage({
    super.key,
    required this.book,
    required this.members,
    required this.activeMemberId,
    required this.onRenameBook,
    required this.onAddMember,
    required this.onRenameMember,
    required this.onSelectActiveMember,
    this.cloudSharingSection,
  });

  final FinancialBook book;
  final List<HouseholdMember> members;
  final String? activeMemberId;
  final Future<void> Function(String name) onRenameBook;
  final Future<void> Function(String name) onAddMember;
  final Future<void> Function(HouseholdMember member, String name)
  onRenameMember;
  final Future<void> Function(HouseholdMember member) onSelectActiveMember;
  final Widget? cloudSharingSection;

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) async {
    var value = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          key: const Key('household-name-field'),
          initialValue: initialValue,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (updated) => value = updated,
          onFieldSubmitted: (value) =>
              Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result?.trim().isEmpty == true ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'LOCAL HOUSEHOLD',
            title: 'Household Settings',
            subtitle: 'Manage the people connected to this financial book.',
          ),
          Card(
            child: ListTile(
              key: const Key('household-summary'),
              title: Text(book.name),
              subtitle: Text('Base currency: ${book.baseCurrencyCode}'),
              trailing: IconButton(
                tooltip: 'Rename household',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final name = await _askName(
                    context,
                    title: 'Rename household',
                    initialValue: book.name,
                  );
                  if (name != null) await onRenameBook(name);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Members',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                key: const Key('add-household-member'),
                onPressed: () async {
                  final name = await _askName(
                    context,
                    title: 'Add local member',
                  );
                  if (name != null) await onAddMember(name);
                },
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add member'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final member in members)
            Card(
              child: ListTile(
                key: ValueKey('household-member-${member.id}'),
                leading: Icon(
                  member.id == activeMemberId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(member.displayName),
                subtitle: Text(
                  '${member.role.label}${member.id == activeMemberId ? ' · Active on this device' : ''}',
                ),
                trailing: IconButton(
                  tooltip: 'Rename member',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final name = await _askName(
                      context,
                      title: 'Rename member',
                      initialValue: member.displayName,
                    );
                    if (name != null) await onRenameMember(member, name);
                  },
                ),
                onTap: () => onSelectActiveMember(member),
              ),
            ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Household members identify account ownership and transaction '
                'attribution. Authorized members can synchronize this '
                'household across devices when cloud sharing is configured '
                'and signed in.',
              ),
            ),
          ),
          if (cloudSharingSection != null) ...[
            const SizedBox(height: 16),
            cloudSharingSection!,
          ],
        ],
      ),
    );
  }
}
