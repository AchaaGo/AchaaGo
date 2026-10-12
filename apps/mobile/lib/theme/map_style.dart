/// Google Maps styles, the same ones the web map uses
/// (apps/web/src/components/GoogleMapView.tsx `MAP_STYLE` and
/// `DARK_MAP_STYLE`). They only change colours, so the camera, markers and
/// routes are untouched when the theme switches.
const lightMapStyle = '''
[
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#ece7dc"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#dce5cc"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]
''';

const darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#18251e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#b7c5bd"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#18251e"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#43564a"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d1b22"}]}
]
''';
