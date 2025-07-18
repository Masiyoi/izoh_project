import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/post_model.dart';
import '../services/post_service.dart';
import '../services/storage_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _captionController = TextEditingController();
  XFile? _mediaFile;
  bool _isVideo = false;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  VideoPlayerController? _videoController;

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final pickedFile = isVideo
        ? await _picker.pickVideo(source: source)
        : await _picker.pickImage(source: source);

    if (pickedFile != null) {
      setState(() {
        _mediaFile = pickedFile;
        _isVideo = isVideo;
        if (isVideo && !kIsWeb) {
          _videoController?.dispose();
          _videoController = VideoPlayerController.file(File(_mediaFile!.path))
            ..initialize().then((_) {
              setState(() {});
              _videoController?.setLooping(true);
              _videoController?.play();
            });
        }
      });
    }
  }

  Future<void> _submitPost() async {
    if (_captionController.text.trim().isEmpty && _mediaFile == null) return;

    setState(() => _isLoading = true);
    final storageService = StorageService();
    String? imageUrl;
    String? mediaType;
    if (_mediaFile != null) {
      if (!kIsWeb) {
        imageUrl = await storageService.uploadFile(File(_mediaFile!.path), 'posts', onProgress: (progress) {  });
      } else {
        imageUrl = await storageService.uploadXFile(_mediaFile!, 'posts');
      }
      mediaType = _isVideo ? 'video' : 'image';
    }

    final post = PostModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      caption: _captionController.text.trim(),
      imageUrl: imageUrl,
      mediaType: mediaType,
      timestamp: DateTime.now(),
      uid: '',
    );

    if (!mounted) return;
    await Provider.of<PostService>(context, listen: false).createPost(post);

    setState(() => _isLoading = false);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
        backgroundColor: Colors.deepPurple,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submitPost,
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'Post',
                    style: TextStyle(color: Colors.white),
                  ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _captionController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'What\'s on your mind?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_mediaFile != null)
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: _isVideo
                    ? (!kIsWeb && _videoController != null && _videoController!.value.isInitialized
                        ? AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          )
                        : const Center(child: CircularProgressIndicator()))
                    : kIsWeb
                        ? Image.network(_mediaFile!.path, fit: BoxFit.cover)
                        : Image.file(File(_mediaFile!.path), fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickMedia(ImageSource.gallery),
                  icon: const Icon(Icons.image),
                  label: const Text('Pick Image'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Pick Video'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
