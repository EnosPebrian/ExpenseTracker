/// Transitional route registry.
///
/// The current application shell uses indexed navigation so desktop and
/// mobile can share the same presentation. This registry remains the seam
/// for a future GoRouter migration.
///
/// Keep this destination order aligned with:
///
/// - appDestinations
/// - the pages list in AppShell
class AppRouter {
  static const destinations = <String>[
    'Overview',
    'Assets',
    'Transactions',
    'Accounts',
    'Categories',
    'Asset Conversion',
    'Projects',
    'Tithe',
    'Reports',
  ];
}
