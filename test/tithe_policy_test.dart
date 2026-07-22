import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/tithe/domain/tithe_policy.dart';

TithePolicy policy() => TithePolicy(
  versions: [
    TithePolicyVersion(effectiveFrom: DateTime(2026, 1, 1), rate: 13 / 100),
    TithePolicyVersion(effectiveFrom: DateTime(2027, 1, 1), rate: 15 / 100),
    TithePolicyVersion(effectiveFrom: DateTime(2028, 5, 1), rate: 16 / 100),
  ],
);

void main() {
  final versionedPolicy = policy();

  test('default policy contains the shipped historical versions', () {
    expect(TithePolicy.defaultPolicy.rateFor(DateTime(2026, 7, 1)), 13 / 100);
    expect(TithePolicy.defaultPolicy.rateFor(DateTime(2027, 7, 1)), 15 / 100);
    expect(TithePolicy.defaultPolicy.rateFor(DateTime(2028, 7, 1)), 16 / 100);
  });

  test('uses the version on its exact effective date', () {
    expect(versionedPolicy.rateFor(DateTime(2027, 1, 1)), 15 / 100);
    expect(versionedPolicy.rateFor(DateTime(2028, 5, 1)), 16 / 100);
  });

  test('keeps the prior version on the day before a change', () {
    expect(versionedPolicy.rateFor(DateTime(2026, 12, 31, 23, 59)), 13 / 100);
    expect(versionedPolicy.rateFor(DateTime(2028, 4, 30, 23, 59)), 15 / 100);
  });

  test('uses the new version on the day after a change', () {
    expect(versionedPolicy.rateFor(DateTime(2027, 1, 2)), 15 / 100);
    expect(versionedPolicy.rateFor(DateTime(2028, 5, 2)), 16 / 100);
  });

  test('supports multiple historical versions without mutating history', () {
    expect(versionedPolicy.rateFor(DateTime(2026, 6, 1)), 13 / 100);
    expect(versionedPolicy.rateFor(DateTime(2027, 6, 1)), 15 / 100);
    expect(versionedPolicy.rateFor(DateTime(2028, 6, 1)), 16 / 100);
    expect(versionedPolicy.versions.length, 3);
  });

  test('uses the latest known version for future dates', () {
    expect(versionedPolicy.rateFor(DateTime(2040, 12, 31)), 16 / 100);
  });

  test('uses the first version as the baseline before the first boundary', () {
    expect(versionedPolicy.rateFor(DateTime(2025, 12, 31, 23, 59)), 13 / 100);
  });

  test('rejects invalid or unordered policy versions', () {
    expect(() => TithePolicy(versions: const []), throwsArgumentError);
    expect(
      () => TithePolicy(
        versions: [
          TithePolicyVersion(
            effectiveFrom: DateTime(2027, 1, 1),
            rate: 15 / 100,
          ),
          TithePolicyVersion(
            effectiveFrom: DateTime(2026, 1, 1),
            rate: 13 / 100,
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => TithePolicy(
        versions: [
          TithePolicyVersion(
            effectiveFrom: DateTime(2026, 1, 1),
            rate: 101 / 100,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
