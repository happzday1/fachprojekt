import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../api_service.dart';
import '../session_service.dart';
import '../models.dart';
import '../ayla_service.dart';
import '../widgets/glass_container.dart';
import '../main.dart'; // To access themeNotifier

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
  List<Deadline> _savedEvents = [];
  bool _isRefreshing = false;
  late SessionData _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _fetchSavedEvents();
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    
    try {
      final credentials = await SessionService.loadCredentials();
      if (credentials != null) {
        final newSession = await ApiService.login(
          credentials['username']!,
          credentials['password']!,
          forceRefresh: true,
        );
        
        if (newSession != null && mounted) {
          await SessionService.saveSession(newSession);
          setState(() {
            _session = newSession;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dashboard updated successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: ${e.toString()}'), backgroundColor: Colors.red),
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
            link: e['id']?.toString() ?? '',
            rawDate: '',
          )).toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching saved events: $e");
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final realDeadlines = filterRealDeadlines(session.moodleDeadlines);
    final allDeadlines = [...realDeadlines, ..._savedEvents];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Simplified Header
          Container(
            padding: const EdgeInsets.only(left: 88, top: 32, right: 32, bottom: 24),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Overview",
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Welcome back, ${session.profileName.split(' ')[0]}",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_isRefreshing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                  )
                else
                  IconButton(
                    tooltip: "Refresh Data",
                    icon: Icon(Icons.refresh_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 20),
                    onPressed: _refreshData,
                  ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Content Column
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        // Statistics Row (Grouped)
                        _buildStatsRow(session, isDark),
                        const SizedBox(height: 24),
                        
                        // Deadlines & Classes Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildSectionCard(
                                title: "Deadlines",
                                icon: Icons.timer_outlined,
                                color: Colors.redAccent,
                                child: _UpcomingListCompact(deadlines: realDeadlines),
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildSectionCard(
                                title: "Classes",
                                icon: Icons.auto_stories_rounded,
                                color: const Color(0xFF38B6FF),
                                child: _CurrentClassesListCompact(classes: session.currentClasses),
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  
                  // Sidebar Content Column (Calendar & Passed)
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _buildSectionCard(
                          title: "Calendar",
                          icon: Icons.calendar_today_rounded,
                          color: Colors.amber,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _MonthlyCalendar(
                                deadlines: allDeadlines,
                                onDateSelected: (date, events) {
                                  setState(() {
                                    _selectedCalendarDate = date;
                                    _selectedDateEvents = events;
                                  });
                                },
                              ),
                              if (_selectedDateEvents != null && _selectedDateEvents!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Divider(height: 1, color: Colors.white12),
                                const SizedBox(height: 16),
                                Text(
                                  DateFormat('EEEE, d MMMM').format(_selectedCalendarDate!),
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black.withOpacity(0.7)),
                                ),
                                const SizedBox(height: 12),
                                ..._selectedDateEvents!.map((event) => _buildEventItem(event, isDark)),
                              ],
                            ],
                          ),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 24),
                        _buildSectionCard(
                          title: "Exams",
                          icon: Icons.verified_rounded,
                          color: Colors.tealAccent,
                          child: SizedBox(
                            height: 140, // Height for roughly 3 items
                            child: _PassedExamsList(examRequirements: session.examRequirements),
                          ),
                          isDark: isDark,
                        ),
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

  Widget _buildStatsRow(SessionData session, bool isDark) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      borderRadius: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem("ECTS Progress", "${session.ectsData.totalEcts.toInt()}/180", Icons.analytics_rounded, const Color(0xFF38B6FF), isDark),
          _buildDivider(isDark),
          _buildStatItem("Average Grade", session.ectsData.averageGrade?.toStringAsFixed(2) ?? "–", Icons.auto_graph_rounded, Colors.orangeAccent, isDark),
          _buildDivider(isDark),
          _buildStatItem("Best Achievement", session.ectsData.bestGrade?.toStringAsFixed(2) ?? "–", Icons.military_tech_rounded, Colors.amber, isDark),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color, bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 16),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white38 : Colors.black38,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 60,
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Color color, required Widget child, required bool isDark}) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.7), size: 18),
              const SizedBox(width: 12),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white54 : Colors.black54,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildEventItem(CalendarEvent event, bool isDark) {
    final eventColor = Colors.primaries[event.title.hashCode % Colors.primaries.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 24,
            decoration: BoxDecoration(color: eventColor, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 2),
                Text(
                  "${DateFormat('HH:mm').format(event.date)} ${event.course ?? ''}", 
                  style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingListCompact extends StatelessWidget {
  final List<Deadline> deadlines;
  const _UpcomingListCompact({required this.deadlines});

  @override
  Widget build(BuildContext context) {
    final sorted = deadlines.toList()..sort((a, b) {
      try { return DateTime.parse(a.date).compareTo(DateTime.parse(b.date)); } catch (e) { return 0; }
    });
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (sorted.isEmpty) {
      return Center(child: Text("All caught up!", style: GoogleFonts.inter(color: isDark ? Colors.white24 : Colors.black.withOpacity(0.24), fontSize: 13)));
    }
    return Column(
      children: sorted.take(5).map((deadline) {
        try {
          final deadlineDate = DateTime.parse(deadline.date);
          final daysUntil = deadlineDate.difference(DateTime.now()).inDays;
          Color urgencyColor = daysUntil <= 1 ? Colors.redAccent : (daysUntil <= 3 ? Colors.orangeAccent : Colors.tealAccent);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deadline.title, 
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deadline.course, 
                        style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: urgencyColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    daysUntil == 0 ? "Today" : (daysUntil == 1 ? "Tomorrow" : "$daysUntil days"), 
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: urgencyColor)
                  ),
                ),
              ],
            ),
          );
        } catch (e) { return const SizedBox.shrink(); }
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
  late DateTime _focusedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final events = <DateTime, List<CalendarEvent>>{};
    for (var deadline in widget.deadlines) {
      try {
        final date = DateTime.parse(deadline.date);
        final dayOnly = DateTime(date.year, date.month, date.day);
        events.putIfAbsent(dayOnly, () => []).add(CalendarEvent.fromDeadline(deadline));
      } catch (e) {}
    }

    return TableCalendar<CalendarEvent>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDate, focusedDay) {
        setState(() { _selectedDay = selectedDate; _focusedDay = focusedDay; });
        widget.onDateSelected?.call(selectedDate, events[DateTime(selectedDate.year, selectedDate.month, selectedDate.day)] ?? []);
      },
      onPageChanged: (focusedDay) => _focusedDay = focusedDay,
      eventLoader: (day) => events[DateTime(day.year, day.month, day.day)] ?? [],
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        weekendTextStyle: GoogleFonts.inter(color: Colors.redAccent.withOpacity(0.6), fontSize: 13),
        defaultTextStyle: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white70 : Colors.black.withOpacity(0.7)),
        todayDecoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1), shape: BoxShape.circle),
        todayTextStyle: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
        selectedDecoration: const BoxDecoration(color: Color(0xFF38B6FF), shape: BoxShape.circle),
        selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        markerDecoration: const BoxDecoration(color: Color(0xFF38B6FF), shape: BoxShape.circle),
        markerSize: 4,
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: false, 
        titleCentered: true, 
        titleTextStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1E293B)),
        leftChevronIcon: Icon(Icons.chevron_left_rounded, color: isDark ? Colors.white38 : Colors.black38),
        rightChevronIcon: Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : Colors.black38),
      ),
    );
  }
}

