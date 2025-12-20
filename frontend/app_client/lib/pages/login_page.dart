import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/glass_container.dart';
import '../main.dart'; // To access MainScreen

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isCheckingCache = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkCachedSession();
  }

  Future<void> _checkCachedSession() async {
    final credentials = await SessionService.loadCredentials();
    if (credentials != null && mounted) {
      setState(() {
        _usernameController.text = credentials['username']!;
        _passwordController.text = credentials['password']!;
      });
    }
    
    if (mounted) {
      setState(() {
        _isCheckingCache = false;
      });
    }
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "Please enter both username and password.";
        _isLoading = false;
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = await ApiService.login(username, password);

      if (mounted && session != null) {
        await SessionService.clearSession();
        await SessionService.saveSession(session);
        await SessionService.saveCredentials(
          _usernameController.text,
          _passwordController.text,
        );
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainScreen(session: session)),
          );
        }
      }
    } catch (e) {
      String errorText = "Invalid username or password. Please check your credentials and try again.";
      final errorString = e.toString();
      
      if (errorString.contains("Exception: ")) {
        errorText = errorString.replaceAll("Exception: ", "").trim();
      } else if (errorString.isNotEmpty && errorString != "Exception") {
        errorText = errorString.trim();
      }
      
      if (errorText.startsWith("Message:")) {
        errorText = errorText.substring(8).trim();
      }
      
      final lowerError = errorText.toLowerCase();
      if (lowerError.contains("credentials") || 
          lowerError.contains("password") ||
          lowerError.contains("username") ||
          lowerError.contains("invalid") ||
          lowerError.contains("wrong")) {
        errorText = "Invalid username or password. Please check your credentials and try again.";
      } else if (lowerError.contains("connect") ||
                 lowerError.contains("network") ||
                 lowerError.contains("unable to connect")) {
        errorText = "Unable to connect to server. Please check your internet connection and ensure the backend is running.";
      } else if (lowerError.contains("server") ||
                 lowerError.contains("500") ||
                 lowerError.contains("error occurred")) {
        errorText = "Server error occurred. Please try again later.";
      }
      
      if (mounted) {
        setState(() {
          _errorMessage = errorText;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingCache) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpinKitDoubleBounce(color: isDark ? Colors.white : const Color(0xFF1E293B), size: 40),
              const SizedBox(height: 24),
              Text(
                "Initializing Ayla",
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Subtle Ambient Glow
          Positioned(
            top: -150,
            left: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF38B6FF).withValues(alpha: isDark ? 0.05 : 0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Icon/Logo
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded, 
                      size: 48, 
                      color: isDark ? Colors.white : const Color(0xFF1E293B)
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Ayla",
                    style: GoogleFonts.inter(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your focused academic space.",
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Login Card
                  GlassContainer(
                    width: 440,
                    padding: const EdgeInsets.all(40),
                    borderRadius: 32,
                    opacity: isDark ? 0.05 : 0.03,
                    blur: 30,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Welcome Back",
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildInputField(
                          controller: _usernameController,
                          label: "University Username",
                          icon: Icons.alternate_email_rounded,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: _passwordController,
                          label: "Service Password",
                          icon: Icons.lock_outline_rounded,
                          isDark: isDark,
                          isPassword: true,
                        ),
                        const SizedBox(height: 32),
                        
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Colors.redAccent, size: 18),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                            foregroundColor: isDark ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20, 
                                  width: 20, 
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)
                                )
                              : Text(
                                  "Enter Workspace",
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                        ),
                        
                        if (_isLoading) ...[
                          const SizedBox(height: 24),
                          Text(
                            "Securely synchronizing with BOSS & Moodle...\nThis protocol takes approximately 30 seconds.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white38 : Colors.black38, 
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            style: GoogleFonts.inter(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 15,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: isDark ? Colors.white24 : Colors.black26, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: "Enter placeholder...",
              hintStyle: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
            ),
          ),
        ),
      ],
    );
  }
}
