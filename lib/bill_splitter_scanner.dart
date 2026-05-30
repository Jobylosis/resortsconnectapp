import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BillSplitterScanner extends StatefulWidget {
  const BillSplitterScanner({super.key});

  @override
  State<BillSplitterScanner> createState() => _BillSplitterScannerState();
}

class _BillSplitterScannerState extends State<BillSplitterScanner> {
  bool _isProcessing = false;

  void _processScannedCode(String scannedData) {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

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
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null) {
                  _processScannedCode(code);
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
                style: TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          )
        ],
      ),
    );
  }
}
