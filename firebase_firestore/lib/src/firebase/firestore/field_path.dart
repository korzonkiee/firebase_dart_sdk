// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/**
 * A {@code FieldPath} refers to a field in a document. The path may consist of a single field name
 * (referring to a top level field in the document), or a list of field names (referring to a nested
 * field in the document).
 */
@publicApi
class FieldPath {
  /** Matches any characters in a field path string that are reserved. */
  static final RegExp RESERVED = RegExp('[~*/\\[\\]]');

  final model.FieldPath internalPath;

  const FieldPath(this.internalPath);

  factory FieldPath.fromSegments(List<String> segments) {
    return FieldPath(model.FieldPath.fromSegments(segments));
  }

  /**
   * Creates a FieldPath from the provided field names. If more than one field name is provided, the
   * path will point to a nested field in a document.
   *
   * @param fieldNames A list of field names.
   * @return A {@code FieldPath} that points to a field location in a document.
   */
  @publicApi
  factory FieldPath.of(List<String> fieldNames) {
    Assert.checkArgument(fieldNames.isNotEmpty,
        "Invalid field path. Provided path must not be empty.");

    for (int i = 0; i < fieldNames.length; ++i) {
      Assert.checkArgument(fieldNames[i] != null && !fieldNames[i].isEmpty,
          "Invalid field name at argument ${i + 1}. Field names must not be null or empty.");
    }

    return new FieldPath.fromSegments(fieldNames);
  }

  static final FieldPath DOCUMENT_ID_INSTANCE =
      new FieldPath(model.FieldPath.keyPath);

  /**
   * Returns A special sentinel FieldPath to refer to the ID of a document. It can be used in
   * queries to sort or filter by the document ID.
   */
  @publicApi
  static FieldPath documentId() {
    return DOCUMENT_ID_INSTANCE;
  }

  /** Parses a field path string into a {@code FieldPath}, treating dots as separators. */
  static FieldPath fromDotSeparatedPath(String path) {
    Assert.checkNotNull(path, "Provided field path must not be null.");
    Assert.checkArgument(!RESERVED.hasMatch(path),
        "Invalid field path ($path). Paths must not contain '~', '*', '/', '[', or ']'");
    try {
      // By default, split() doesn't return empty leading and trailing segments. This can be enabled
      // by passing "-1" as the  limit.
      // todo handle the above
      return FieldPath.of(path.split("\\."));
    } on ArgumentError catch (_) {
      throw new ArgumentError(
          "Invalid field path ($path). Paths must not be empty, begin with '.', end with '.', or contain '..'");
    }
  }

  @override
  String toString() {
    return internalPath.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldPath &&
          runtimeType == other.runtimeType &&
          internalPath == other.internalPath;

  @override
  int get hashCode => internalPath.hashCode;
}