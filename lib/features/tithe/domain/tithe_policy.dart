/// A single immutable tithe-rate version.
class TithePolicyVersion {
  const TithePolicyVersion({required this.effectiveFrom, required this.rate});

  final DateTime effectiveFrom;

  /// Decimal representation of the rate, from 0 to 1.
  final double rate;
}

/// In-memory, effective-date versioned tithe policy.
///
/// Versions are evaluated chronologically. The latest version whose effective
/// date is on or before the requested date is always selected. Dates before
/// the first version use that first version as the policy baseline.
class TithePolicy {
  TithePolicy({required List<TithePolicyVersion> versions})
    : versions = List<TithePolicyVersion>.unmodifiable(versions) {
    if (this.versions.isEmpty) {
      throw ArgumentError.value(
        versions,
        'versions',
        'At least one version is required.',
      );
    }
    for (var index = 0; index < this.versions.length; index++) {
      final version = this.versions[index];
      if (version.rate < 0 || version.rate > 1) {
        throw ArgumentError.value(
          version.rate,
          'versions[$index].rate',
          'Tithe rate must be between 0 and 1.',
        );
      }
      if (index > 0 &&
          !version.effectiveFrom.isAfter(
            this.versions[index - 1].effectiveFrom,
          )) {
        throw ArgumentError.value(
          versions,
          'versions',
          'Policy versions must be ordered by effective date.',
        );
      }
    }
  }

  /// The default policy for the current product period.
  ///
  /// The expression keeps the percentage definition readable without
  /// scattering a decimal literal through application code.
  static final TithePolicy defaultPolicy = TithePolicy(
    versions: [
      TithePolicyVersion(effectiveFrom: DateTime(2026, 1, 1), rate: 13 / 100),
      TithePolicyVersion(effectiveFrom: DateTime(2027, 1, 1), rate: 15 / 100),
      TithePolicyVersion(effectiveFrom: DateTime(2028, 5, 1), rate: 16 / 100),
    ],
  );

  final List<TithePolicyVersion> versions;

  double rateFor(DateTime date) {
    for (var index = versions.length - 1; index >= 0; index--) {
      final version = versions[index];
      if (!version.effectiveFrom.isAfter(date)) {
        return version.rate;
      }
    }
    return versions.first.rate;
  }
}
