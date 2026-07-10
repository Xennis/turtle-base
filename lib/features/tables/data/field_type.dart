/// v1 field types. `relation` follows in a later step (PLAN.md phase 6).
enum FieldType { text, number, date, url }

extension FieldTypeLabel on FieldType {
  String get label => switch (this) {
    FieldType.text => 'Text',
    FieldType.number => 'Number',
    FieldType.date => 'Date',
    FieldType.url => 'URL',
  };
}
