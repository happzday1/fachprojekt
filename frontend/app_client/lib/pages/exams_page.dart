import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../widgets/glass_container.dart';

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
          Container(
            padding: const EdgeInsets.only(left: 80, top: 20, right: 32, bottom: 20),
            child: Row(
              children: [
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

class _ExamRequirementsList extends StatelessWidget {
  final List<ExamCategory> examRequirements;
  const _ExamRequirementsList({required this.examRequirements});

  @override
  Widget build(BuildContext context) {
    if (examRequirements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Text("No exam requirements available", style: TextStyle(color: Colors.grey[400])),
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
            title: Text(category.category, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.school_rounded, color: Colors.purpleAccent, size: 20)),
            children: category.exams.map((exam) {
              final isPassed = exam.passed;
              return Card(
                margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                color: isPassed ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isPassed ? Colors.greenAccent.withOpacity(0.3) : Colors.white12, width: isPassed ? 2 : 1)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: isPassed ? Colors.green.withOpacity(0.2) : (exam.required ? Colors.blue.withOpacity(0.1) : Colors.white10), shape: BoxShape.circle, border: Border.all(color: isPassed ? Colors.greenAccent : Colors.transparent, width: 2)), child: Icon(isPassed ? Icons.check_circle : (exam.required ? Icons.radio_button_unchecked : Icons.help_outline), color: isPassed ? Colors.greenAccent : (exam.required ? Colors.blueAccent : Colors.grey[400]), size: 24)),
                  title: Row(children: [Expanded(child: Text(exam.name, style: GoogleFonts.inter(fontSize: 15, fontWeight: isPassed ? FontWeight.w500 : FontWeight.w600, color: isPassed ? Colors.white : Colors.white70, decoration: isPassed ? TextDecoration.lineThrough : TextDecoration.none, decorationColor: Colors.white54))), if (isPassed) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check, color: Colors.greenAccent, size: 14), const SizedBox(width: 4), Text("PASSED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent, letterSpacing: 0.5))]))]]),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(exam.type, style: TextStyle(fontSize: 12, color: isPassed ? Colors.green[700] : Colors.grey[600], fontWeight: isPassed ? FontWeight.w500 : FontWeight.normal))),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
