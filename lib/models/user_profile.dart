class UserProfile {
  String name;
  String avatarPath;

  UserProfile({
    this.name = '我',
    this.avatarPath = '',
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '我',
      avatarPath: json['avatar_path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'avatar_path': avatarPath,
    };
  }
}