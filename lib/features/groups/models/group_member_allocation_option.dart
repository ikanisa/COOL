class GroupMemberAllocationOption {
  const GroupMemberAllocationOption({
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;

  factory GroupMemberAllocationOption.fromJson(Map<String, dynamic> json) {
    final displayName = json['display_name']?.toString().trim() ?? '';
    return GroupMemberAllocationOption(
      userId: json['user_id']?.toString() ?? '',
      displayName: displayName.isEmpty ? 'Member' : displayName,
    );
  }
}
