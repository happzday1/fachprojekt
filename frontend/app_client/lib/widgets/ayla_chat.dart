import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../workspace_service.dart';

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

class AylaChatButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String? initials;

  const AylaChatButton({super.key, required this.onPressed, this.initials});

  @override
  State<AylaChatButton> createState() => _AylaChatButtonState();
}

class _AylaChatButtonState extends State<AylaChatButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
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
          width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)]),
            boxShadow: [
              BoxShadow(color: const Color(0xFF3A7BD5).withOpacity(0.4), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 4)),
              BoxShadow(color: const Color(0xFF00D2FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 5),
            ],
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.initials != null)
                Text(widget.initials!, style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))
              else
                const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
              Positioned(right: 12, top: 12, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF00D2FF), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
            ],
          ),
        ),
      ),
    );
  }
}

class AylaFloatingChat extends StatefulWidget {
  final SessionData session;
  final VoidCallback onClose;
  final VoidCallback? onEventAdded;

  const AylaFloatingChat({super.key, required this.session, required this.onClose, this.onEventAdded});

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
    _animController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _messages.add(ChatMessage(text: "Hi! I'm Ayla, your AI study companion 📚\nHow can I help you today?", isUser: false));
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
    return {
      'student_name': widget.session.profileName,
      'degree_program': grades.degreeProgram ?? 'Unknown',
      'total_ects': grades.totalEcts,
      'courses_count': grades.coursesCount,
      'average_grade': grades.averageGrade,
      'best_grade': grades.bestGrade,
      'current_date': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() { _messages.add(ChatMessage(text: text, isUser: true)); _isLoading = true; });
    _messageController.clear();
    _scrollToBottom();
    try {
      final contextMap = _buildStudentContext();
      final userId = widget.session.profileName.toLowerCase().replaceAll(' ', '_');
      final response = await WorkspaceService.sendGeminiChat(text, userId: userId, studentContext: {
        'name': widget.session.profileName,
        'ects': contextMap['total_ects'],
        'degree': contextMap['degree_program'],
      });
      if (mounted) {
        setState(() { _messages.add(ChatMessage(text: response ?? "No response received.", isUser: false)); _isLoading = false; });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _messages.add(ChatMessage(text: "Sorry, I couldn't process that. ${e.toString().replaceAll('Exception: ', '')}", isUser: false)); _isLoading = false; });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final chatWidth = screenWidth > 600 ? 420.0 : screenWidth * 0.85;
    return ScaleTransition(
      scale: _scaleAnim,
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        elevation: 20,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _isMinimized ? 56 : chatWidth,
          height: _isMinimized ? 56 : 550,
          decoration: BoxDecoration(color: isDark ? const Color(0xFF1a1a1a) : Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: isDark ? const Color(0xFF3A7BD5).withOpacity(0.3) : Colors.grey.shade300, width: 1.5)),
          child: _isMinimized ? _buildMinimizedView() : _buildExpandedView(isDark),
        ),
      ),
    );
  }

  Widget _buildMinimizedView() {
    return InkWell(
      onTap: () => setState(() => _isMinimized = false),
      borderRadius: BorderRadius.circular(24),
      child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)]), borderRadius: BorderRadius.circular(24)), child: const Center(child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26))),
    );
  }

  Widget _buildExpandedView(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)])),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Ayla", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)), Text("AI Study Companion", style: GoogleFonts.inter(fontSize: 11, color: Colors.white70))])),
              IconButton(icon: const Icon(Icons.remove_rounded, color: Colors.white70, size: 20), onPressed: () => setState(() => _isMinimized = true)),
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), onPressed: widget.onClose),
            ]),
          ),
          Expanded(child: ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(12), itemCount: _messages.length + (_isLoading ? 1 : 0), itemBuilder: (context, index) { if (index == _messages.length && _isLoading) return _buildTypingIndicator(isDark); return _buildMessage(_messages[index], isDark); })),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.shade50, border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200))),
            child: Row(children: [
              Expanded(child: TextField(controller: _messageController, style: GoogleFonts.inter(fontSize: 14, color: isDark ? Colors.white : Colors.black87), decoration: InputDecoration(hintText: "Ask anything...", hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 14), filled: true, fillColor: isDark ? Colors.white.withOpacity(0.08) : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), isDense: true), onSubmitted: (_) => _sendMessage())),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFF3A7BD5)), onPressed: _sendMessage),
            ]),
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
          if (!message.isUser) ...[Container(width: 26, height: 26, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)]), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14)), const SizedBox(width: 6)],
          Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: message.isUser ? const Color(0xFF3A7BD5).withOpacity(0.9) : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100), borderRadius: BorderRadius.circular(16).copyWith(bottomRight: message.isUser ? const Radius.circular(4) : null, bottomLeft: !message.isUser ? const Radius.circular(4) : null), border: Border.all(color: message.isUser ? Colors.transparent : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)))), child: message.isUser ? Text(message.text, style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: Colors.white)) : MarkdownBody(data: message.text, styleSheet: MarkdownStyleSheet(p: GoogleFonts.inter(fontSize: 13, height: 1.4, color: isDark ? Colors.white : Colors.black87), a: GoogleFonts.inter(color: const Color(0xFF00D2FF), decoration: TextDecoration.underline), code: GoogleFonts.robotoMono(backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200, fontSize: 12), codeblockDecoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.grey.shade100, borderRadius: BorderRadius.circular(8))), onTapLink: (text, href, title) { if (href != null) launchUrl(Uri.parse(href)); }))),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 26, height: 26, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)]), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 14)), const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100, borderRadius: BorderRadius.circular(14).copyWith(bottomLeft: const Radius.circular(4))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _buildDot(i))), const SizedBox(height: 6), _AnimatedStatusText(isDark: isDark)]))]));
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0.4, end: 1.0), duration: Duration(milliseconds: 400 + (index * 150)), curve: Curves.easeInOut, builder: (context, value, _) => Container(margin: EdgeInsets.only(right: index < 2 ? 4 : 0), width: 6, height: 6, decoration: BoxDecoration(color: const Color(0xFF3A7BD5).withOpacity(value), shape: BoxShape.circle)));
  }
}

class _AnimatedStatusText extends StatefulWidget {
  final bool isDark;
  const _AnimatedStatusText({required this.isDark});
  @override
  State<_AnimatedStatusText> createState() => _AnimatedStatusTextState();
}

class _AnimatedStatusTextState extends State<_AnimatedStatusText> {
  int _currentIndex = 0;
  final List<String> _statusMessages = ["Thinking...", "Analyzing your data...", "Checking TU Dortmund...", "Almost there..."];
  @override
  void initState() { super.initState(); _startCycling(); }
  void _startCycling() { Future.delayed(const Duration(seconds: 2), () { if (mounted) { setState(() { _currentIndex = (_currentIndex + 1) % _statusMessages.length; }); _startCycling(); } }); }
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: Text(_statusMessages[_currentIndex], key: ValueKey<int>(_currentIndex), style: GoogleFonts.inter(fontSize: 11, color: widget.isDark ? Colors.white38 : Colors.grey.shade600, fontStyle: FontStyle.italic)));
}
