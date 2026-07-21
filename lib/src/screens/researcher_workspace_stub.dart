import 'package:flutter/material.dart';

bool get isWeb => false;

Widget buildViewer(String viewerId) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Web-only 3D viewer is not available on this platform.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF64748B)),
      ),
    ),
  );
}

void registerViewer(String viewerId) {}

class PickFileResult {
  final String fileName;
  final String pdbText;

  const PickFileResult({required this.fileName, required this.pdbText});
}

Future<PickFileResult?> pickPdbFile() async => null;

Future<String> loadPdbFromRcsb(String url) async {
  throw UnsupportedError('Web-only feature');
}

class PostResult {
  final int status;
  final String responseText;

  const PostResult({required this.status, required this.responseText});
}

Future<PostResult> postOptimization(
  String endpoint,
  String fileName,
  String pdbText,
  String temperature,
  String ph,
) async {
  throw UnsupportedError('Web-only feature');
}

void downloadText(String filename, String text, String mimeType) {}

void renderMolecule(String viewerId, String pdbText, Object mutationResidues) {}
