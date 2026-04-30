import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.file,
    required this.title,
    this.isViewOnce = false,
  });

  final File file;
  final String title;

  /// When [true] the save action is blocked and a snackbar is shown instead.
  final bool isViewOnce;

  Future<void> _saveToDevice(BuildContext context) async {
    if (isViewOnce) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Cannot save view-once media.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(dir.path, 'CipherChat'));
      if (!destDir.existsSync()) destDir.createSync(recursive: true);

      final fileName = p.basename(file.path).isEmpty
          ? 'image.jpg'
          : p.basename(file.path);
      final dest = File(p.join(destDir.path, fileName));
      await file.copy(dest.path);

      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Saved to ${dest.path}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Could not save image: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: isViewOnce ? 'Cannot save view-once media' : 'Save image',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _saveToDevice(context),
          ),
        ],
      ),
      body: InteractiveViewer(child: Center(child: Image.file(file))),
    );
  }
}
