import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/tokens.dart';

/// Photo picked from the camera or gallery, already downsized on the device to save data.
typedef PickedPhoto = ({List<int> bytes, String filename});

enum PhotoAction { camera, gallery, remove }

/// Asks where the photo should come from (and offers "Remove" when one exists).
Future<PhotoAction?> choosePhotoAction(BuildContext context, {required bool hasPhoto}) =>
    showModalBottomSheet<PhotoAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, PhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: BizColors.error),
                title: const Text('Remove photo', style: TextStyle(color: BizColors.error)),
                onTap: () => Navigator.pop(context, PhotoAction.remove),
              ),
          ],
        ),
      ),
    );

Future<PickedPhoto?> pickPhoto(PhotoAction action) async {
  final file = await ImagePicker().pickImage(
    source: action == PhotoAction.camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1600, // the server stores at most 1024 px; this keeps uploads small on mobile data
    maxHeight: 1600,
    imageQuality: 85,
  );
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), filename: file.name);
}

/// Full-screen camera barcode scanner. Returns the first code read, or null if cancelled.
Future<String?> scanBarcode(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScannerPage()));

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.isNotEmpty).firstOrNull;
    if (code == null) return;
    _done = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final window = Rect.fromCenter(
      center: MediaQuery.sizeOf(context).center(Offset.zero),
      width: MediaQuery.sizeOf(context).width * 0.8,
      height: 180,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // Explicit style: the app theme's dark title colour would otherwise win over foregroundColor.
        title: const Text(
          'Scan barcode',
          style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            scanWindow: window,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera permission is needed to scan barcodes. Allow it in Settings, or type the code instead.'
                      : 'The camera could not start. Type the code instead.',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(size: Size.infinite, painter: _WindowPainter(window)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Point the camera at the barcode',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(window, const Radius.circular(Radii.md));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(frame)),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = BizColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}
