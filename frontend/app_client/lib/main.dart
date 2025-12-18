import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';
import 'session_service.dart';
import 'widgets/glass_container.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/workspace_page.dart';

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
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E293B),
              secondary: Color(0xFF64748B),
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
              bodyColor: const Color(0xFF1E293B),
              displayColor: const Color(0xFF1E293B),
            ),
            iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF020617),
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              secondary: Color(0xFF94A3B8),
              surface: Color(0xFF0F172A),
              onSurface: Colors.white,
            ),
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          currentPage,
          if (_isSidebarOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isSidebarOpen = false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            left: _isSidebarOpen ? 0 : -260,
            top: 0,
            bottom: 0,
            child: GlassContainer(
              width: 260,
              borderRadius: 0,
              opacity: isDark ? 0.08 : 0.4,
              blur: 20,
              border: Border(right: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 60, 20, 40),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38B6FF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF38B6FF), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Ayla", 
                          style: GoogleFonts.inter(
                            fontSize: 22, 
                            fontWeight: FontWeight.w700, 
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                            letterSpacing: -0.5,
                          )
                        ),
                      ],
                    ),
                  ),
                  SidebarMenuItem(
                    icon: Icons.grid_view_rounded, 
                    label: "Overview", 
                    isSelected: _selectedIndex == 0, 
                    onTap: () => setState(() { _selectedIndex = 0; _isSidebarOpen = false; })
                  ),
                  const SizedBox(height: 4),
                  SidebarMenuItem(
                    icon: Icons.layers_rounded, 
                    label: "Workspace", 
                    isSelected: _selectedIndex == 1, 
                    onTap: () => setState(() { _selectedIndex = 1; _isSidebarOpen = false; })
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _SidebarActionButton(
                          label: "Reset Data",
                          icon: Icons.refresh_rounded,
                          onTap: () async { 
                            await SessionService.clearSession(); 
                            if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage())); 
                          },
                        ),
                        const SizedBox(height: 8),
                        _SidebarActionButton(
                          label: "Sign Out",
                          icon: Icons.logout_rounded,
                          onTap: () async { 
                            await SessionService.clearCredentials(); 
                            if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage())); 
                          },
                          isDestructive: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isSidebarOpen)
            Positioned(
              top: 24,
              left: 24,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _isSidebarOpen = true),
                  borderRadius: BorderRadius.circular(12),
                  child: GlassContainer(
                    padding: const EdgeInsets.all(10),
                    borderRadius: 12,
                    opacity: isDark ? 0.05 : 0.1,
                    child: Icon(
                      Icons.menu_open_rounded, 
                      color: isDark ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.7), 
                      size: 22
                    ),
                  ),
                ),
              ),
            ),
          if (_isChatOpen)
            Positioned(
              right: 24,
              bottom: 24,
              child: AylaFloatingChat(session: widget.session, onClose: () => setState(() => _isChatOpen = false), onEventAdded: _refreshDashboard),
            ),
        ],
      ),
      floatingActionButton: _isChatOpen ? null : AylaChatButton(
        onPressed: () => setState(() => _isChatOpen = true),
      ),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SidebarActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isDestructive 
              ? Colors.redAccent.withOpacity(0.05) 
              : (isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDestructive 
                ? Colors.redAccent.withOpacity(0.1) 
                : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isDestructive ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black54)),
            const SizedBox(width: 12),
            Text(
              label, 
              style: GoogleFonts.inter(
                fontSize: 13, 
                fontWeight: FontWeight.w500, 
                color: isDestructive ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black54)
              )
            ),
          ],
        ),
      ),
    );
  }
}
