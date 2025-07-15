class UserModel {
  final String uid;
  final String username;
  final String email;
  final String profileImageUrl;

  UserModel({
    required this.uid,
    required this.username,
    required this.email,
    required this.profileImageUrl, required String name,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'email': email,
      'profileImageUrl': profileImageUrl,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'],
      username: map['username'],
      email: map['email'],
      profileImageUrl: map['profileImageUrl'], name: '',
    );
  }
}
