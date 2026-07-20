import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../navigation/app_destination.dart';
import 'brand_mark.dart';

class SideNav extends StatelessWidget {
  const SideNav({super.key, required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 238,
      color: ink,
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                BrandMark(),
                SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilgrim',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'TRACKER',
                      style: TextStyle(
                        color: Color(0xFF9695A4),
                        fontSize: 8,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                color: Color(0xFF777785),
                fontSize: 9,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D39),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFF3B3B47)),
            ),
            child: const Row(
              children: [
                CircleAvatar(radius: 4, backgroundColor: Color(0xFF9DE6C0)),
                SizedBox(width: 10),
                Text(
                  'Personal',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Spacer(),
                Icon(Icons.expand_more, color: Color(0xFF9998A6), size: 18),
              ],
            ),
          ),
          const SizedBox(height: 26),
          for (var index = 0; index < appDestinations.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () {
                  onSelect(index);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: selected == index
                        ? const Color(0xFF343440)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        appDestinations[index].icon,
                        size: 18,
                        color: selected == index
                            ? const Color(0xFFA995FF)
                            : const Color(0xFF9796A5),
                      ),
                      const SizedBox(width: 13),
                      Text(
                        appDestinations[index].label,
                        style: TextStyle(
                          color: selected == index
                              ? Colors.white
                              : const Color(0xFF9796A5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF393945)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Color(0xFF284737),
                  child: Icon(Icons.check, size: 13, color: Color(0xFF73D69F)),
                ),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All synced',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Just now / Local-first',
                      style: TextStyle(color: Color(0xFF777785), fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
