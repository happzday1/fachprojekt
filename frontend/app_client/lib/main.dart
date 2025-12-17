import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'models.dart';
import 'session_service.dart';
import 'widgets/glass_container.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/workspace_page.dart';
import 'pages/exams_page.dart';
import 'widgets/ayla_chat.dart';
import 'widgets/sidebar_menu_item.dart';

void main() {
  runApp(const Ayla());
}

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
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
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
              onPrimary: Colors.black,
              onSurface: Colors.white,
            ),
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
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
  int _dashboardKey = 0;

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
      case 2:
        currentPage = ExamsPage(session: widget.session, onNavigate: (index) => setState(() => _selectedIndex = index));
        break;
      default:
        currentPage = DashboardPage(key: ValueKey(_dashboardKey), session: widget.session, onNavigate: (index) => setState(() => _selectedIndex = index));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          currentPage,
          if (_isSidebarOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isSidebarOpen = false),
                child: Container(color: Colors.black.withOpacity(0.3)),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: _isSidebarOpen ? 0 : -240,
            top: 0,
            bottom: 0,
            child: GlassContainer(
              width: 240,
              borderRadius: 0,
              color: Theme.of(context).brightness == Brightness.dark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.8),
              border: Border(right: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Ayla", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                        IconButton(icon: Icon(Icons.close, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black, size: 20), onPressed: () => setState(() => _isSidebarOpen = false)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SidebarMenuItem(icon: Icons.dashboard_rounded, label: "Dashboard", isSelected: _selectedIndex == 0, onTap: () => setState(() { _selectedIndex = 0; _isSidebarOpen = false; })),
                  const SizedBox(height: 8),
                  SidebarMenuItem(icon: Icons.workspaces_rounded, label: "Workspace", isSelected: _selectedIndex == 1, onTap: () => setState(() { _selectedIndex = 1; _isSidebarOpen = false; })),
                  const SizedBox(height: 8),
                  SidebarMenuItem(icon: Icons.school_rounded, label: "Exams", isSelected: _selectedIndex == 2, onTap: () => setState(() { _selectedIndex = 2; _isSidebarOpen = false; })),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async { await SessionService.clearSession(); if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage())); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D3748), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text("Refresh Data"))),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async { await SessionService.clearCredentials(); if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage())); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D3748), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text("Logout"))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isSidebarOpen)
            Positioned(
              top: 20,
              left: 20,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12)), child: Icon(Icons.menu, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black, size: 24)),
                ),
              ),
            ),
          if (_isChatOpen)
            Positioned(
              right: 16,
              bottom: 16,
              child: AylaFloatingChat(session: widget.session, onClose: () => setState(() => _isChatOpen = false), onEventAdded: _refreshDashboard),
            ),
        ],
      ),
      floatingActionButton: _isChatOpen ? null : AylaChatButton(
        onPressed: () => setState(() => _isChatOpen = true),
        initials: widget.session.profileName.trim().isNotEmpty ? widget.session.profileName.trim().split(' ')[0][0].toUpperCase() : null,
      ),
    );
  }
}
