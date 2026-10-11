/// Invalidates older asynchronous place searches when the query changes.
class SearchRevision {
  int _current = 0;

  int next() => ++_current;

  bool isCurrent(int revision) => revision == _current;
}
