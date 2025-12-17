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
    final progress = (session.ectsData.totalEcts / 180) * 100;
    final firstName = session.profileName.split(' ')[0];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(left: 80, top: 20, right: 32, bottom: 20),
            child: Row(
              children: [
                Text(
                  "Dashboard",
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
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
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      )
                    : IconButton(
                        icon: Icon(Icons.refresh_rounded, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
                        onPressed: _refreshData,
                      ),
                const SizedBox(width: 8),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, currentMode, child) {
                    final isDark = currentMode == ThemeMode.dark;
                    return IconButton(
                      icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: isDark ? Colors.white : Colors.black),
                      onPressed: () => themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark,
                    );
                  },
                ),
                const SizedBox(width: 16),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  child: Text(
                    firstName[0].toUpperCase(),
                    style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            GlassContainer(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Progress Overview", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
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
                            GlassContainer(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Upcoming Deadlines", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                                  const SizedBox(height: 16),
                                  SizedBox(height: 200, child: SingleChildScrollView(child: _UpcomingListCompact(deadlines: realDeadlines))),
                                  if (session.currentClasses.isNotEmpty) ...[
                                    const SizedBox(height: 24),
                                    const Divider(),
                                    const SizedBox(height: 16),
                                    Text("Current Classes", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                                    const SizedBox(height: 16),
                                    SizedBox(height: 200, child: SingleChildScrollView(child: _CurrentClassesListCompact(classes: session.currentClasses))),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: GlassContainer(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Monthly", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
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
                              if (_selectedDateEvents != null && _selectedDateEvents!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Divider(color: Colors.white24),
                                const SizedBox(height: 16),
                                Text(DateFormat('EEEE, d MMMM').format(_selectedCalendarDate!), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                                const SizedBox(height: 12),
                                ..._selectedDateEvents!.map((event) {
                                  final colors = [const Color(0xFF3498DB), const Color(0xFFE74C3C), const Color(0xFF00D2FF), const Color(0xFF9B59B6), const Color(0xFFF39C12)];
                                  final eventColor = colors[event.title.hashCode.abs() % colors.length];
                                  final timeString = DateFormat('HH:mm').format(event.date);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: eventColor, width: 4))),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(event.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.access_time, size: 12, color: Colors.white60),
                                                    const SizedBox(width: 4),
                                                    Text(timeString, style: GoogleFonts.inter(fontSize: 11, color: Colors.white60)),
                                                    if (event.course != null && event.course!.isNotEmpty) ...[
                                                      const SizedBox(width: 12),
                                                      Expanded(child: Text(event.course!, style: GoogleFonts.inter(fontSize: 11, color: Colors.white60), overflow: TextOverflow.ellipsis)),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (event.platform == 'Ayla')
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white54),
                                              onPressed: () async {
                                                final eventId = int.tryParse(event.id);
                                                if (eventId != null) {
                                                  final success = await AylaService.deleteEvent(eventId);
                                                  if (success && mounted) {
                                                    _fetchSavedEvents();
                                                    setState(() => _selectedDateEvents = null);
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
                              if (session.examRequirements.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                const Divider(color: Colors.white24),
                                const SizedBox(height: 16),
                                Text("Passed Exams", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                                const SizedBox(height: 12),
                                SizedBox(height: 200, child: SingleChildScrollView(child: _PassedExamsList(examRequirements: session.examRequirements))),
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

class _UpcomingListCompact extends StatelessWidget {
  final List<Deadline> deadlines;
  const _UpcomingListCompact({required this.deadlines});

  @override
  Widget build(BuildContext context) {
    final sorted = deadlines.toList()..sort((a, b) {
      try { return DateTime.parse(a.date).compareTo(DateTime.parse(b.date)); } catch (e) { return 0; }
    });
    if (sorted.isEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text("No deadlines this week", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600], fontSize: 14))));
    }
    return Column(
      children: sorted.map((deadline) {
        try {
          final deadlineDate = DateTime.parse(deadline.date);
          final daysUntil = deadlineDate.difference(DateTime.now()).inDays;
          Color urgencyColor = daysUntil <= 1 ? Colors.redAccent : (daysUntil <= 3 ? Colors.orangeAccent : Colors.greenAccent);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: urgencyColor, width: 3))),
            child: Row(
              children: [
                Expanded(child: Text(deadline.title.length > 30 ? "${deadline.title.substring(0, 30)}..." : deadline.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: urgencyColor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Text(daysUntil == 0 ? "Today!" : (daysUntil == 1 ? "Tomorrow" : "In $daysUntil days"), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: urgencyColor))),
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
    final events = <DateTime, List<CalendarEvent>>{};
    for (var deadline in widget.deadlines) {
      try {
        final date = DateTime.parse(deadline.date);
        final dayOnly = DateTime(date.year, date.month, date.day);
        events.putIfAbsent(dayOnly, () => []).add(CalendarEvent.fromDeadline(deadline));
      } catch (e) {}
    }

    return SizedBox(
      height: 400,
      child: TableCalendar<CalendarEvent>(
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
          weekendTextStyle: GoogleFonts.inter(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),
          defaultTextStyle: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
          todayDecoration: const BoxDecoration(color: Color(0xFF111827), shape: BoxShape.circle),
          todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          selectedDecoration: BoxDecoration(color: Colors.grey[300]!, shape: BoxShape.circle),
          markerDecoration: const BoxDecoration(color: Color(0xFF4A5568), shape: BoxShape.circle),
          markerSize: 6,
        ),
        headerStyle: HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, date, eventList) {
            if (eventList.isEmpty) return const SizedBox.shrink();
            bool hasAylaEvent = eventList.any((e) => e.platform == 'Ayla');
            bool hasMoodleEvent = eventList.any((e) => e.platform != 'Ayla');
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasMoodleEvent) Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: const BoxDecoration(color: Color(0xFF3A7BD5), shape: BoxShape.circle)),
                if (hasAylaEvent) Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: const BoxDecoration(color: Color(0xFFE74C3C), shape: BoxShape.circle)),
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
  const _ProgressCard({required this.currentEcts, required this.maxEcts, this.averageGrade, this.bestGrade});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: _SpeedometerGauge(currentValue: currentEcts, maxValue: maxEcts))),
          const SizedBox(width: 24),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00D2FF).withOpacity(0.3))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Avg Grade", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                    const SizedBox(height: 8),
                    Text(averageGrade != null ? averageGrade!.toStringAsFixed(2) : "–", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
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
  const _SpeedometerGauge({required this.currentValue, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 280, height: 200, child: CustomPaint(painter: _SpeedometerPainter(currentValue: currentValue, maxValue: maxValue, progress: (currentValue / maxValue).clamp(0.0, 1.0), isDarkMode: Theme.of(context).brightness == Brightness.dark)));
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double currentValue, maxValue, progress;
  final bool isDarkMode;
  _SpeedometerPainter({required this.currentValue, required this.maxValue, required this.progress, required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.55);
    final radius = size.width * 0.38;
    const startAngle = (140 * math.pi) / 180, sweepAngle = (260 * math.pi) / 180;
    final List<Color> progressGradient = isDarkMode ? [const Color(0xFF00D2FF), const Color(0xFF3A7BD5), const Color(0xFF2D3748)] : [const Color(0xFF3A7BD5), const Color(0xFF2D3748), const Color(0xFF1A1A1A)];
    
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, Paint()..color = isDarkMode ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.12)..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round);
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle * progress, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round..shader = SweepGradient(colors: progressGradient, stops: const [0.0, 0.5, 1.0], startAngle: startAngle, endAngle: startAngle + sweepAngle).createShader(Rect.fromCircle(center: center, radius: radius)));
    }
    
    final textPainter = TextPainter(text: TextSpan(text: currentValue.toInt().toString(), style: GoogleFonts.inter(fontSize: 42, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black)), textDirection: ui.TextDirection.ltr)..layout();
    textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
    final labelPainter = TextPainter(text: TextSpan(text: "ECTS", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.grey[400] : Colors.grey[600], letterSpacing: 2)), textDirection: ui.TextDirection.ltr)..layout();
    labelPainter.paint(canvas, center + Offset(-labelPainter.width / 2, textPainter.height / 2 + 2));
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _CurrentClassesListCompact extends StatelessWidget {
  final List<String> classes;
  const _CurrentClassesListCompact({required this.classes});

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text("No current classes", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]))));
    return Column(children: classes.map((c) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(Icons.class_outlined, size: 16), const SizedBox(width: 12), Expanded(child: Text(c, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)))]))).toList());
  }
}

class _PassedExamsList extends StatelessWidget {
  final List<ExamCategory> examRequirements;
  const _PassedExamsList({required this.examRequirements});

  @override
  Widget build(BuildContext context) {
    final passed = examRequirements.expand((c) => c.exams).where((e) => e.passed).toList();
    if (passed.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text("No passed exams yet", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]))));
    return Column(children: passed.map((e) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(Icons.check_circle_outline, size: 16, color: Colors.greenAccent), const SizedBox(width: 12), Expanded(child: Text(e.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)))]))).toList());
  }
}
