import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'product_lookup.dart';

/// Opens the camera and returns the first product barcode it reads, or null
/// when the user goes back.
Future<String?> scanProductBarcode(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const BarcodeScannerScreen(),
      ),
    );

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where(isProductBarcode)
        .firstOrNull;
    if (code == null) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Barcode scannen'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            tooltip: 'Taschenlampe',
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error) => _ScannerError(error),
        overlayBuilder: (context, constraints) => const _ScanFrame(),
      ),
    );
  }
}

/// Frame hinting where to hold the barcode.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Barcode der Verpackung in den Rahmen halten',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError(this.error);

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Kein Zugriff auf die Kamera. Bitte in den Android-Einstellungen '
            'für Casa Pazza erlauben.',
      MobileScannerErrorCode.unsupported =>
        'Auf diesem Gerät kann nicht gescannt werden.',
      _ => 'Die Kamera konnte nicht gestartet werden.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
