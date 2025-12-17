import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'api_service.dart';
import 'ayla_service.dart';
import 'models.dart';
import 'custom_event_service.dart';
import 'session_service.dart';
import 'workspace_service.dart';

import 'custom_event_service.dart';
import 'session_service.dart';
import 'widgets/glass_container.dart';

// Unified event class for calendar display
class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String? course;
  final String? link;
  final bool isCustom;
  final String color;
  final String platform; // 'Moodle' or 'Ayla'

  CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    this.course,
    this.link,
    required this.isCustom,
    this.color = '#4a5568',
    this.platform = 'Moodle',
  });

  factory CalendarEvent.fromDeadline(Deadline deadline) {
    final isAyla = deadline.platform == 'Ayla';
    return CalendarEvent(
      id: deadline.link.isNotEmpty ? deadline.link : DateTime.now().millisecondsSinceEpoch.toString(),
      title: deadline.title,
      description: deadline.course,
      date: DateTime.parse(deadline.date),
      course: deadline.course,
      link: deadline.link,
      isCustom: isAyla,
      color: isAyla ? '#E74C3C' : '#4a5568', // Red for exams, gray for Moodle
      platform: deadline.platform,
    );
  }

  factory CalendarEvent.fromCustomEvent(CustomEvent customEvent) {
    return CalendarEvent(
      id: customEvent.id,
      title: customEvent.title,
      description: customEvent.description,
      date: customEvent.date,
      course: customEvent.location,
      isCustom: true,
      color: customEvent.color,
    );
  }
}

// Helper function to filter out submission actions (not actual deadlines)
List<Deadline> filterRealDeadlines(List<Deadline> deadlines) {
  // Titles to filter out - these are submission actions or calendar events, NOT actual deadlines
  final filterOutTitles = [
    'aufgabenlösung hinzufügen',
    'lösung hinzufügen',
    'abgabe hinzufügen',
    'add submission',
    'edit submission',
    'einreichung',
    'aufgabe lösen',
    'lösung',
    'hinzufügen',
    'endet',      // Quiz/activity close events (e.g., "Testat endet")
    'beginnt',    // Quiz/activity open events (e.g., "Testat beginnt")
  ];
  
  // URL patterns that indicate submission actions (not deadlines)
  final filterOutUrls = [
    'action=editsubmission',
    'action=submit',
    'action=add',
  ];
  
  return deadlines.where((deadline) {
    final titleLower = deadline.title.toLowerCase();
    final linkLower = deadline.link.toLowerCase();
    
    // Skip if title contains any filter word
    if (filterOutTitles.any((filter) => titleLower.contains(filter))) {
      return false;
    }
    
    // Skip if URL contains any filter pattern
    if (filterOutUrls.any((filter) => linkLower.contains(filter))) {
      return false;
    }
    
    return true;
  }).toList();
}

void main() {
  runApp(const Ayla());
}

