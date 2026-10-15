import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Na računaru pita gdje da sačuva fajl, u pregledaču ga preuzima, a na telefonu
/// ga nudi za dijeljenje (Viber, mail, Drive), jer telefon nema izbor foldera.
Future<void> saveFile(
  BuildContext context, {
  required Uint8List bytes,
  required String name,
  required String mimeType,
  required String label,
  required String extension,
}) async {
  final file = XFile.fromData(bytes, mimeType: mimeType, name: name);
  if (kIsWeb) {
    await file.saveTo(name);
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    // Dugme koje je otvorilo dijeljenje; iPad iz njega otvara meni.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [name],
        subject: name,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    return;
  }
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: label, extensions: [extension]),
    ],
  );
  if (location == null) return;
  await file.saveTo(location.path);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$label je sačuvan: ${location.path}')),
  );
}
