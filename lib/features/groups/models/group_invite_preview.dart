import 'group.dart';

class GroupInvitePreview {
  const GroupInvitePreview({required this.group, required this.isMember});

  final Group group;
  final bool isMember;

  factory GroupInvitePreview.fromJson(Map<String, dynamic> json) {
    return GroupInvitePreview(
      group: Group.fromJson(json),
      isMember: _asBool(json['is_member']),
    );
  }
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}
