import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

@JS('plasmaCoreRenderMolecule')
external void _renderMoleculeJs(
  String elementId,
  String pdbText,
  JSArray<JSNumber> mutationResidues,
);

bool get isWeb => true;

Widget buildViewer(String viewerId) => HtmlElementView(viewType: viewerId);

void registerViewer(String viewerId) {
  ui_web.platformViewRegistry.registerViewFactory(viewerId, (int viewId) {
    return web.HTMLDivElement()
      ..id = viewerId
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#07111f';
  });
}

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
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;

  return PickFileResult(
    fileName: file.name,
    pdbText: String.fromCharCodes(bytes),
  );
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

  final streamed = await request.send().timeout(const Duration(seconds: 8));
  final body = await streamed.stream.bytesToString();
  return PostResult(status: streamed.statusCode, responseText: body);
}

Future<void> downloadText(String filename, String text, String mimeType) async {
  await FilePicker.saveFile(
    fileName: filename,
    bytes: Uint8List.fromList(text.codeUnits),
    type: FileType.custom,
    allowedExtensions: const ['fasta', 'fa', 'txt'],
  );
}

void renderMolecule(String viewerId, String pdbText, Object mutationResidues) {
  scheduleMicrotask(() {
    final residues = (mutationResidues as List<int>)
        .map((residue) => residue.toJS)
        .toList()
        .toJS;
    _renderMoleculeJs(viewerId, pdbText, residues);
  });
}
