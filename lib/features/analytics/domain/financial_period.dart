enum FinancialPeriodPreset {
  thisMonth,
  last2Months,
  last3Months,
  last6Months,
  last12Months,
  yearToDate,
  quarter1,
  quarter2,
  quarter3,
  quarter4,
  lastYear,
  custom,
}

class FinancialPeriod {
  const FinancialPeriod({
    required this.start,
    required this.endExclusive,
    required this.preset,
  });

  final DateTime start;
  final DateTime endExclusive;
  final FinancialPeriodPreset preset;

  factory FinancialPeriod.thisMonth(DateTime referenceDate) {
    return FinancialPeriod.trailingMonths(
      referenceDate,
      1,
      preset: FinancialPeriodPreset.thisMonth,
    );
  }

  factory FinancialPeriod.last2Months(DateTime referenceDate) {
    return FinancialPeriod.trailingMonths(
      referenceDate,
      2,
      preset: FinancialPeriodPreset.last2Months,
    );
  }

  factory FinancialPeriod.last3Months(DateTime referenceDate) {
    return FinancialPeriod.trailingMonths(
      referenceDate,
      3,
      preset: FinancialPeriodPreset.last3Months,
    );
  }

  factory FinancialPeriod.last6Months(DateTime referenceDate) {
    return FinancialPeriod.trailingMonths(
      referenceDate,
      6,
      preset: FinancialPeriodPreset.last6Months,
    );
  }

  factory FinancialPeriod.last12Months(DateTime referenceDate) {
    return FinancialPeriod.trailingMonths(
      referenceDate,
      12,
      preset: FinancialPeriodPreset.last12Months,
    );
  }

  factory FinancialPeriod.trailingMonths(
    DateTime referenceDate,
    int monthCount, {
    required FinancialPeriodPreset preset,
  }) {
    if (monthCount <= 0) {
      throw ArgumentError.value(
        monthCount,
        'monthCount',
        'Month count must be positive.',
      );
    }

    final start = DateTime(
      referenceDate.year,
      referenceDate.month - monthCount + 1,
    );

    final endExclusive = DateTime(referenceDate.year, referenceDate.month + 1);

    return FinancialPeriod(
      start: start,
      endExclusive: endExclusive,
      preset: preset,
    );
  }

  factory FinancialPeriod.yearToDate(DateTime referenceDate) {
    final normalizedDate = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );

    return FinancialPeriod(
      start: DateTime(referenceDate.year),
      endExclusive: normalizedDate.add(const Duration(days: 1)),
      preset: FinancialPeriodPreset.yearToDate,
    );
  }

  factory FinancialPeriod.quarter1(DateTime referenceDate) {
    return FinancialPeriod._quarter(
      referenceDate.year,
      1,
      FinancialPeriodPreset.quarter1,
    );
  }

  factory FinancialPeriod.quarter2(DateTime referenceDate) {
    return FinancialPeriod._quarter(
      referenceDate.year,
      2,
      FinancialPeriodPreset.quarter2,
    );
  }

  factory FinancialPeriod.quarter3(DateTime referenceDate) {
    return FinancialPeriod._quarter(
      referenceDate.year,
      3,
      FinancialPeriodPreset.quarter3,
    );
  }

  factory FinancialPeriod.quarter4(DateTime referenceDate) {
    return FinancialPeriod._quarter(
      referenceDate.year,
      4,
      FinancialPeriodPreset.quarter4,
    );
  }

  factory FinancialPeriod._quarter(
    int year,
    int quarter,
    FinancialPeriodPreset preset,
  ) {
    final startMonth = ((quarter - 1) * 3) + 1;

    return FinancialPeriod(
      start: DateTime(year, startMonth),
      endExclusive: DateTime(year, startMonth + 3),
      preset: preset,
    );
  }

  factory FinancialPeriod.lastYear(DateTime referenceDate) {
    final year = referenceDate.year - 1;

    return FinancialPeriod(
      start: DateTime(year),
      endExclusive: DateTime(year + 1),
      preset: FinancialPeriodPreset.lastYear,
    );
  }

  factory FinancialPeriod.custom({
    required DateTime start,
    required DateTime endInclusive,
  }) {
    final normalizedStart = DateTime(start.year, start.month, start.day);

    final normalizedEnd = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
    );

    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError('The end date cannot be before the start date.');
    }

    return FinancialPeriod(
      start: normalizedStart,
      endExclusive: normalizedEnd.add(const Duration(days: 1)),
      preset: FinancialPeriodPreset.custom,
    );
  }

  bool contains(DateTime date) {
    return !date.isBefore(start) && date.isBefore(endExclusive);
  }

  String get label {
    return switch (preset) {
      FinancialPeriodPreset.thisMonth => 'This month',
      FinancialPeriodPreset.last2Months => 'Last 2 months',
      FinancialPeriodPreset.last3Months => 'Last 3 months',
      FinancialPeriodPreset.last6Months => 'Last 6 months',
      FinancialPeriodPreset.last12Months => 'Last 12 months',
      FinancialPeriodPreset.yearToDate => 'Year to date',
      FinancialPeriodPreset.quarter1 => 'Q1 ${start.year}',
      FinancialPeriodPreset.quarter2 => 'Q2 ${start.year}',
      FinancialPeriodPreset.quarter3 => 'Q3 ${start.year}',
      FinancialPeriodPreset.quarter4 => 'Q4 ${start.year}',
      FinancialPeriodPreset.lastYear => 'Last Year (${start.year})',
      FinancialPeriodPreset.custom =>
        '${_formatDate(start)} - '
            '${_formatDate(endExclusive.subtract(const Duration(days: 1)))}',
    };
  }

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');

    return '$day/$month/${value.year}';
  }
}
