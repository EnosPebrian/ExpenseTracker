import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../widgets/master_data_list.dart';
import '../widgets/project_card.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({
    super.key,
    required this.projects,
    required this.transactions,
    required this.currencyCode,
    required this.onSave,
    this.projectIdsByName = const {},
  });

  final List<String> projects;
  final List<Transaction> transactions;
  final String currencyCode;
  final MasterDataSaveCallback onSave;
  final Map<String, String> projectIdsByName;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'WORK IN MOTION',
            title: 'Projects',
            subtitle: 'See which work is creating momentum.',
          ),
          if (projects.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No project activity yet. Add a project, then assign it to '
                  'transactions to see real totals here.',
                ),
              ),
            )
          else
            for (final project in projects) ...[
              _projectCard(project),
              const SizedBox(height: 14),
            ],
          MasterDataList(
            title: 'All projects',
            subtitle: 'Optional financial dimension for transactions',
            items: projects,
            itemLabel: 'project',
            entity: 'projects',
            onSave: onSave,
          ),
        ],
      ),
    );
  }

  Widget _projectCard(String project) {
    final projectId =
        projectIdsByName[project] ??
        project.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');
    var income = 0;
    var expenses = 0;
    for (final transaction in transactions) {
      if (transaction.projectId != projectId) continue;
      if (transaction.type == TransactionType.income) {
        income += transaction.amount;
      } else if (transaction.type == TransactionType.expense) {
        expenses += transaction.amount;
      }
    }
    return ProjectCard(
      name: project,
      income: '$currencyCode ${money(income)}',
      expenses: '$currencyCode ${money(expenses)}',
      net: '$currencyCode ${money(income - expenses)}',
    );
  }
}
