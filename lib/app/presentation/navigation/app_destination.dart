import 'package:flutter/material.dart';

class AppDestination {
  const AppDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const appDestinations = <AppDestination>[
  AppDestination(label: 'Overview', icon: Icons.grid_view_rounded),
  AppDestination(label: 'Assets', icon: Icons.pie_chart_outline_rounded),
  AppDestination(label: 'Transactions', icon: Icons.swap_vert_rounded),
  AppDestination(
    label: 'Accounts',
    icon: Icons.account_balance_wallet_outlined,
  ),
  AppDestination(label: 'Categories', icon: Icons.category_outlined),
  AppDestination(
    label: 'Asset Conversion',
    icon: Icons.currency_exchange_rounded,
  ),
  AppDestination(label: 'Projects', icon: Icons.work_outline_rounded),
  AppDestination(label: 'Tithe', icon: Icons.volunteer_activism_outlined),
  AppDestination(label: 'Reports', icon: Icons.insights_outlined),
];
