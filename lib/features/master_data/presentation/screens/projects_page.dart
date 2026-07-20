import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../widgets/master_data_list.dart';
import '../widgets/project_card.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.projects, required this.onSave});

  final List<String> projects;
  final MasterDataSaveCallback onSave;

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
          const ResponsivePair(
            left: ProjectCard('Client Website', 'Rp 18.5m', 'Rp 6.2m', .72),
            right: ProjectCard('Product Launch', 'Rp 8.0m', 'Rp 2.4m', .38),
          ),
          const SizedBox(height: 14),
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
}
