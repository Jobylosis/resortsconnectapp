import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'theme.dart';

class BillSplitterPage extends StatefulWidget {
  final double? initialAmount;
  final String? resortGCash;
  final List<Map<String, dynamic>>? addons;
  const BillSplitterPage({super.key, this.initialAmount, this.resortGCash, this.addons});

  @override
  State<BillSplitterPage> createState() => _BillSplitterPageState();
}

class _BillSplitterPageState extends State<BillSplitterPage> {
  late final TextEditingController _billController;
  late final TextEditingController _paymentInfoController;
  int _peopleCount = 2;
  String _splitMode = 'equal'; // 'equal', 'percentage', 'itemized'
  List<double> _percentages = [50.0, 50.0];
  List<String> _personNames = ['Friend 1', 'Friend 2'];
  List<Map<String, dynamic>> _items = [
    {'name': '', 'amount': '', 'assignedTo': 'Friend 1'}
  ];
  String? _generatedQRData;
  List<Map<String, dynamic>>? _individualQRs;

  @override
  void initState() {
    super.initState();
    _billController = TextEditingController(
      text: widget.initialAmount != null ? widget.initialAmount.toString() : '',
    );
    _paymentInfoController = TextEditingController();
  }

  @override
  void dispose() {
    _billController.dispose();
    _paymentInfoController.dispose();
    super.dispose();
  }

  void _updatePeopleCount(int newCount) {
    setState(() {
      _peopleCount = newCount;
      if (_splitMode == 'percentage') {
        _percentages = List.generate(newCount, (index) => 100.0 / newCount);
      }
      _personNames = List.generate(newCount, (index) => 'Friend ${index + 1}');
      _generatedQRData = null;
      _individualQRs = null;
    });
  }

