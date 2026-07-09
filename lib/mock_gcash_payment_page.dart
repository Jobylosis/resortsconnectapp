import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class MockGCashPaymentPage extends StatefulWidget {
  final String propertyName;
  final double amount;
  final String gcashName;
  final String gcashNumber;

  const MockGCashPaymentPage({
    super.key,
    required this.propertyName,
    required this.amount,
    required this.gcashName,
    required this.gcashNumber,
  });

  @override
  State<MockGCashPaymentPage> createState() => _MockGCashPaymentPageState();
}

class _MockGCashPaymentPageState extends State<MockGCashPaymentPage> {
  int _step =
      0; // 0 = Phone Input, 1 = OTP Input, 2 = MPIN Input, 3 = Confirmation, 4 = Success Receipt
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _mpinController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  late String _generatedOtp;
  late String _refNo;

  @override
  void initState() {
    super.initState();
    _refNo = _generateRefNo();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _mpinController.dispose();
    super.dispose();
  }

  String _generateRefNo() {
    final rand = Random();
    String code = "5";
    for (int i = 0; i < 12; i++) {
      code += rand.nextInt(10).toString();
    }
    return code;
  }

  void _sendOtp() {
    final rand = Random();
    _generatedOtp = (100000 + rand.nextInt(900000)).toString();

    setState(() => _step = 1);

    // Simulate sending OTP message via popup
    Future.microtask(() {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'GCash: Your verification code (OTP) is $_generatedOtp. Do not share this code.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF0038A8),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    });
  }

  void _verifyOtp() {
    if (_otpController.text.trim() == _generatedOtp ||
        _otpController.text.trim() == "123456") {
      setState(() => _step = 2);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Invalid verification code. Please check the SnackBar message.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _verifyMpin() {
    if (_mpinController.text.length == 4) {
      setState(() => _step = 3);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MPIN must be 4 digits.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF0038A8), // GCash Dark Blue
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0038A8),
          secondary: Color(0xFF0C56E9), // GCash Light Blue
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0038A8),
          elevation: 0,
          leading: _step < 4
              ? IconButton(
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () {
                    if (_step > 0) {
                      setState(() => _step--);
                    } else {
                      Navigator.pop(context, null);
                    }
                  },
                )
              : null,
          title: Text(
            'GCash Secure Checkout',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Top merchant summary banner
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF0038A8),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.propertyName,
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₱${widget.amount.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: _buildStepContent(),
                    ),
                  ),
                ),
              ),

              // GCash footer brand details
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.shield_rounded,
                        color: Color(0xFF0038A8), size: 28),
                    const SizedBox(height: 6),
                    Text(
                      'GCash Customer Protection',
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'This payment is fully secure and verified.',
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade500, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _phoneInputView();
      case 1:
        return _otpInputView();
      case 2:
        return _mpinInputView();
      case 3:
        return _confirmationView();
      case 4:
        return _successView();
      default:
        return Container();
    }
  }

  Widget _phoneInputView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Login with GCash',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: const Color(0xFF0038A8)),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your GCash mobile number to pay.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, letterSpacing: 1.0),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Mobile Number',
            hintText: '09XXXXXXXXX',
            counterText: '',
            prefixIcon: const Icon(Icons.phone_iphone_rounded,
                color: Color(0xFF0038A8)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (val) {
            if (val == null || val.length < 11 || !val.startsWith("09")) {
              return 'Enter a valid 11-digit GCash number starting with 09.';
            }
            return null;
          },
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _sendOtp();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C56E9),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('NEXT',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _otpInputView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Authentication Required',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: const Color(0xFF0038A8)),
        ),
        const SizedBox(height: 6),
        Text(
          'We sent a 6-digit code to ${_phoneController.text}. Enter it below.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: 8.0),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'XXXXXX',
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _verifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C56E9),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('SUBMIT CODE',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _sendOtp,
          child: Text('Resend Code',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: const Color(0xFF0C56E9))),
        ),
      ],
    );
  }

  Widget _mpinInputView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter GCash MPIN',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: const Color(0xFF0038A8)),
        ),
        const SizedBox(height: 6),
        Text(
          'Input your secure 4-digit GCash mobile PIN.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _mpinController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: 12.0),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'XXXX',
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _verifyMpin,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C56E9),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('NEXT',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _confirmationView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review & Confirm',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: const Color(0xFF0038A8)),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Paying From:',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600)),
            Text(_phoneController.text,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const Divider(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Paying To:',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600)),
            Text(widget.gcashName,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(widget.gcashNumber,
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
        ),
        const Divider(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Amount:',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600)),
            Text('₱${widget.amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Processing Fee:',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600)),
            Text('₱0.00',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
          ],
        ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Debit:',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            Text('₱${widget.amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0038A8))),
          ],
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () {
            setState(() => _step = 4);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C56E9),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('PAY ₱${widget.amount.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 15)),
        ),
      ],
    );
  }

  Widget _successView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: CircleAvatar(
            radius: 36,
            backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.check_circle_rounded,
                color: Color(0xFF2E7D32), size: 54),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Payment Successful',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: const Color(0xFF2E7D32)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Receipt details have been automatically shared with the resort system.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Reference No:',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600)),
            SelectableText(_refNo,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recipient Merchant:',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600)),
            Text(widget.gcashName,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Amount Paid:',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600)),
            Text('₱${widget.amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _refNo),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0038A8),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('DONE',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }
}
