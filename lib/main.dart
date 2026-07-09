import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'firebase_options.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'theme.dart';
import 'theme_provider.dart';
import 'dashboards/tourist_dashboard.dart';
import 'dashboards/owner_dashboard.dart';
import 'dashboards/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Replace red screen with a clean error message
  ErrorWidget.builder = (details) => Material(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              "Rendering Error: ${details.exception}",
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    // Enable offline persistence
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Resort Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: theme.themeMode,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnapshot.data;
        if (user == null) return const LoginPage();

        final isSocialAuth = user.providerData.any((p) => 
          p.providerId == 'google.com' || p.providerId == 'facebook.com'
        );

        if (!user.emailVerified && !isSocialAuth) {
          return const VerificationTimerPage();
        }

        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref("users/${user.uid}").onValue,
          builder: (context, dbSnapshot) {
            if (dbSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            if (!dbSnapshot.hasData || !dbSnapshot.data!.snapshot.exists) {
              return Scaffold(body: RegisterPage(isCompletingSocial: true, socialUser: user));
            }

            final data = Map<String, dynamic>.from(
                dbSnapshot.data!.snapshot.value as Map);

            if (data['isBanned'] == true) {
              return _bannedPage();
            }

            String role = (data['role'] ?? 'Tourist').toString().toUpperCase();
            
            if (role != 'ADMIN' && data['idVerified'] == false) {
              return _pendingVerificationPage();
            }

            if (role == 'OWNER') return const OwnerDashboard();
            if (role == 'ADMIN') return const AdminDashboard();
            return const TouristDashboard();
          },
        );
      },
    );
  }

  Widget _bannedPage() => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.darkBg, Color(0xFF1A0505)],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gavel_rounded,
                        size: 56, color: AppTheme.primaryAccent),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Account Suspended',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Poppins',
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your account has been suspended.\nContact us for more information.',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 15,
                        fontFamily: 'Poppins'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'resortconnect2026@gmail.com',
                    style: TextStyle(
                        color: AppTheme.secondaryAccent,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins'),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('BACK TO LOGIN'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(220, 52),
                      backgroundColor: AppTheme.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _pendingVerificationPage() => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.darkBg, Color(0xFF0D2E26)],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pending_actions_rounded,
                        size: 56, color: AppTheme.secondaryAccent),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Pending Verification',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Poppins',
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your account is currently pending Admin verification.\nPlease wait until your Valid ID is approved.',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 15,
                        fontFamily: 'Poppins'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('BACK TO LOGIN'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(220, 52),
                      backgroundColor: AppTheme.secondaryAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _errorPage(String message, IconData icon) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 48, color: AppTheme.primaryAccent),
                ),
                const SizedBox(height: 20),
                Text(
                  message,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      );
}

// ✅ Automated Email Verification Check
class VerificationTimerPage extends StatefulWidget {
  const VerificationTimerPage({super.key});
  @override
  State<VerificationTimerPage> createState() => _VerificationTimerPageState();
}

class _VerificationTimerPageState extends State<VerificationTimerPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Check every 3 seconds if email is verified
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await FirebaseAuth.instance.currentUser?.reload();
      if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
        timer.cancel();
        FirebaseAuth.instance.signOut().then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Email verified successfully. You may now log in.'),
                backgroundColor: AppTheme.primaryAccent,
              ),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.darkBg, AppTheme.darkSurface, Color(0xFF0D2E26)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_rounded,
                      size: 52,
                      color: AppTheme.secondaryAccent,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Verify Your Email',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Poppins',
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "We've sent a verification link to your email.\nThis page will update automatically once verified.",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                      fontFamily: 'Poppins',
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation(AppTheme.secondaryAccent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for verification...',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                        fontFamily: 'Poppins'),
                  ),
                  const SizedBox(height: 36),
                  ElevatedButton.icon(
                    onPressed: () => FirebaseAuth.instance.currentUser
                        ?.sendEmailVerification(),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('RESEND EMAIL'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Back to Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
