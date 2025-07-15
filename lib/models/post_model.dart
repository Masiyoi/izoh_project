import 'package:cloud_firestore/cloud_firestore.dart';

class PostModel {
  final String id;
  final String uid;
  final String? caption;
  final String? mediaUrl;
  final String? mediaType; // 'image' or 'video'
  final DateTime timestamp;

  PostModel({
    required this.id,
    required this.uid,
    this.caption,
    this.mediaUrl,
    this.mediaType,
    required this.timestamp,
  });

  factory PostModel.fromMap(Map<String, dynamic> map) {
    return PostModel(
      id: map['id'],
      uid: map['uid'],
      caption: map['caption'],
      mediaUrl: map['mediaUrl'],
      mediaType: map['mediaType'],
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'caption': caption,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
