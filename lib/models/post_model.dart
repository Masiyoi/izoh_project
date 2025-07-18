
class PostModel {
  final String id;
  final String uid;
  final String? caption;
  final String? imageUrl;
  final String? mediaType; // 'image' or 'video'
  final DateTime timestamp;

  PostModel({
    required this.id,
    required this.uid,
    this.caption,
    this.imageUrl,
    this.mediaType,
    required this.timestamp,
  });

  factory PostModel.fromMap(Map<String, dynamic> map) {
    return PostModel(
      id: map['id'],
      uid: map['user_id'] ?? map['uid'],
      caption: map['caption'],
      imageUrl: map['image_url'] ?? map['mediaUrl'],
      mediaType: map['media_type'],
      timestamp: DateTime.parse(map['timestamp'].toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': uid,
      'caption': caption,
      'image_url': imageUrl,
      'media_type': mediaType,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
