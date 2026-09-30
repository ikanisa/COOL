import 'dart:js_interop';
import 'admin_roster_checkpoint.dart';
@JS('window.sessionStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key,String value);
  external void removeItem(String key);
}
class _BrowserStore implements RosterBookmarkStore {
  static const key='collect.admin.roster.recovery.v1';
  @override String? read()=>_storage.getItem(key);
  @override void write(String value)=>_storage.setItem(key,value);
  @override void clear()=>_storage.removeItem(key);
}
RosterBookmarkStore createRosterBookmarkStore()=>_BrowserStore();