class _CurrentClassesListCompact extends StatelessWidget {
  final List<String> classes;
  const _CurrentClassesListCompact({required this.classes});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (classes.isEmpty) return Center(child: Text("No active classes", style: GoogleFonts.inter(color: isDark ? Colors.white24 : Colors.black.withOpacity(0.24), fontSize: 13)));
    return Column(
      children: classes.map((c) => Container(
        margin: const EdgeInsets.only(bottom: 12), 
        padding: const EdgeInsets.all(16), 
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
        ), 
        child: Row(
          children: [
            Icon(Icons.bookmark_rounded, size: 16, color: const Color(0xFF38B6FF).withOpacity(0.6)), 
            const SizedBox(width: 16), 
            Expanded(child: Text(c, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black87)))
          ]
        )
      )).toList()
    );
  }
}

class _PassedExamsList extends StatelessWidget {
  final List<ExamCategory> examRequirements;
  const _PassedExamsList({required this.examRequirements});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final passed = examRequirements.expand((c) => c.exams).where((e) => e.passed).toList();
    if (passed.isEmpty) return Center(child: Text("No results found", style: GoogleFonts.inter(color: isDark ? Colors.white24 : Colors.black.withOpacity(0.24), fontSize: 13)));
    final ScrollController controller = ScrollController();
    
    return Theme(
      data: Theme.of(context).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(isDark ? Colors.white24 : Colors.black12),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(4),
        ),
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: ListView.builder(
          controller: controller,
          padding: const EdgeInsets.only(right: 8), // Room for scrollbar
          itemCount: passed.length,
          itemBuilder: (context, index) {
            final e = passed[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8), 
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02), 
                borderRadius: BorderRadius.circular(12),
              ), 
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: Colors.tealAccent), 
                  const SizedBox(width: 12), 
                  Expanded(
                    child: Text(
                      e.name, 
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black.withOpacity(0.7)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  )
                ]
              )
            );
          },
        ),
      ),
    );
  }
}
