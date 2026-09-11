import 'package:flutter/material.dart';

class AppDestination {
  const AppDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const appDestinations = <AppDestination>[
  AppDestination(label: 'Overview', icon: Icons.grid_view_rounded),
  AppDestination(label: 'Assets', icon: Icons.pie_chart_outline_rounded),
  AppDestination(label: 'Investments', icon: Icons.candlestick_chart_outlined),
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
  AppDestination(label: 'Budgets', icon: Icons.savings_outlined),
  AppDestination(label: 'Tithe', icon: Icons.volunteer_activism_outlined),
  AppDestination(label: 'Reports', icon: Icons.insights_outlined),
  AppDestination(label: 'Household', icon: Icons.group_outlined),
  AppDestination(label: 'Integrations', icon: Icons.hub_outlined),
  AppDestination(label: 'Backup & Export', icon: Icons.shield_outlined),
  AppDestination(label: 'Data & Sync', icon: Icons.health_and_safety_outlined),
];

abstract final class AppDestinationIndex {
  static const overview = 0;
  static const assets = 1;
  static const investments = 2;
  static const transactions = 3;
  static const accounts = 4;
  static const categories = 5;
  static const assetConversion = 6;
  static const projects = 7;
  static const budgets = 8;
  static const tithe = 9;
  static const reports = 10;
  static const household = 11;
  static const integrations = 12;
  static const backupExport = 13;
  static const dataSync = 14;
}
