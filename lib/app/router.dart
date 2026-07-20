/// Transitional route registry. The current shell uses indexed navigation so
/// desktop and mobile can share the same presentation. This registry is the
/// seam for the future GoRouter migration.
class AppRouter {
  static const destinations = <String>[
    'Overview',
    'Transactions',
    'Accounts',
    'Categories',
    'Asset Conversion',
    'Projects',
    'Tithe',
    'Reports',
  ];
}
