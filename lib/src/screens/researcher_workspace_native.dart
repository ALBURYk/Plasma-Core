import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

bool get isWeb => false;

Widget buildViewer(String viewerId) {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Text(
        '3D viewer is available in the web build. Calculation and DNA FASTA work in the app.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF64748B)),
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

Future<PickFileResult?> pickPdbFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdb'],
    withData: true,
  );
  final file = result?.files.single;
  if (file == null) return null;

  final bytes =
      file.bytes ??
      (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null) return null;

  return PickFileResult(fileName: file.name, pdbText: utf8.decode(bytes));
}

Future<String> loadPdbFromRcsb(String url) async {
  final response = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 12));
  if (response.statusCode < 200 || response.statusCode > 299) {
    throw StateError('RCSB returned ${response.statusCode}');
  }
  return response.body;
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
  final request = http.MultipartRequest('POST', Uri.parse(endpoint))
    ..fields['temperature'] = temperature
    ..fields['ph'] = ph
    ..files.add(
      http.MultipartFile.fromString(
        'file',
        pdbText,
        filename: fileName.endsWith('.pdb') ? fileName : 'input.pdb',
      ),
    );

  final streamed = await request.send().timeout(const Duration(seconds: 12));
  final body = await streamed.stream.bytesToString();
  return PostResult(status: streamed.statusCode, responseText: body);
}

Future<void> downloadText(String filename, String text, String mimeType) async {
  await FilePicker.saveFile(
    dialogTitle: 'Save FASTA',
    fileName: filename,
    bytes: Uint8List.fromList(utf8.encode(text)),
    type: FileType.custom,
    allowedExtensions: const ['fasta', 'fa', 'txt'],
  );
}

void renderMolecule(String viewerId, String pdbText, Object mutationResidues) {}
