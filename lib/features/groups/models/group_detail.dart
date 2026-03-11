import 'group.dart';
import 'group_contribution.dart';
import 'group_member.dart';

class GroupDetail {
  const GroupDetail({
    required this.group,
    this.members = const <GroupMember>[],
    this.recentContributions = const <GroupContribution>[],
    this.isMember = false,
  });

  final Group group;
  final List<GroupMember> members;
  final List<GroupContribution> recentContributions;
  final bool isMember;

  GroupDetail copyWith({
    Group? group,
    List<GroupMember>? members,
    List<GroupContribution>? recentContributions,
    bool? isMember,
  }) {
    return GroupDetail(
      group: group ?? this.group,
      members: members ?? this.members,
      recentContributions: recentContributions ?? this.recentContributions,
      isMember: isMember ?? this.isMember,
    );
  }
}
