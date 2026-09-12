import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmailJsConfig {
  static const String serviceId = 'service_resortsconnect';
  static const String publicKey = 'user_resortsconnect_pk';
  static const String privateKey = ''; // Optional private key / accessToken

  static const String templateBookingConfirmation = 'template_booking_confirm';
  static const String templateBookingStatusUpdate = 'template_booking_status';
  static const String templateUserRegistration = 'template_welcome_user';
  static const String templateAdminAlert = 'template_admin_alert';
}

class EmailService {
  static Future<bool> sendEmail({
    required String templateId,
    required Map<String, dynamic> templateParams,
  }) async {
    try {
      final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
      
      final Map<String, dynamic> payload = {
        'service_id': EmailJsConfig.serviceId,
        'template_id': templateId,
        'user_id': EmailJsConfig.publicKey,
        'template_params': {
          'timestamp': DateTime.now().toIso8601String(),
          ...templateParams,
        }
      };

      if (EmailJsConfig.privateKey.isNotEmpty) {
        payload['accessToken'] = EmailJsConfig.privateKey;
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('[EmailJS] Dispatched email template $templateId successfully.');
        return true;
      } else {
        debugPrint('[EmailJS] Dispatch failed (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[EmailJS] Network error: $e');
      return false;
    }
  }

  static Future<bool> sendBookingConfirmation({
    required String toEmail,
    required String toName,
    required String bookingId,
    required String propertyName,
    required String roomName,
    required String checkInDate,
    required int nights,
    required double amountPaid,
    required double grandTotal,
    String paymentMethod = 'GCash',
    String paymentOption = 'Full Payment',
  }) async {
    return sendEmail(
      templateId: EmailJsConfig.templateBookingConfirmation,
      templateParams: {
        'to_email': toEmail,
        'to_name': toName,
        'subject': 'Booking Confirmation: $propertyName ($roomName)',
        'booking_id': bookingId,
        'resort_name': propertyName,
        'room_name': roomName,
        'check_in_date': checkInDate,
        'nights': nights,
        'amount_paid': '₱${amountPaid.toStringAsFixed(2)}',
        'grand_total': '₱${grandTotal.toStringAsFixed(2)}',
        'payment_method': paymentMethod,
        'payment_option': paymentOption,
        'summary': 'Your reservation for $roomName at $propertyName is being processed.',
      },
    );
  }

  static Future<bool> sendBookingStatusUpdate({
    required String toEmail,
    required String toName,
    required String bookingId,
    required String propertyName,
    required String roomName,
    required String newStatus,
    String notes = 'No additional notes.',
  }) async {
    return sendEmail(
      templateId: EmailJsConfig.templateBookingStatusUpdate,
      templateParams: {
        'to_email': toEmail,
        'to_name': toName,
        'subject': 'Booking Status Update: ${newStatus.toUpperCase()} - $propertyName',
        'booking_id': bookingId,
        'resort_name': propertyName,
        'room_name': roomName,
        'status': newStatus,
        'notes': notes,
        'summary': 'Your booking status for $propertyName has been updated to $newStatus.',
      },
    );
  }

  static Future<bool> sendAdminAlert({
    String? toEmail,
    String recipientRole = 'Admin',
    required String title,
    required String message,
    Map<String, dynamic>? details,
  }) async {
    return sendEmail(
      templateId: EmailJsConfig.templateAdminAlert,
      templateParams: {
        'to_email': toEmail ?? 'admin@resortconnect.site',
        'to_name': recipientRole,
        'subject': '[System Alert] $title',
        'alert_title': title,
        'alert_message': message,
        'details': details != null ? jsonEncode(details) : '',
        'summary': message,
      },
    );
  }

  static Future<bool> sendWelcomeEmail({
    required String toEmail,
    required String toName,
    required String customId,
    String role = 'Tourist',
  }) async {
    return sendEmail(
      templateId: EmailJsConfig.templateUserRegistration,
      templateParams: {
        'to_email': toEmail,
        'to_name': toName,
        'subject': 'Welcome to Resort Connect!',
        'custom_id': customId,
        'role': role,
        'summary': 'Welcome to Resort Connect! Your account ($customId) has been created.',
      },
    );
  }
}
