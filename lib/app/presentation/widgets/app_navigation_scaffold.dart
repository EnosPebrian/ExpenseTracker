import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../navigation/app_destination.dart';
import 'side_nav.dart';
import 'top_bar.dart';

class AppNavigationScaffold extends StatelessWidget {
  const AppNavigationScaffold({
    super.key,
    required this.selected,
    required this.child,
    required this.onSelect,
    required this.onQuickAdd,
  }) : assert(
         selected >= 0 && selected < appDestinations.length,
         'Selected destination is outside appDestinations.',
       );

  final int selected;
  final Widget child;
  final ValueChanged<int> onSelect;
  final VoidCallback onQuickAdd;

  int get _mobileSelectedIndex {
    return selected < 3 ? selected : 3;
  }

  Future<void> _showMoreDestinations(BuildContext context) async {
    final destinationIndex = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'More',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              for (var index = 3; index < appDestinations.length; index++)
                ListTile(
                  selected: selected == index,
                  selectedColor: violet,
                  selectedTileColor: const Color(0xFFF1EEFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(appDestinations[index].icon),
                  title: Text(
                    appDestinations[index].label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: selected == index
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext, index);
                  },
                ),
            ],
          ),
        );
      },
    );

    if (destinationIndex != null) {
      onSelect(destinationIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;

    return Scaffold(
      body: Row(
        children: [
          if (wide) SideNav(selected: selected, onSelect: onSelect),
          Expanded(
            child: Column(
              children: [
                TopBar(
                  title: appDestinations[selected].label,
                  onAdd: onQuickAdd,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              height: 66,
              selectedIndex: _mobileSelectedIndex,
              onDestinationSelected: (index) {
                if (index == 3) {
                  _showMoreDestinations(context);
                  return;
                }

                onSelect(index);
              },
              destinations: [
                NavigationDestination(
                  icon: Icon(appDestinations[0].icon),
                  label: appDestinations[0].label,
                ),
                NavigationDestination(
                  icon: Icon(appDestinations[1].icon),
                  label: appDestinations[1].label,
                ),
                NavigationDestination(
                  icon: Icon(appDestinations[2].icon),
                  label: appDestinations[2].label,
                ),
                const NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'More',
                ),
              ],
            ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton(
              onPressed: onQuickAdd,
              backgroundColor: violet,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
    );
  }
}
