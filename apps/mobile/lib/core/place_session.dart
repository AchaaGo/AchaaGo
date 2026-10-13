import 'formatting.dart';

/// The Google Places billing session of one address-typing session, as in
/// apps/web's `sessionToken` ref: every search in the session and the final
/// place lookup share one token, so Google bills them as a single request
/// instead of one per keystroke.
///
/// A session starts with the first search ([token]) and ends ([end]) when a
/// place is chosen, the field is cleared or switched, the map is tapped, or
/// the screen closes.
class PlaceSession {
  String? _token;

  /// The token for the next search call; created on first use.
  String get token => _token ??= newPlaceSessionToken();

  /// The token to spend on the place lookup, or null when no search has run.
  String? get current => _token;

  void end() => _token = null;
}
