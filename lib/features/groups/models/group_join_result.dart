import 'group_detail.dart';

class GroupJoinResult {
  const GroupJoinResult({required this.detail, required this.status});

  final GroupDetail detail;
  final String status;

  bool get didJoin => status == 'joined';
  bool get alreadyMember => status == 'already_member';
}
