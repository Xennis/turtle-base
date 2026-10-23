/// Value checks of the base field types (see base_field_type.dart).
library;

bool isValidNumber(String value) => num.tryParse(value) != null;
