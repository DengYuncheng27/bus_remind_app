import 'dart:js_interop';

@JS('navigator.standalone')
external JSBoolean? get _appleStandalone;

@JS('window.matchMedia')
external _MediaQuery _matchMedia(JSString query);

extension type _MediaQuery(JSObject _) implements JSObject {
  external JSBoolean get matches;
}

bool get isStandaloneWebApp =>
    (_appleStandalone?.toDart ?? false) ||
    _matchMedia('(display-mode: standalone)'.toJS).matches.toDart;
