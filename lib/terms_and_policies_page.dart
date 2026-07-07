import 'package:flutter/material.dart';
import '../theme.dart';

class TermsAndPoliciesPage extends StatefulWidget {
  final bool scrollToPrivacy;
  const TermsAndPoliciesPage({Key? key, this.scrollToPrivacy = false}) : super(key: key);

  @override
  State<TermsAndPoliciesPage> createState() => _TermsAndPoliciesPageState();
}

class _TermsAndPoliciesPageState extends State<TermsAndPoliciesPage> {
  final GlobalKey _privacyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToPrivacy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          if (_privacyKey.currentContext != null) {
            Scrollable.ensureVisible(
              _privacyKey.currentContext!,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.05, // 5% from the top edge to give it breathing room
            );
          }
        });
      });
    }
  }

  Widget _buildSection(BuildContext context, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryAccent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Terms and Policies'),
        backgroundColor: Theme.of(context).cardColor,
        elevation: 0,
        iconTheme: IconThemeData(
          color: Theme.of(context).textTheme.titleLarge?.color,
        ),
        titleTextStyle: TextStyle(
          color: Theme.of(context).textTheme.titleLarge?.color,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(context, '1. Booking and Reservations',
                'All bookings must be confirmed through the platform. A valid identification card must be presented upon check-in. The person whose name is on the booking must be present.'),
            _buildSection(context, '2. Check-in and Check-out Policies',
                'Standard check-in time is 2:00 PM, and check-out time is 12:00 PM. Early check-in or late check-out is subject to availability and may incur additional charges.'),
            _buildSection(context, '3. Cancellation and Refund Policy',
                'Cancellations made 48 hours prior to the check-in date may be eligible for a refund, subject to the resort\'s specific rules. Late cancellations or no-shows are strictly non-refundable. Refunds will be processed through GCash.'),
            _buildSection(context, '4. Resort Rules and Code of Conduct',
                'Guests are expected to behave respectfully. Excessive noise, illegal activities, and damage to property are strictly prohibited. The resort reserves the right to evict guests who violate these terms without a refund.'),
            _buildSection(context, '5. Liability and Security',
                'The resort, hotel, and platform are not responsible for the loss or damage of personal belongings. Please secure your valuables. ResortConnect is merely a facilitator of bookings and does not directly operate the individual properties.'),
            const Divider(height: 48, thickness: 1),
            Text(
              'Data Privacy Policy',
              key: _privacyKey,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSection(context, '1. Information We Collect',
                'To facilitate your bookings across our partner properties (2 Resorts and 1 Hotel), we collect your name, contact number, email address, Government ID (for verification), and GCash payment receipts.'),
            _buildSection(context, '2. How We Use Your Data',
                'Your data is strictly used to confirm your identity, process reservations, and ensure secure communication between you and the property hosts. GCash receipts are used exclusively for payment verification.'),
            _buildSection(context, '3. Data Sharing',
                'We only share your booking details and identity verification with the specific resort or hotel you booked. We do not sell or rent your personal information to third parties.'),
            _buildSection(context, '4. Data Security and Retention',
                'Your data is securely stored using industry-standard encryption on Google Cloud (Firebase). You may request account deletion at any time, which will permanently remove your personal identifiable information from our active databases.'),
          ],
        ),
      ),
    );
  }
}
