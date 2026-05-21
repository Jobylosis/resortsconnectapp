import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'theme.dart';

class BillSplitterPage extends StatefulWidget {
  const BillSplitterPage({super.key});

  @override
  State<BillSplitterPage> createState() => _BillSplitterPageState();
}

class _BillSplitterPageState extends State<BillSplitterPage> {
  final _billController = TextEditingController();
  int _peopleCount = 2;
  bool _usePercentages = false;
  List<double> _percentages = [50.0, 50.0];
  String? _generatedQRData;

  @override
  void dispose() {
    _billController.dispose();
    super.dispose();
  }

  void _updatePeopleCount(int newCount) {
    setState(() {
      _peopleCount = newCount;
      if (_usePercentages) {
        _percentages = List.generate(newCount, (index) => 100.0 / newCount);
      }
      _generatedQRData = null;
    });
  }

  void _generateSplit() {
    double totalBill = double.tryParse(_billController.text) ?? 0.0;
    if (totalBill <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid bill amount.')));
      return;
    }

    if (_usePercentages) {
      double sum = _percentages.fold(0, (prev, curr) => prev + curr);
      if ((sum - 100).abs() > 0.1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Percentages must add up to exactly 100%.')));
        return;
      }
    }

    List<double> splits = [];
    if (_usePercentages) {
      splits = _percentages.map((p) => totalBill * (p / 100.0)).toList();
    } else {
      double evenSplit = totalBill / _peopleCount;
      splits = List.generate(_peopleCount, (index) => evenSplit);
    }

    String qrData = "Bill Breakdown\\nTotal: ₱${totalBill.toStringAsFixed(2)}\\n\\n";
    for (int i = 0; i < splits.length; i++) {
      qrData += "Person ${i + 1}: ₱${splits[i].toStringAsFixed(2)}\\n";
    }

    setState(() {
      _generatedQRData = qrData;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Splitter', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total Bill Amount (₱)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _billController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              decoration: InputDecoration(
                hintText: 'e.g. 1500.00',
                prefixIcon: const Icon(Icons.receipt_rounded),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _generatedQRData = null),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Number of People', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_rounded, size: 20),
                        onPressed: _peopleCount > 2 ? () => _updatePeopleCount(_peopleCount - 1) : null,
                      ),
                      Text('$_peopleCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 20),
                        onPressed: _peopleCount < 20 ? () => _updatePeopleCount(_peopleCount + 1) : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            SwitchListTile(
              title: const Text('Custom Percentage Split', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Assign different % to each person'),
              value: _usePercentages,
              activeColor: AppTheme.primaryAccent,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                setState(() {
                  _usePercentages = val;
                  if (val) {
                    _percentages = List.generate(_peopleCount, (index) => 100.0 / _peopleCount);
                  }
                  _generatedQRData = null;
                });
              },
            ),

            if (_usePercentages) ...[
              const SizedBox(height: 16),
              const Text('Adjust Percentages (Must total 100%)', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (int i = 0; i < _peopleCount; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Text('Person ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Slider(
                          value: _percentages[i].clamp(0.0, 100.0),
                          min: 0,
                          max: 100,
                          activeColor: AppTheme.secondaryAccent,
                          onChanged: (val) {
                            setState(() {
                              _percentages[i] = val;
                              _generatedQRData = null;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text('${_percentages[i].toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Current Total: ${_percentages.fold(0.0, (p, c) => p + c).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (_percentages.fold(0.0, (p, c) => p + c) - 100).abs() < 0.1 ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _generateSplit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Calculate & Generate QR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),

            if (_generatedQRData != null) ...[
              const SizedBox(height: 40),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  children: [
                    const Text('Scan for Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: QrImageView(
                        data: _generatedQRData!,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _generatedQRData!.replaceAll('\\n', '\n'),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
