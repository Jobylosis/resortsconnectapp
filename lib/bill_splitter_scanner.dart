import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BillSplitterScanner extends StatefulWidget {
  const BillSplitterScanner({super.key});

  @override
  State<BillSplitterScanner> createState() => _BillSplitterScannerState();
}

class _BillSplitterScannerState extends State<BillSplitterScanner> {
  bool _isProcessing = false;
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _processScannedCode(String scannedData) {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _controller.stop();
    Navigator.pop(context, scannedData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Split Bill',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final String? code = barcode.rawValue ?? barcode.displayValue;
                if (code != null) {
                  _processScannedCode(code);
                  break;
                }
              }
            },
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Use your camera to scan a friend\'s Bill Breakdown QR Code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
