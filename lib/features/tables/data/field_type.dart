/// v1 field types.
enum FieldType { text, number, date, url, relation, select, multiSelect }

extension FieldTypeLabel on FieldType {
  String get label => switch (this) {
    FieldType.text => 'Text',
    FieldType.number => 'Number',
    FieldType.date => 'Date',
    FieldType.url => 'URL',
    FieldType.relation => 'Relation',
    FieldType.select => 'Select',
    FieldType.multiSelect => 'Multi-select',
  };

  bool get isSelect => this == FieldType.select || this == FieldType.multiSelect;
}