  void _generateSplit() {
    double totalBill = double.tryParse(_billController.text) ?? 0.0;

    if (_splitMode == 'itemized') {
      double itemsTotal = _items.fold(
          0.0,
          (sum, item) =>
              sum + (double.tryParse(item['amount'].toString()) ?? 0.0));
      totalBill = itemsTotal;
    }

    if (totalBill <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter a valid bill amount or items.')));
      return;
    }

    if (_splitMode == 'percentage') {
      double sum = _percentages.fold(0, (prev, curr) => prev + curr);
      if ((sum - 100).abs() > 0.1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Percentages must add up to exactly 100%.')));
        return;
      }
    }

    String qrData =
        "💰 Bill Split Summary\nTotal: ₱${totalBill.toStringAsFixed(2)}\n\n";
    List<Map<String, dynamic>> indQRs = [];
    String paymentSuffix = _paymentInfoController.text.trim().isNotEmpty
        ? "\n\nSend Payment To:\n${_paymentInfoController.text.trim()}"
        : "";

    if (_splitMode == 'percentage') {
      qrData += "Percentage Breakdown:\n";
      for (int i = 0; i < _percentages.length; i++) {
        double amt = totalBill * (_percentages[i] / 100.0);
        qrData +=
            "- ${_personNames[i]}: ₱${amt.toStringAsFixed(2)} (${_percentages[i].toStringAsFixed(1)}%)\n";
        indQRs.add({
          'name': _personNames[i],
          'amount': amt,
          'text':
              "💰 Personal Bill\nName: ${_personNames[i]}\nTotal Owed: ₱${amt.toStringAsFixed(2)}\nShare: ${_percentages[i].toStringAsFixed(1)}%$paymentSuffix"
        });
      }
    } else if (_splitMode == 'itemized') {
      qrData += "Itemized Breakdown:\n";
      Map<String, double> personTotals = {};
      Map<String, List<Map<String, dynamic>>> personItems = {};
      for (var item in _items) {
        String name =
            item['name'].toString().trim().isEmpty ? 'Item' : item['name'];
        String who = item['assignedTo'].toString().trim().isEmpty
            ? 'Unassigned'
            : item['assignedTo'];
        double amt = double.tryParse(item['amount'].toString()) ?? 0.0;
        if (amt > 0) {
          qrData += "- $name ($who): ₱${amt.toStringAsFixed(2)}\n";
          personTotals[who] = (personTotals[who] ?? 0) + amt;
          if (personItems[who] == null) personItems[who] = [];
          personItems[who]!.add({'name': name, 'amt': amt});
        }
      }
      qrData += "\nEach Person Pays:\n";
      personTotals.forEach((who, amt) {
        qrData += "$who: ₱${amt.toStringAsFixed(2)}\n";
        String text =
            "💰 Personal Bill\nName: $who\nTotal Owed: ₱${amt.toStringAsFixed(2)}\n\nItems:\n";
        for (var item in personItems[who]!) {
          text += "- ${item['name']}: ₱${item['amt'].toStringAsFixed(2)}\n";
        }
        text += paymentSuffix;
        indQRs.add({'name': who, 'amount': amt, 'text': text});
      });
    } else {
      double evenSplit = totalBill / _peopleCount;
      qrData +=
          "Split by: $_peopleCount people\nEach pays: ₱${evenSplit.toStringAsFixed(2)}\n";
    }

    if (paymentSuffix.isNotEmpty) {
      qrData += paymentSuffix;
    }

    setState(() {
      _generatedQRData = qrData;
      _individualQRs = _splitMode == 'equal' ? null : indQRs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Splitter',
            style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total Bill Amount (₱)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _billController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
              ],
              decoration: InputDecoration(
                hintText: 'e.g. 1500.00',
                prefixIcon: const Icon(Icons.receipt_rounded),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _generatedQRData = null),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Payment Info (Optional)',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (widget.resortGCash != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _paymentInfoController.text = widget.resortGCash!;
                        _generatedQRData = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 30),
                      foregroundColor: AppTheme.primaryAccent,
                    ),
                    child: const Text('Use Resort GCash',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _paymentInfoController,
              decoration: InputDecoration(
                hintText: 'e.g. GCash 09123456789',
                prefixIcon: const Icon(Icons.account_balance_wallet_rounded),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _generatedQRData = null),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Number of People',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_rounded, size: 20),
                        onPressed: _peopleCount > 2
                            ? () => _updatePeopleCount(_peopleCount - 1)
                            : null,
                      ),
                      Text('$_peopleCount',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 20),
                        onPressed: _peopleCount < 20
                            ? () => _updatePeopleCount(_peopleCount + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'equal',
                    label: Text('Equal', style: TextStyle(fontSize: 12))),
                ButtonSegment(
                    value: 'percentage',
                    label: Text('Percentage', style: TextStyle(fontSize: 12))),
                ButtonSegment(
                    value: 'itemized',
                    label: Text('Itemized', style: TextStyle(fontSize: 12))),
              ],
              selected: {_splitMode},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _splitMode = newSelection.first;
                  if (_splitMode == 'percentage') {
                    _percentages = List.generate(
                        _peopleCount, (index) => 100.0 / _peopleCount);
                    _personNames = List.generate(
                        _peopleCount, (index) => 'Friend ${index + 1}');
                  }
                  _generatedQRData = null;
                  _individualQRs = null;
                });
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected))
                    return AppTheme.primaryAccent.withValues(alpha: 0.1);
                  return Theme.of(context).colorScheme.surface;
                }),
              ),
            ),
            const SizedBox(height: 24),
            if (_splitMode == 'itemized') ...[
              const Text('Add Items (Total automatically calculated)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 12),
              for (int i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: (widget.addons != null && widget.addons!.isNotEmpty) ? DropdownButtonFormField<String>(
                          value: _items[i]['name'].toString().isEmpty ? null : _items[i]['name'],
                          decoration: InputDecoration(
                            hintText: 'Item name',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          items: [
                            ...{
                              for (var a in widget.addons!)
                                a['name'].toString(): a
                            }.values.map((a) => DropdownMenuItem<String>(
                              value: a['name'].toString(),
                              child: Text(a['name'].toString(), style: const TextStyle(fontSize: 13)),
                            )),
                            const DropdownMenuItem<String>(value: 'Custom Item', child: Text('Custom Item', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _items[i]['name'] = val;
                                final addon = widget.addons!.cast<Map<String,dynamic>?>().firstWhere((a) => a != null && a['name'] == val, orElse: () => null);
                                if (addon != null && addon['price'] != null) {
                                  _items[i]['amount'] = addon['price'].toString();
                                }
                                _generatedQRData = null;
                              });
                            }
                          },
                        ) : TextFormField(
                          initialValue: _items[i]['name'],
                          decoration: InputDecoration(
                            hintText: 'Item name',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) => setState(() {
                            _items[i]['name'] = val;
                            _generatedQRData = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: _items[i]['assignedTo'],
                          decoration: InputDecoration(
                            hintText: 'Who pays?',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) => setState(() {
                            _items[i]['assignedTo'] = val;
                            _generatedQRData = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          key: ValueKey('amount_${i}_${_items[i]['amount']}'),
                          initialValue: _items[i]['amount'].toString(),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          decoration: InputDecoration(
                            hintText: 'Amount',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) => setState(() {
                            _items[i]['amount'] = val;
                            _generatedQRData = null;
                          }),
                        ),
                      ),
                      if (_items.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () => setState(() {
                            _items.removeAt(i);
                            _generatedQRData = null;
                          }),
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _items.add({
                    'name': '',
                    'amount': '',
                    'assignedTo': 'Friend ${_items.length + 1}'
                  });
                  _generatedQRData = null;
                }),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Another Item'),
              ),
            ] else if (_splitMode == 'percentage') ...[
              const SizedBox(height: 16),
              const Text('Adjust Percentages (Must total 100%)',
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (int i = 0; i < _peopleCount; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: _personNames[i],
                          decoration: InputDecoration(
                            hintText: 'Name',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                          onChanged: (val) => setState(() {
                            _personNames[i] = val;
                            _generatedQRData = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
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
                        child: Text('${_percentages[i].toStringAsFixed(1)}%',
                            textAlign: TextAlign.right,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
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
                    color:
                        (_percentages.fold(0.0, (p, c) => p + c) - 100).abs() <
                                0.1
                            ? Colors.green
                            : Colors.red,
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Calculate & Generate QR',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
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
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  children: [
                    const Text('Scan for Full Breakdown',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      child: QrImageView(
                        data: _generatedQRData!,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _generatedQRData!,
                      style: const TextStyle(fontSize: 14, height: 1.5, fontFamily: 'monospace'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