// Global Theme Notifier
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class Ayla extends StatelessWidget {
  const Ayla({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Ayla',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              secondary: Color(0xFF64748B),
              surface: Colors.white,
              background: Colors.white,
              onPrimary: Colors.white,
              onSecondary: Colors.black,
              onSurface: Colors.black,
              onBackground: Colors.black,
            ),
            textTheme: GoogleFonts.interTextTheme(
              Theme.of(context).textTheme,
            ).apply(
              bodyColor: Colors.black,
              displayColor: Colors.black,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF000000),
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              secondary: Color(0xFF94A3B8),
              surface: Color(0xFF111111),
              background: Colors.black,
              onPrimary: Colors.black,
              onSecondary: Colors.white,
              onSurface: Colors.white,
              onBackground: Colors.white,
            ),
            textTheme: GoogleFonts.interTextTheme(
              Theme.of(context).textTheme,
            ).apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
          ),
          home: const LoginPage(),
        );
      },
    );
  }
}

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
    // Check for cached session
    final cachedSession = await SessionService.loadSession();
    
    // FORCE REFRESH: Always fetch fresh data on app start to ensure correct exam requirements
    // Comment out the auto-login below if you want to always fetch fresh data
    // For now, we'll skip auto-login to ensure fresh data is fetched
    /*
    if (cachedSession != null && mounted) {
      // Auto-login with cached session
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainScreen(session: cachedSession)),
      );
      return;
    }
    */
    
    // Try to load saved credentials
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
    // Validate inputs
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
        // Clear old cache first to ensure fresh data
        await SessionService.clearSession();
        
        // Save fresh session and credentials
        await SessionService.saveSession(session);
        await SessionService.saveCredentials(
          _usernameController.text,
          _passwordController.text,
        );
        
        // Debug: Print exam requirements to verify
        print("=== SAVED SESSION DATA ===");
        print("Degree Program: ${session.ectsData.degreeProgram}");
        print("Exam Requirements Count: ${session.examRequirements.length}");
        for (var cat in session.examRequirements) {
          print("Category: ${cat.category}");
          for (var exam in cat.exams) {
            print("  - ${exam.name} (Passed: ${exam.passed})");
          }
        }
        print("==========================");
        
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainScreen(session: session)),
        );
      }
    } catch (e) {
      print("Login error caught: $e");
      print("Error type: ${e.runtimeType}");
      
      if (mounted) {
        String errorText = "Invalid username or password. Please check your credentials and try again.";
        
        // Extract user-friendly error message
        final errorString = e.toString();
        print("Raw error string: '$errorString'");
        
        if (errorString.contains("Exception: ")) {
          errorText = errorString.replaceAll("Exception: ", "").trim();
        } else if (errorString.isNotEmpty && errorString != "Exception") {
          errorText = errorString.trim();
        }
        
        // Remove any "Message:" prefix that might be added
        if (errorText.startsWith("Message:")) {
          errorText = errorText.substring(8).trim();
        }
        
        // Ensure we always have a message
        if (errorText.isEmpty || errorText == "Exception" || errorText == "Message:") {
          errorText = "Invalid username or password. Please check your credentials and try again.";
        }
        
        // Make error messages more user-friendly
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
        
        print("Final error message: '$errorText'");
        
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
    // Show loading while checking cache
    if (_isCheckingCache) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SpinKitThreeBounce(color: Colors.white, size: 30),
              const SizedBox(height: 16),
              Text(
                "Loading...",
                style: GoogleFonts.inter(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Ambient Background Gradients
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueGrey.withOpacity(0.2),
                image: null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueGrey.withOpacity(0.2),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3A7BD5).withOpacity(0.05),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D2FF).withOpacity(0.05),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: GlassContainer(
                width: 400,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.school_rounded, size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      "Ayla",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        color: const Color(0xFF00D2FF),
                      ),
                    ),
                    Text(
                      "Student Dashboard",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 48),
                    TextField(
                      controller: _usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Username",
                        labelStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: Icon(Icons.person_outline, color: Colors.grey[400]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF00D2FF), width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Password",
                        labelStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[400]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF00D2FF), width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null && _errorMessage!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.5), width: 1),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: _isLoading ? null : _handleLogin,
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3A7BD5).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SpinKitThreeBounce(color: Colors.white, size: 20)
                              : Text(
                                  "Sign In",
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 24),
                      Text(
                        "Connecting to Moodle & BOSS...\nThis usually takes about 30 seconds.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final SessionData session;

  const MainScreen({super.key, required this.session});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isSidebarOpen = false;
  bool _isChatOpen = false;
  int _dashboardKey = 0; // Increment to force dashboard refresh

  void _refreshDashboard() {
    setState(() => _dashboardKey++);
  }

  @override
  Widget build(BuildContext context) {
    Widget currentPage;
    switch (_selectedIndex) {
      case 0:
        currentPage = DashboardPage(key: ValueKey(_dashboardKey), session: widget.session, onNavigate: (index) => setState(() => _selectedIndex = index));
        break;
      case 1:
        currentPage = WorkspacePage(session: widget.session, onNavigate: (index) => setState(() => _selectedIndex = index));
        break;
      default:
        currentPage = DashboardPage(key: ValueKey(_dashboardKey), session: widget.session, onNavigate: (index) => setState(() => _selectedIndex = index));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [

          // Main Content Area
          currentPage,
          // Overlay to close sidebar when clicking outside (behind sidebar)
          if (_isSidebarOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isSidebarOpen = false),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                ),
              ),
            ),
          // Animated Sidebar (above overlay so it's clickable)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: _isSidebarOpen ? 0 : -240,
            top: 0,
            bottom: 0,
            child: GlassContainer(
                width: 240,
                borderRadius: 0,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.black.withOpacity(0.6) 
                    : Colors.white.withOpacity(0.8), // Light sidebar
                border: Border(right: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12,
                )),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Ayla",
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black, size: 20),
                            onPressed: () => setState(() => _isSidebarOpen = false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _SidebarMenuItem(
                      icon: Icons.dashboard_rounded,
                      label: "Dashboard",
                      isSelected: _selectedIndex == 0,
                      onTap: () {
                        setState(() {
                          _selectedIndex = 0;
                          _isSidebarOpen = false;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _SidebarMenuItem(
                      icon: Icons.workspaces_rounded,
                      label: "Workspace",
                      isSelected: _selectedIndex == 1,
                      onTap: () {
                        setState(() {
                          _selectedIndex = 1;
                          _isSidebarOpen = false;
                        });
                      },
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                await SessionService.clearSession();
                                if (context.mounted) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(builder: (_) => const LoginPage()),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D3748),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text("Refresh Data"),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                await SessionService.clearCredentials();
                                if (context.mounted) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(builder: (_) => const LoginPage()),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D3748),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text("Logout"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Hamburger Menu Button (above sidebar so it's always clickable)
          if (!_isSidebarOpen) // Hide when sidebar is open to prevent collision
            Positioned(
              top: 20,
              left: 20,
              child: Material(
                color: Colors.transparent, 
                child: InkWell(
                  onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.black.withOpacity(0.5) 
                          : Colors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12
                      ),
                    ),
                    child: Icon(
                      Icons.menu,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            // Floating Ayla Chat Widget
            if (_isChatOpen)
              Positioned(
                right: 16,
                bottom: 16,
                child: AylaFloatingChat(
                  session: widget.session,
                  onClose: () => setState(() => _isChatOpen = false),
                  onEventAdded: _refreshDashboard, // Refresh calendar when event added
                ),
              ),
        ],
      ),
      floatingActionButton: _isChatOpen ? null : AylaChatButton(
        onPressed: () => setState(() => _isChatOpen = true),
      ),
    );
  }
}

class AylaChatButton extends StatefulWidget {
  final VoidCallback onPressed;

  const AylaChatButton({super.key, required this.onPressed});

  @override
  State<AylaChatButton> createState() => _AylaChatButtonState();
}

class _AylaChatButtonState extends State<AylaChatButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF00D2FF),
                Color(0xFF3A7BD5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3A7BD5).withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF00D2FF).withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 30,
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D2FF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// AYLA FLOATING CHAT WIDGET
// ============================================================================

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AylaFloatingChat extends StatefulWidget {
  final SessionData session;
  final VoidCallback onClose;
  final VoidCallback? onEventAdded; // Callback when an event is added

  const AylaFloatingChat({
    super.key, 
    required this.session,
    required this.onClose,
    this.onEventAdded,
  });

  @override
  State<AylaFloatingChat> createState() => _AylaFloatingChatState();
}

class _AylaFloatingChatState extends State<AylaFloatingChat> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isMinimized = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    
    // Add welcome message
    _messages.add(ChatMessage(
      text: "Hi! I'm Ayla, your AI study companion 📚\nHow can I help you today?",
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildStudentContext() {
    final grades = widget.session.ectsData;
    final deadlines = widget.session.moodleDeadlines.take(5).map((d) => {
      'title': d.title,
      'course': d.course,
      'date': d.date,
    }).toList();
    
    final examRequirements = widget.session.examRequirements.map((category) => {
      'category': category.category,
      'exams': category.exams.map((exam) => {
        'name': exam.name,
        'ects': exam.ects,
        'type': exam.type,
        'passed': exam.passed,
      }).toList(),
    }).toList();
    
    final currentClasses = widget.session.currentClasses;
    
    // Include detailed grades (actual scores)
    final detailedGrades = widget.session.detailedGrades.map((grade) => {
      'name': grade.name,
      'grade': grade.grade,
      'ects': grade.ects,
    }).toList();
    
    return {
      'student_name': widget.session.profileName,
      'degree_program': grades.degreeProgram ?? 'Unknown',
      'total_ects': grades.totalEcts,
      'courses_count': grades.coursesCount,
      'average_grade': grades.averageGrade,
      'best_grade': grades.bestGrade,
      'upcoming_deadlines': deadlines,
      'exam_requirements': examRequirements,
      'current_classes': currentClasses,
      'detailed_grades': detailedGrades,
      'current_date': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      // Build student context for personalized responses
      final contextMap = _buildStudentContext();
      final userId = widget.session.profileName.toLowerCase().replaceAll(' ', '_');
      
      // Use Gemini 2.0 Flash API with memory
      final response = await WorkspaceService.sendGeminiChat(
        text,
        userId: userId,
        studentContext: {
          'name': widget.session.profileName,
          'gpa': contextMap['gpa'],
          'ects': contextMap['ects'],
          'degree': contextMap['degree'] ?? 'Informatik',
          'exams': contextMap['exam_requirements'] ?? [],
        },
      );

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: response ?? "No response received.", isUser: false));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: "Sorry, I couldn't process that. ${e.toString().replaceAll('Exception: ', '')}",
            isUser: false,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final chatWidth = screenWidth > 600 ? 420.0 : screenWidth * 0.85;
    final chatHeight = screenHeight > 700 ? 550.0 : screenHeight * 0.7;
    
    return ScaleTransition(
      scale: _scaleAnim,
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        elevation: 20,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _isMinimized ? 56 : chatWidth,
          height: _isMinimized ? 56 : chatHeight,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1a1a1a) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF3A7BD5).withOpacity(0.3) : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: _isMinimized ? _buildMinimizedView() : _buildExpandedView(isDark, chatWidth),
        ),
      ),
    );
  }

  Widget _buildMinimizedView() {
    return InkWell(
      onTap: () => setState(() => _isMinimized = false),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _buildExpandedView(bool isDark, double chatWidth) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Ayla",
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "AI Study Companion",
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _isMinimized = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.remove_rounded, color: Colors.white70, size: 20),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isLoading) {
                  return _buildTypingIndicator(isDark);
                }
                return _buildMessage(_messages[index], isDark);
              },
            ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.shade50,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: "Ask anything...",
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _isLoading ? null : _sendMessage,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: _isLoading ? null : const LinearGradient(
                        colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                      ),
                      color: _isLoading ? Colors.grey : null,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: message.isUser
                    ? const Color(0xFF3A7BD5)
                    : (isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(14).copyWith(
                  bottomRight: message.isUser ? const Radius.circular(4) : null,
                  bottomLeft: !message.isUser ? const Radius.circular(4) : null,
                ),
              ),
              child: message.isUser 
                  ? Text(
                      message.text,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    )
                  : MarkdownBody(
                      data: message.text,
                      styleSheet: MarkdownStyleSheet(
                        p: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        a: GoogleFonts.inter(
                          color: const Color(0xFF00D2FF),
                          decoration: TextDecoration.underline,
                        ),
                        code: GoogleFonts.robotoMono(
                          backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                          fontSize: 12,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          launchUrl(Uri.parse(href));
                        }
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14).copyWith(
                bottomLeft: const Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) => _buildDot(i)),
                ),
                const SizedBox(height: 6),
                _AnimatedStatusText(isDark: isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 150)),
      curve: Curves.easeInOut,
      builder: (context, value, _) => Container(
        margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: const Color(0xFF3A7BD5).withOpacity(value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// Keep the old AylaChatSheet for backwards compatibility but it won't be used
class AylaChatSheet extends StatefulWidget {
  final SessionData session;
  const AylaChatSheet({super.key, required this.session});
  @override
  State<AylaChatSheet> createState() => _AylaChatSheetState();
}
class _AylaChatSheetState extends State<AylaChatSheet> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Animated status text that cycles through different messages
/// to show the user what the AI is doing
class _AnimatedStatusText extends StatefulWidget {
  final bool isDark;
  const _AnimatedStatusText({required this.isDark});

  @override
  State<_AnimatedStatusText> createState() => _AnimatedStatusTextState();
}

class _AnimatedStatusTextState extends State<_AnimatedStatusText> {
  int _currentIndex = 0;
  final List<String> _statusMessages = [
    "Thinking...",
    "Analyzing your data...",
    "Checking TU Dortmund...",
    "Almost there...",
  ];

  @override
  void initState() {
    super.initState();
    _startCycling();
  }

  void _startCycling() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _statusMessages.length;
        });
        _startCycling();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        _statusMessages[_currentIndex],
        key: ValueKey<int>(_currentIndex),
        style: GoogleFonts.inter(
          fontSize: 11,
          color: widget.isDark ? Colors.white38 : Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}



class _SidebarMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarMenuItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3A7BD5).withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected 
                  ? const Color(0xFF00D2FF) 
                  : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black), 
              size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isSelected 
                      ? const Color(0xFF00D2FF) 
                      : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final SessionData session;
  final Function(int)? onNavigate;

  const DashboardPage({super.key, required this.session, this.onNavigate});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedCalendarDate;
  List<CalendarEvent>? _selectedDateEvents;
  List<Deadline> _savedEvents = []; // Saved exam events from Supabase
  bool _isRefreshing = false;
  late SessionData _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _fetchSavedEvents();
  }

  /// Force refresh all data from the server (bypasses 24h cache)
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    
    try {
      // Get credentials from session service
      final credentials = await SessionService.loadCredentials();
      if (credentials != null) {
        final newSession = await ApiService.login(
          credentials['username']!,
          credentials['password']!,
          forceRefresh: true,
        );
        
        if (newSession != null && mounted) {
          // Save the new session
          await SessionService.saveSession(newSession);
          
          // Update local state to reflect changes immediately
          setState(() {
            _session = newSession;
          });
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dashboard updated successfully!'),
               backgroundColor: Colors.green,
               duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // No saved credentials
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log out and log in again to refresh.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print("Refresh error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _fetchSavedEvents() async {
    final studentId = _session.profileName.toLowerCase().replaceAll(' ', '_');
    try {
      final events = await AylaService.getEvents(studentId);
      if (events.isNotEmpty && mounted) {
        setState(() {
          _savedEvents = events.map((e) => Deadline(
            platform: 'Ayla',
            title: e['title'] ?? 'Event',
            course: e['course'] ?? '',
            date: e['event_date'] ?? '',
            link: e['id']?.toString() ?? '', // Store event ID for deletion
            rawDate: '',
          )).toList();
        });
      }
    } catch (e) {
      print("Error fetching saved events: $e");
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use local _session state instead of widget.session
    final session = _session;
    
    // Filter out submission actions to show only real deadlines
    final realDeadlines = filterRealDeadlines(session.moodleDeadlines);
    // Combine Moodle deadlines with saved exam events
    final allDeadlines = [...realDeadlines, ..._savedEvents];
    final progress = (session.ectsData.totalEcts / 180) * 100;
    final firstName = session.profileName.split(' ')[0];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
                // Top Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  // Removed white decoration
                  child: Row(
                    children: [
                      const SizedBox(width: 80), // Space for hamburger menu
                      Text(
                        "Dashboard",
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                        ),
                      ),
                      const Spacer(),
                      // Refresh Button
                      _isRefreshing
                          ? SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white : Colors.black,
                              ),
                              tooltip: 'Refresh Data',
                              onPressed: _refreshData,
                            ),
                      const SizedBox(width: 8),
                      // Theme Toggle
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeNotifier,
                        builder: (context, currentMode, child) {
                          final isDark = currentMode == ThemeMode.dark;
                          return IconButton(
                            icon: Icon(
                              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            onPressed: () {
                              themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      // Profile Icon
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                        child: Text(
                          firstName[0].toUpperCase(),
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w600
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Main Content
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Charts and Calendar Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column - Charts
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  // Progress Chart Card
                                  GlassContainer(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Progress Overview",
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Center(
                                          child: _ProgressCard(
                                            currentEcts: session.ectsData.totalEcts,
                                            maxEcts: 180,
                                            averageGrade: session.ectsData.averageGrade,
                                            bestGrade: session.ectsData.bestGrade,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Upcoming Deadlines Card (with Current Classes inside)
                                  GlassContainer(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Upcoming Deadlines",
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          height: 200,
                                          child: SingleChildScrollView(
                                            child: _UpcomingListCompact(deadlines: realDeadlines),
                                          ),
                                        ),
                                        // Current Classes Section inside same card
                                        if (session.currentClasses.isNotEmpty) ...[
                                          const SizedBox(height: 24),
                                          const Divider(),
                                          const SizedBox(height: 16),
                                          Text(
                                            "Current Classes",
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            height: 200,
                                            child: SingleChildScrollView(
                                              child: _CurrentClassesListCompact(classes: session.currentClasses),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Right Column - Calendar
                              Expanded(
                                flex: 2,
                                child: GlassContainer(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Monthly",
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    _MonthlyCalendar(
                                      deadlines: allDeadlines,
                                      onDateSelected: (date, events) {
                                        setState(() {
                                          _selectedCalendarDate = date;
                                          _selectedDateEvents = events;
                                        });
                                      },
                                    ),
                                    // Show selected date events below calendar
                                      if (_selectedDateEvents != null && _selectedDateEvents!.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        const Divider(color: Colors.white24),
                                        const SizedBox(height: 16),
                                        Text(
                                          DateFormat('EEEE, d MMMM').format(_selectedCalendarDate!),
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        ..._selectedDateEvents!.map((event) {
                                          // Generate consistent color based on event title
                                          final colors = [
                                            const Color(0xFF3498DB), // Blue
                                            const Color(0xFFE74C3C), // Red  
                                            const Color(0xFF00D2FF), // Teal accent
                                            const Color(0xFF9B59B6), // Purple
                                            const Color(0xFFF39C12), // Orange
                                            const Color(0xFF1ABC9C), // Teal
                                            const Color(0xFFE91E63), // Pink
                                          ];
                                          final eventColor = colors[event.title.hashCode.abs() % colors.length];
                                          final timeString = DateFormat('HH:mm').format(event.date);
                                          
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 8),
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border(
                                                  left: BorderSide(color: eventColor, width: 4),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          event.title,
                                                          style: GoogleFonts.inter(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          children: [
                                                            Icon(Icons.access_time, size: 12, color: Colors.white60),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              timeString,
                                                              style: GoogleFonts.inter(
                                                                fontSize: 11,
                                                                color: Colors.white60,
                                                              ),
                                                            ),
                                                            if (event.course != null && event.course!.isNotEmpty) ...[
                                                              const SizedBox(width: 12),
                                                              Expanded(
                                                                child: Text(
                                                                  event.course!,
                                                                  style: GoogleFonts.inter(
                                                                    fontSize: 11,
                                                                    color: Colors.white60,
                                                                  ),
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // Delete button for Ayla events
                                                  if (event.platform == 'Ayla')
                                                    IconButton(
                                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white54),
                                                      onPressed: () async {
                                                        // Parse event ID from link field
                                                        final eventId = int.tryParse(event.id);
                                                        if (eventId != null) {
                                                          final success = await AylaService.deleteEvent(eventId);
                                                          if (success && mounted) {
                                                            _fetchSavedEvents();
                                                            setState(() {
                                                              _selectedDateEvents = null;
                                                            });
                                                          }
                                                        }
                                                      },
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                    ],
                                    // Passed Exams Section (scrollable)
                                      if (session.examRequirements.isNotEmpty) ...[
                                        const SizedBox(height: 24),
                                        const Divider(color: Colors.white24),
                                        const SizedBox(height: 16),
                                        Text(
                                          "Passed Exams",
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: 200,
                                        child: SingleChildScrollView(
                                          child: _PassedExamsList(examRequirements: session.examRequirements),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ============================================================================
// WORKSPACE PAGE (replaces Planner and Exams)
// ============================================================================

class WorkspacePage extends StatefulWidget {
  final SessionData session;
  final Function(int)? onNavigate;
  const WorkspacePage({super.key, required this.session, this.onNavigate});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  List<Map<String, dynamic>> _workspaces = [];
  Map<String, dynamic>? _selectedWorkspace;
  bool _isLoading = true;
  
  // For workspace detail view
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  List<Map<String, dynamic>> _chatMessages = [];
  List<Map<String, dynamic>> _files = [];
  bool _isChatLoading = false;
  
  String get _studentId => widget.session.profileName.toLowerCase().replaceAll(' ', '_');

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspaces() async {
    setState(() => _isLoading = true);
    final workspaces = await WorkspaceService.getWorkspaces(_studentId);
    if (mounted) {
      setState(() {
        _workspaces = workspaces;
        _isLoading = false;
      });
    }
  }

  Future<void> _createWorkspace() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? const Color(0xFF1A1A2E) 
            : Colors.white,
        title: Text("Create Workspace", style: GoogleFonts.inter(
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
        )),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: GoogleFonts.inter(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
          ),
          decoration: InputDecoration(
            hintText: "Workspace name (e.g., Math, Research)",
            hintStyle: GoogleFonts.inter(color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF00D2FF), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3A7BD5),
              foregroundColor: Colors.white,
            ),
            child: Text("Create", style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      await WorkspaceService.createWorkspace(_studentId, result);
      _loadWorkspaces();
    }
  }

  Future<void> _openWorkspace(Map<String, dynamic> workspace) async {
    setState(() {
      _selectedWorkspace = workspace;
      _isLoading = true;
    });
    
    // Load notes, chat history, and files
    final notes = await WorkspaceService.getNotes(workspace['id']);
    final chats = await WorkspaceService.getChats(workspace['id']);
    final files = await WorkspaceService.getFiles(workspace['id']);
    
    if (mounted) {
      setState(() {
        _notesController.text = notes;
        _chatMessages = chats;
        _files = files;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveNotes() async {
    if (_selectedWorkspace != null) {
      await WorkspaceService.saveNotes(
        _selectedWorkspace!['id'], 
        _notesController.text,
        _studentId
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Notes saved!")),
        );
      }
    }
  }

  Future<void> _sendChatMessage() async {
    if (_chatController.text.trim().isEmpty || _selectedWorkspace == null) return;
    
    final message = _chatController.text.trim();
    _chatController.clear();
    
    setState(() {
      _chatMessages.add({'role': 'user', 'message': message});
      _isChatLoading = true;
    });
    
    final response = await WorkspaceService.sendChat(
      _selectedWorkspace!['id'],
      _studentId,
      message,
      _notesController.text,
    );
    
    if (mounted) {
      setState(() {
        _isChatLoading = false;
        if (response != null) {
          _chatMessages.add({'role': 'model', 'message': response});
        }
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedWorkspace == null) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true, // Necessary for Web to get bytes
      );

      if (result != null) {
        final platformFile = result.files.single;
        List<int>? fileBytes;
        final fileName = platformFile.name;

        // On Web, we must use bytes. On IO, we can read from path if bytes are null
        if (kIsWeb) {
          fileBytes = platformFile.bytes;
        } else {
          fileBytes = platformFile.bytes;
          if (fileBytes == null && platformFile.path != null) {
            fileBytes = File(platformFile.path!).readAsBytesSync();
          }
        }

        if (fileBytes != null) {
          final success = await WorkspaceService.uploadFile(
            _selectedWorkspace!['id'],
            fileBytes,
            fileName,
            _studentId,
          );

          if (success) {
            // Refresh files list
            final files = await WorkspaceService.getFiles(_selectedWorkspace!['id']);
            setState(() {
              _files = files;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("File uploaded successfully!")),
              );
            }
          }
        } else {
          print("Error: Could not read file bytes");
        }
      }
    } catch (e) {
      print("File pick error: $e");
    }
  }

  Future<void> _deleteFile(String fileId) async {
    if (await WorkspaceService.deleteFile(fileId)) {
      if (_selectedWorkspace != null) {
        final files = await WorkspaceService.getFiles(_selectedWorkspace!['id']);
        setState(() {
          _files = files;
        });
      }
    }
  }

  Future<void> _deleteWorkspace(String workspaceId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? const Color(0xFF1A1A2E) : Colors.white,
        title: Text("Delete Workspace?", style: GoogleFonts.inter(
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
        )),
        content: Text("This will delete all notes, files, and chat history.", 
          style: GoogleFonts.inter(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel", style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("Delete", style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await WorkspaceService.deleteWorkspace(workspaceId);
      _loadWorkspaces();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_selectedWorkspace != null) {
      return _buildWorkspaceDetail(isDark);
    }
    return _buildWorkspaceList(isDark);
  }

  Widget _buildWorkspaceList(bool isDark) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(left: 80, top: 24, right: 24, bottom: 24),
            child: Row(
              children: [
                Text(
                  "Your Workspaces",
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _createWorkspace,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text("New Workspace", style: GoogleFonts.inter()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3A7BD5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          // Workspace Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A7BD5)))
                : _workspaces.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_rounded, size: 80, color: isDark ? Colors.white24 : Colors.black26),
                            const SizedBox(height: 16),
                            Text("No workspaces yet", style: GoogleFonts.inter(fontSize: 18, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text("Create one to get started!", style: GoogleFonts.inter(color: Colors.grey)),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.2,
                          ),
                          itemCount: _workspaces.length,
                          itemBuilder: (context, index) {
                            final workspace = _workspaces[index];
                            return _WorkspaceCard(
                              name: workspace['name'] ?? 'Untitled',
                              onTap: () => _openWorkspace(workspace),
                              onDelete: () => _deleteWorkspace(workspace['id']),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceDetail(bool isDark) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header with back button - PADDED to avoid overlap with menu button
          Padding(
            padding: const EdgeInsets.only(left: 80, top: 16, right: 16, bottom: 16),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black),
                    onPressed: () {
                      _saveNotes();
                      setState(() => _selectedWorkspace = null);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _selectedWorkspace?['name'] ?? 'Workspace',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
          // 3-Panel Layout
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A7BD5)))
                : Row(
                    children: [
                      // Chat Panel (largest - 60%)
                      Expanded(
                        flex: 6,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
                          ),
                          child: Column(
                            children: [
                              // Chat header
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.chat_rounded, color: Color(0xFF3A7BD5), size: 20),
                                    const SizedBox(width: 8),
                                    Text("AI Chat", style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : Colors.black,
                                    )),
                                  ],
                                ),
                              ),
                              // Chat messages
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _chatMessages.length && _isChatLoading) {
                                      return Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Row(children: [
                                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                                          const SizedBox(width: 8),
                                          Text("Ayla is thinking...", style: GoogleFonts.inter(color: Colors.grey)),
                                        ]),
                                      );
                                    }
                                    final msg = _chatMessages[index];
                                    final isUser = msg['role'] == 'user';
                                    return Align(
                                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(12),
                                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.4),
                                        decoration: BoxDecoration(
                                          color: isUser 
                                              ? const Color(0xFF3A7BD5).withOpacity(0.15) 
                                              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isUser 
                                                ? const Color(0xFF3A7BD5).withOpacity(0.2) 
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: Text(msg['message'] ?? '', style: GoogleFonts.inter(
                                          color: isDark ? Colors.white : Colors.black87,
                                          height: 1.4,
                                        )),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Chat input
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _chatController,
                                        style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black),
                                        decoration: InputDecoration(
                                          hintText: "Ask Ayla...",
                                          hintStyle: GoogleFonts.inter(color: Colors.grey),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
                                        onSubmitted: (_) => _sendChatMessage(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.send_rounded, color: Color(0xFF3A7BD5)),
                                      onPressed: _sendChatMessage,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Right side panels (40%)
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            // Files Panel
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.folder_rounded, color: Colors.amber, size: 20),
                                          const SizedBox(width: 8),
                                          Text("Files", style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white : Colors.black,
                                          )),
                                          const Spacer(),
                                          TextButton.icon(
                                            onPressed: _uploadFile,
                                            icon: const Icon(Icons.upload_file, size: 16),
                                            label: Text("Upload", style: GoogleFonts.inter(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: _files.isEmpty
                                          ? Center(
                                              child: Text("No files yet", style: GoogleFonts.inter(color: Colors.grey)),
                                            )
                                          : ListView.builder(
                                              itemCount: _files.length,
                                              itemBuilder: (context, index) {
                                                final file = _files[index];
                                                return ListTile(
                                                  leading: Icon(Icons.insert_drive_file, color: isDark ? Colors.white54 : Colors.black54),
                                                  title: Text(file['filename'] ?? 'File', style: GoogleFonts.inter(
                                                    color: isDark ? Colors.white : Colors.black,
                                                  )),
                                                  trailing: IconButton(
                                                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[300]),
                                                    onPressed: () => _deleteFile(file['id']),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Notes Panel
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_note_rounded, color: Colors.blue, size: 20),
                                          const SizedBox(width: 8),
                                          Text("Notes", style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white : Colors.black,
                                          )),
                                          const Spacer(),
                                          TextButton.icon(
                                            onPressed: _saveNotes,
                                            icon: const Icon(Icons.save, size: 16),
                                            label: Text("Save", style: GoogleFonts.inter(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: TextField(
                                          controller: _notesController,
                                          maxLines: null,
                                          expands: true,
                                          style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black),
                                          decoration: InputDecoration(
                                            hintText: "Write your notes here...\n\nAyla can read these notes and help you!",
                                            hintStyle: GoogleFonts.inter(color: Colors.grey),
                                            border: InputBorder.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _WorkspaceCard({required this.name, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_rounded, size: 48, color: Colors.amber),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// PlannerPage removed - replaced by WorkspacePage


class ExamsPage extends StatelessWidget {
  final SessionData session;
  final Function(int)? onNavigate;

  const ExamsPage({super.key, required this.session, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final firstName = session.profileName.split(' ')[0];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Top Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            // Removed white decoration
            child: Row(
              children: [
                const SizedBox(width: 60), // Space for hamburger menu
                Text(
                  "Exams",
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  child: Text(
                    firstName[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (session.examRequirements.isNotEmpty) ...[
                    GlassContainer(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "Exam Requirements",
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                                ),
                              ),
                              if (session.ectsData.degreeProgram != null) ...[
                                const SizedBox(width: 12),
                                Text(
                                  "• ${session.ectsData.degreeProgram}",
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          _ExamRequirementsList(examRequirements: session.examRequirements),
                        ],
                      ),
                    ),
                  ] else
                    GlassContainer(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.school_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              "No exam requirements available",
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
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
}

// --- Components ---

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 16),
            Text(value, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, height: 1.0)),
            const SizedBox(height: 4),
            Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ModernStatCard extends StatelessWidget {
  final String label;
  final String labelSecondary;
  final String value;

  const _ModernStatCard({
    required this.label,
    required this.labelSecondary,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            labelSecondary,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 40,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827),
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper widget for displaying audit statistics
class _AuditStatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _AuditStatItem({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.white,
          ),
        ),
      ],
    );
  }
}

class _UpcomingListCompact extends StatelessWidget {
  final List<Deadline> deadlines;

  const _UpcomingListCompact({required this.deadlines});

  @override
  Widget build(BuildContext context) {
    // Sort by date
    final sorted = deadlines.toList()..sort((a, b) {
      try {
        final dateA = DateTime.parse(a.date);
        final dateB = DateTime.parse(b.date);
        return dateA.compareTo(dateB);
      } catch (e) {
        return 0;
      }
    });
    
    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            "No deadlines this week",
            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: sorted.map((deadline) {
        try {
          final deadlineDate = DateTime.parse(deadline.date);
          final now = DateTime.now();
          final daysUntil = deadlineDate.difference(now).inDays;
          
          String urgencyText;
          Color urgencyColor;
          Color bgColor;
          
          if (daysUntil <= 1) {
            urgencyText = daysUntil == 0 ? "Today!" : "Tomorrow";
            urgencyColor = Colors.redAccent;
            bgColor = Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
          } else if (daysUntil <= 3) {
            urgencyText = "In $daysUntil days";
            urgencyColor = Colors.orangeAccent;
            bgColor = Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
          } else {
            urgencyText = "In $daysUntil days";
            urgencyColor = Colors.greenAccent;
            bgColor = Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
          }
          
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: urgencyColor, width: 3),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    deadline.title.length > 30 
                        ? "${deadline.title.substring(0, 30)}..."
                        : deadline.title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: urgencyColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    urgencyText,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: urgencyColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        } catch (e) {
          return const SizedBox.shrink();
        }
      }).toList(),
    );
  }
}

class _MonthlyCalendar extends StatefulWidget {
  final List<Deadline> deadlines;
  final Function(DateTime, List<CalendarEvent>)? onDateSelected;

  const _MonthlyCalendar({required this.deadlines, this.onDateSelected});

  @override
  State<_MonthlyCalendar> createState() => _MonthlyCalendarState();
}

class _MonthlyCalendarState extends State<_MonthlyCalendar> {
  DateTime? _selectedDay;
  late DateTime _focusedDay; // Track focused month

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    // Convert deadlines to calendar events
    final events = <DateTime, List<CalendarEvent>>{};
    for (var deadline in widget.deadlines) {
      try {
        final date = DateTime.parse(deadline.date);
        final dayOnly = DateTime(date.year, date.month, date.day);
        if (events[dayOnly] == null) {
          events[dayOnly] = [];
        }
        // Mark Ayla-added events differently
        final event = CalendarEvent.fromDeadline(deadline);
        events[dayOnly]!.add(event);
      } catch (e) {
        // Skip invalid dates
      }
    }

    return SizedBox(
      height: 400,
      child: TableCalendar<CalendarEvent>(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay, // Use state variable
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDate, focusedDay) {
          setState(() {
            _selectedDay = selectedDate;
            _focusedDay = focusedDay; // Keep focused on selected month
          });
          final dayOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
          final dayEvents = events[dayOnly] ?? [];
          if (widget.onDateSelected != null) {
            widget.onDateSelected!(selectedDate, dayEvents);
          }
        },
        onPageChanged: (focusedDay) {
          _focusedDay = focusedDay; // Track month navigation
        },
        eventLoader: (day) => events[DateTime(day.year, day.month, day.day)] ?? [],
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          weekendTextStyle: GoogleFonts.inter(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),
          defaultTextStyle: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
          todayDecoration: BoxDecoration(
            color: const Color(0xFF111827),
            shape: BoxShape.circle,
          ),
          todayTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          selectedDecoration: BoxDecoration(
            color: Colors.grey[300]!,
            shape: BoxShape.circle,
          ),
          markerDecoration: const BoxDecoration(
            color: Color(0xFF4A5568),
            shape: BoxShape.circle,
          ),
          markerSize: 6,
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
          ),
          leftChevronIcon: Icon(Icons.chevron_left, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
          rightChevronIcon: Icon(Icons.chevron_right, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
          ),
          weekendStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        // Custom markers for different event sources
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, date, eventList) {
            if (eventList.isEmpty) return const SizedBox.shrink();
            
            // Check if any event is from Ayla (exam)
            bool hasAylaEvent = false;
            bool hasMoodleEvent = false;
            
            for (var event in eventList) {
              if (event is CalendarEvent) {
                if (event.platform == 'Ayla') {
                  hasAylaEvent = true;
                } else {
                  hasMoodleEvent = true;
                }
              }
            }
            
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasMoodleEvent)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: const BoxDecoration(
                      color: Color(0xFF3A7BD5), // Themed for Moodle
                      shape: BoxShape.circle,
                    ),
                  ),
                if (hasAylaEvent)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE74C3C), // Red for exams
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final double currentEcts;
  final double maxEcts;
  final double? averageGrade;
  final double? bestGrade;

  const _ProgressCard({
    required this.currentEcts,
    required this.maxEcts,
    this.averageGrade,
    this.bestGrade,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final cardBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final aylaTeal = const Color(0xFF00D2FF);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Speedometer on the LEFT of the box
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SpeedometerGauge(
                currentValue: currentEcts,
                maxValue: maxEcts,
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Grade Statistics on the right
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Best Grade Card
              Container(
                width: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: aylaTeal.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.emoji_events_rounded, size: 16, color: aylaTeal),
                        const SizedBox(width: 6),
                        Text(
                          "Best Grade",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: secondaryColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bestGrade != null ? bestGrade!.toStringAsFixed(1) : "–",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: aylaTeal,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Average Grade Card
              Container(
                width: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Average Grade",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: secondaryColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      averageGrade != null ? averageGrade!.toStringAsFixed(2) : "–",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedometerGauge extends StatelessWidget {
  final double currentValue;
  final double maxValue;

  const _SpeedometerGauge({
    required this.currentValue,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (currentValue / maxValue).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SizedBox(
      width: 280,
      height: 200,
      child: CustomPaint(
        painter: _SpeedometerPainter(
          currentValue: currentValue,
          maxValue: maxValue,
          progress: progress,
          needleAngle: 0,
          isDarkMode: isDark,
        ),
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double currentValue;
  final double maxValue;
  final double progress;
  final double needleAngle;
  final bool isDarkMode;

  _SpeedometerPainter({
    required this.currentValue,
    required this.maxValue,
    required this.progress,
    required this.needleAngle,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.55);
    final radius = size.width * 0.38;
    
    // === THEME COLORS ===
    // Using the app's premium Blue/Teal theme
    // Dark Mode: Vibrant blue/teal gradient
    // Light Mode: Slightly darker blue for readability
    final List<Color> progressGradient = isDarkMode 
        ? [const Color(0xFF00D2FF), const Color(0xFF3A7BD5), const Color(0xFF2D3748)]
        : [const Color(0xFF3A7BD5), const Color(0xFF2D3748), const Color(0xFF1A1A1A)];
    
    final Color trackColor = isDarkMode 
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.12);  // More visible track in light mode
    
    final Color textPrimary = isDarkMode ? Colors.white : const Color(0xFF1F2937);  // Dark gray for light mode
    final Color textSecondary = isDarkMode ? Colors.grey[400]! : const Color(0xFF4B5563);  // Better contrast
    final Color tickColor = isDarkMode 
        ? Colors.white.withOpacity(0.15)
        : Colors.black.withOpacity(0.20);  // More visible ticks in light mode
    
    // Arc angles: 220° sweep starting from bottom-left
    const startAngle = (140 * math.pi) / 180;  // Start at 140°
    const sweepAngle = (260 * math.pi) / 180;  // 260° sweep
    
    // === OUTER GLOW (subtle ambient) ===
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round
      ..color = progressGradient[0].withOpacity(0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress,
      false,
      glowPaint,
    );
    
    // === TRACK ARC ===
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );
    
    // === PROGRESS ARC WITH GRADIENT ===
    final progressRect = Rect.fromCircle(center: center, radius: radius);
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: progressGradient,
        stops: const [0.0, 0.5, 1.0],
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
      ).createShader(progressRect);
    
    if (progress > 0) {
      canvas.drawArc(
        progressRect,
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );
    }
    
    // === TICK MARKS (elegant thin lines) ===
    final tickPaint = Paint()
      ..color = tickColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    for (int i = 0; i <= 10; i++) {
      final tickProgress = i / 10;
      final tickAngle = startAngle + (sweepAngle * tickProgress);
      
      // Longer ticks at 0, 50%, 100%
      final isMain = i == 0 || i == 5 || i == 10;
      final innerRadius = isMain ? radius - 28 : radius - 22;
      final outerRadius = radius - 18;
      
      final startX = center.dx + innerRadius * math.cos(tickAngle);
      final startY = center.dy + innerRadius * math.sin(tickAngle);
      final endX = center.dx + outerRadius * math.cos(tickAngle);
      final endY = center.dy + outerRadius * math.sin(tickAngle);
      
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), tickPaint);
    }
    
    // === NEEDLE/INDICATOR DOT ===
    final needleAngleRad = startAngle + (sweepAngle * progress);
    final dotX = center.dx + radius * math.cos(needleAngleRad);
    final dotY = center.dy + radius * math.sin(needleAngleRad);
    
    // Outer glow
    canvas.drawCircle(
      Offset(dotX, dotY),
      10,
      Paint()
        ..color = progressGradient[0].withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    
    // White/black border
    canvas.drawCircle(
      Offset(dotX, dotY),
      8,
      Paint()..color = isDarkMode ? Colors.white : Colors.black,
    );
    
    // Inner colored dot
    canvas.drawCircle(
      Offset(dotX, dotY),
      5,
      Paint()..color = progressGradient[0],
    );
    
    // === CENTER TEXT ===
    // Main value
    final valueStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 48,
      fontWeight: FontWeight.w700,
      color: textPrimary,
      letterSpacing: -2,
    );
    
    final valuePainter = TextPainter(
      text: TextSpan(text: currentValue.toInt().toString(), style: valueStyle),
      textDirection: ui.TextDirection.ltr,
    );
    valuePainter.layout();
    valuePainter.paint(
      canvas,
      Offset(center.dx - valuePainter.width / 2, center.dy - 30),
    );
    
    // Label "ECTS"
    final labelStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: textSecondary,
      letterSpacing: 2,
    );
    
    final labelPainter = TextPainter(
      text: TextSpan(text: "ECTS", style: labelStyle),
      textDirection: ui.TextDirection.ltr,
    );
    labelPainter.layout();
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy + 22),
    );
    
    // === BOTTOM LABELS (0 and max) ===
    final bottomLabelStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: textSecondary,
    );
    
    // "0" label
    final zeroAngle = startAngle;
    final zeroX = center.dx + (radius + 20) * math.cos(zeroAngle);
    final zeroY = center.dy + (radius + 20) * math.sin(zeroAngle);
    final zeroPainter = TextPainter(
      text: TextSpan(text: "0", style: bottomLabelStyle),
      textDirection: ui.TextDirection.ltr,
    );
    zeroPainter.layout();
    zeroPainter.paint(canvas, Offset(zeroX - zeroPainter.width / 2, zeroY - 6));
    
    // Max label
    final maxAngle = startAngle + sweepAngle;
    final maxX = center.dx + (radius + 20) * math.cos(maxAngle);
    final maxY = center.dy + (radius + 20) * math.sin(maxAngle);
    final maxPainter = TextPainter(
      text: TextSpan(text: maxValue.toInt().toString(), style: bottomLabelStyle),
      textDirection: ui.TextDirection.ltr,
    );
    maxPainter.layout();
    maxPainter.paint(canvas, Offset(maxX - maxPainter.width / 2, maxY - 6));
    
    // === PERCENTAGE BADGE ===
    final percentage = (progress * 100).toInt();
    final badgeStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: isDarkMode ? Colors.black : Colors.white,
    );
    
    // Badge position below the label
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 45), width: 50, height: 20),
      const Radius.circular(10),
    );
    
    // Badge background with gradient
    final badgePaint = Paint()
      ..shader = LinearGradient(
        colors: [progressGradient[0], progressGradient[1]],
      ).createShader(badgeRect.outerRect);
    
    canvas.drawRRect(badgeRect, badgePaint);
    
    final badgePainter = TextPainter(
      text: TextSpan(text: "$percentage%", style: badgeStyle),
      textDirection: ui.TextDirection.ltr,
    );
    badgePainter.layout();
    badgePainter.paint(
      canvas,
      Offset(center.dx - badgePainter.width / 2, center.dy + 39),
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter oldDelegate) {
    return oldDelegate.currentValue != currentValue ||
           oldDelegate.maxValue != maxValue ||
           oldDelegate.progress != progress ||
           oldDelegate.isDarkMode != isDarkMode;
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13)),
                      ]
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _QuickMenuBar extends StatelessWidget {
  final void Function(String section) onSelect;

  const _QuickMenuBar({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = const [
      {'label': 'Overview', 'icon': Icons.dashboard_rounded},
      {'label': 'Classes', 'icon': Icons.class_outlined},
      {'label': 'Deadlines', 'icon': Icons.timer_outlined},
      {'label': 'Exams', 'icon': Icons.school_outlined},
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final label = item['label'] as String;
          final iconData = item['icon'] as IconData;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(label),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(iconData, size: 16, color: const Color(0xFF1E293B)),
                    const SizedBox(width: 6),
                    Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CurrentClassesList extends StatelessWidget {
  final List<String> classes;

  const _CurrentClassesList({required this.classes});

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) {
      return _EmptyState(
        icon: Icons.class_outlined,
        title: "No current classes",
        message: "Your LSF courses for this semester will appear here.",
      );
    }

    return Column(
      children: classes.map((c) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.class_outlined, color: Color(0xFF1E293B), size: 18),
            ),
            title: Text(
              c,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CurrentClassesListCompact extends StatelessWidget {
  final List<String> classes;

  const _CurrentClassesListCompact({required this.classes});

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            "No current classes",
            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: classes.map((className) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.class_outlined, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  className,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PassedExamsList extends StatelessWidget {
  final List<ExamCategory> examRequirements;

  const _PassedExamsList({required this.examRequirements});

  @override
  Widget build(BuildContext context) {
    // Collect all passed exams from all categories
    final passedExams = <Exam>[];
    for (var category in examRequirements) {
      for (var exam in category.exams) {
        if (exam.passed) {
          passedExams.add(exam);
        }
      }
    }

    if (passedExams.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            "No passed exams yet",
            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
          ),
        ),
      );
    }

    // Show all passed exams (scrollable)
    return Column(
      children: passedExams.map((exam) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.name,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      exam.type,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Text(
                  "${exam.ects.toStringAsFixed(0)} CP",
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _UpcomingList extends StatelessWidget {
  final List<Deadline> deadlines;

  const _UpcomingList({required this.deadlines});

  @override
  Widget build(BuildContext context) {
    // Filter out submission actions (double check) and sort by date
    final filtered = filterRealDeadlines(deadlines);
    
    // Sort by date (earliest first)
    final sorted = filtered.toList()..sort((a, b) {
      try {
        final dateA = DateTime.parse(a.date);
        final dateB = DateTime.parse(b.date);
        return dateA.compareTo(dateB);
      } catch (e) {
        return 0;
      }
    });
    
    // Show up to 3 most urgent deadlines
    final list = sorted.take(3).toList();
    
    if (list.isEmpty) {
      return _EmptyState(
        icon: Icons.timer_outlined,
        title: "No upcoming deadlines",
        message: "Deadlines from Moodle will show up here.",
      );
    }

    return Column(
      children: list.map((d) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.timer_outlined, color: Colors.red[700], size: 18),
          ),
          title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Text(d.course, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(d.rawDate.split(',').last.trim(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(d.platform, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
        ),
      )).toList(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, color: const Color(0xFF1E293B), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(message, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamRequirementsList extends StatelessWidget {
  final List<ExamCategory> examRequirements;

  const _ExamRequirementsList({required this.examRequirements});

  @override
  Widget build(BuildContext context) {
    if (examRequirements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Text(
          "No exam requirements available",
          style: TextStyle(color: Colors.grey[400]),
        ),
      );
    }

    return Column(
      children: examRequirements.map((category) {
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          color: Colors.white.withOpacity(0.05),
          child: ExpansionTile(
            collapsedIconColor: Colors.white,
            iconColor: Colors.white,
            title: Text(
              category.category,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school_rounded, color: Colors.purpleAccent, size: 20),
            ),
            children: category.exams.map((exam) {
              // Determine if exam is passed
              final isPassed = exam.passed;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                color: isPassed ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                elevation: isPassed ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isPassed ? Colors.greenAccent.withOpacity(0.3) : Colors.white12,
                    width: isPassed ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPassed 
                          ? Colors.green.withOpacity(0.2) 
                          : (exam.required ? Colors.blue.withOpacity(0.1) : Colors.white10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPassed ? Colors.greenAccent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      isPassed 
                          ? Icons.check_circle 
                          : (exam.required ? Icons.radio_button_unchecked : Icons.help_outline),
                      color: isPassed 
                          ? Colors.greenAccent 
                          : (exam.required ? Colors.blueAccent : Colors.grey[400]),
                      size: 24,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          exam.name,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: isPassed ? FontWeight.w500 : FontWeight.w600,
                            color: isPassed ? Colors.white : Colors.white70,
                            decoration: isPassed ? TextDecoration.lineThrough : TextDecoration.none,
                            decorationColor: Colors.white54,
                          ),
                        ),
                      ),
                      if (isPassed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check, color: Colors.greenAccent, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                "PASSED",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.greenAccent,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      exam.type,
                      style: TextStyle(
                        fontSize: 12, 
                        color: isPassed ? Colors.green[700] : Colors.grey[600],
                        fontWeight: isPassed ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPassed ? Colors.green[600] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${exam.ects.toStringAsFixed(0)} CP",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isPassed ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

// Minimal CircularPercentIndicator implementation to avoid extra dependency (or could use existing SpinKit?)
// Added simple custom widget.
class CircularPercentIndicator extends StatelessWidget {
  final double radius;
  final double lineWidth;
  final double percent;
  final Widget center;
  final Color progressColor;
  final Color backgroundColor;

  const CircularPercentIndicator({
    super.key, 
    required this.radius, 
    required this.lineWidth, 
    required this.percent, 
    required this.center, 
    required this.progressColor, 
    required this.backgroundColor
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percent,
            strokeWidth: lineWidth,
            color: progressColor,
            backgroundColor: backgroundColor,
          ),
          center,
        ],
      ),
    );
  }
}

// Event Dialog for adding/editing custom events
class _EventDialog extends StatefulWidget {
  final DateTime? initialDate;
  final CustomEvent? customEvent;

  const _EventDialog({this.initialDate, this.customEvent});

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _selectedColor = '#6366F1';

  final List<Map<String, String>> _colors = [
    {'name': 'Purple', 'hex': '#6366F1'},
    {'name': 'Blue', 'hex': '#3B82F6'},
    {'name': 'Green', 'hex': '#10B981'},
    {'name': 'Orange', 'hex': '#F97316'},
    {'name': 'Red', 'hex': '#EF4444'},
    {'name': 'Pink', 'hex': '#EC4899'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.customEvent != null) {
      _titleController = TextEditingController(text: widget.customEvent!.title);
      _descriptionController = TextEditingController(text: widget.customEvent!.description);
      _locationController = TextEditingController(text: widget.customEvent!.location ?? '');
      _selectedDate = widget.customEvent!.date;
      _selectedTime = TimeOfDay.fromDateTime(widget.customEvent!.date);
      _selectedColor = widget.customEvent!.color;
    } else {
      _titleController = TextEditingController();
      _descriptionController = TextEditingController();
      _locationController = TextEditingController();
      _selectedDate = widget.initialDate ?? DateTime.now();
      _selectedTime = TimeOfDay.now();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _saveEvent() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final event = CustomEvent(
      id: widget.customEvent?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      date: dateTime,
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      color: _selectedColor,
    );

    Navigator.pop(context, event);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customEvent == null ? 'Add Event' : 'Edit Event'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat('MMM d, yyyy').format(_selectedDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _selectTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Time',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time),
                      ),
                      child: Text(_selectedTime.format(context)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Color:', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _colors.map((color) {
                final isSelected = _selectedColor == color['hex'];
                return InkWell(
                  onTap: () => setState(() => _selectedColor = color['hex']!),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(int.parse(color['hex']!.replaceAll('#', '0xFF'))),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveEvent,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
