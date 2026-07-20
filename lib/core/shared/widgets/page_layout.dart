import 'package:flutter/material.dart';

import '../../design/app_colors.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: child,
        ),
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.kicker,
    required this.title,
    required this.subtitle,
  });

  final String kicker;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            style: const TextStyle(
              color: muted,
              fontSize: 9,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            style: const TextStyle(
              color: ink,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class ResponsivePair extends StatelessWidget {
  const ResponsivePair({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 840,
    this.spacing = 14,
    this.leftFlex = 8,
    this.rightFlex = 5,
  });

  final Widget left;
  final Widget right;
  final double breakpoint;
  final double spacing;
  final int leftFlex;
  final int rightFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > breakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: leftFlex, child: left),
              SizedBox(width: spacing),
              Expanded(flex: rightFlex, child: right),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            SizedBox(height: spacing),
            right,
          ],
        );
      },
    );
  }
}

class PanelTitle extends StatelessWidget {
  const PanelTitle(this.title, this.subtitle, {super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: muted, fontSize: 10)),
      ],
    );
  }
}

class MetricSmall extends StatelessWidget {
  const MetricSmall(
    this.label,
    this.value, {
    super.key,
    this.labelColor = muted,
    this.valueColor = ink,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 9)),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
