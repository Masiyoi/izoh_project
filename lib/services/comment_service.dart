import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment_model.dart';

class CommentService {
  final _commentCollection = FirebaseFirestore.instance.collection('comments');

  Future<void> addComment(CommentModel comment) async {
    await _commentCollection.doc(comment.id).set(comment.toMap());
  }

  Stream<List<CommentModel>> getComments(String postId) {
    return _commentCollection
        .where('postId', isEqualTo: postId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => CommentModel.fromMap(doc.data())).toList());
  }
}
