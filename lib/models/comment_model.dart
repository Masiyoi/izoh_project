class CommentModel {
  final String id;
  final String postId;
  final String userId;
  final String text;
  final DateTime timestamp;

  CommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'postId': postId,
      'userId': userId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory CommentModel.fromMap(Map<String, dynamic> map) {
    return CommentModel(
      id: map['id'],
      postId: map['postId'],
      userId: map['userId'],
      text: map['text'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}
