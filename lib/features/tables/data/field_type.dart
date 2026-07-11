/// v1 field types.
enum FieldType { text, number, date, url, relation }

extension FieldTypeLabel on FieldType {
  String get label => switch (this) {
    FieldType.text => 'Text',
    FieldType.number => 'Number',
    FieldType.date => 'Date',
    FieldType.url => 'URL',
    FieldType.relation => 'Relation',
  };
}
