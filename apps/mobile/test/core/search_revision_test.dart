import 'package:achaago_mobile/core/search_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the newest place-search response may update suggestions', () {
    final revision = SearchRevision();
    final first = revision.next();
    final second = revision.next();

    expect(revision.isCurrent(first), isFalse);
    expect(revision.isCurrent(second), isTrue);
    revision.next(); // Selection, clear, or switching the address tab.
    expect(revision.isCurrent(second), isFalse);
  });
}
