class FinancialProject {
  const FinancialProject({required this.id, required this.name});

  final String id;
  final String name;

  factory FinancialProject.fromRecord(Map<String, Object?> record) {
    return FinancialProject(
      id: record['id']! as String,
      name: record['name']! as String,
    );
  }

  Map<String, Object?> toRecord() => {'id': id, 'name': name};
}
