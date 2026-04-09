class GroupJoinResult {
  const GroupJoinResult({
    required this.status,
    this.groupId,
    this.message,
  });

  final String status;
  final String? groupId;
  final String? message;

  bool get isJoined => status == 'joined' || status == 'already_member';
  bool get isAlreadyMember => status == 'already_member';

  factory GroupJoinResult.fromJson(Map<String, dynamic> json) {
    return GroupJoinResult(
      status: json['status']?.toString() ?? 'error',
      groupId: json['group_id']?.toString(),
      message: json['message']?.toString(),
    );
  }
}
