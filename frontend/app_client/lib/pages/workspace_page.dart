import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../services/workspace_service.dart';
import '../widgets/glass_container.dart';
import '../services/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';

// Use conditional import for IoHelper
import '../utils/io_helper.dart' if (dart.library.html) '../utils/io_helper_web.dart';

class WorkspacePage extends StatefulWidget {
  final SessionData session;
  final Function(int)? onNavigate;
  final Map<String, dynamic>? initialWorkspace;
  const WorkspacePage({super.key, required this.session, this.onNavigate, this.initialWorkspace});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  List<Map<String, dynamic>> _workspaces = [];
  Map<String, dynamic>? _selectedWorkspace;
  bool _isLoading = true;
  
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  List<Map<String, dynamic>> _chatMessages = [];
  List<Map<String, dynamic>> _files = [];
  bool _isChatLoading = false;
  bool _isRecording = false;
  
  String get _studentId => widget.session.userId ?? widget.session.username;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
    if (widget.initialWorkspace != null) {
      _openWorkspace(widget.initialWorkspace!);
    }
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
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A2E) : Colors.white,
        title: Text("Create Workspace", style: GoogleFonts.inter(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: GoogleFonts.inter(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: "Workspace name (e.g., Math, Research)",
            hintStyle: GoogleFonts.inter(color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF00D2FF), width: 2)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: GoogleFonts.inter(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A7BD5), foregroundColor: Colors.white),
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
    setState(() { _selectedWorkspace = workspace; _isLoading = true; });
    final notes = await WorkspaceService.getNotes(workspace['id']);
    final chats = await WorkspaceService.getChats(workspace['id']);
    final files = await WorkspaceService.getFiles(workspace['id']);
    if (mounted) {
      setState(() { _notesController.text = notes; _chatMessages = chats; _files = files; _isLoading = false; });
    }
  }

  Future<void> _saveNotes() async {
    if (_selectedWorkspace != null) {
      await WorkspaceService.saveNotes(_selectedWorkspace!['id'], _notesController.text, _studentId);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Notes saved!"))); }
    }
  }

  Future<void> _sendChatMessage() async {
    if (_chatController.text.trim().isEmpty || _selectedWorkspace == null) return;
    final message = _chatController.text.trim();
    _chatController.clear();
    setState(() { _chatMessages.add({'role': 'user', 'message': message}); _isChatLoading = true; });
    final response = await WorkspaceService.sendChat(_selectedWorkspace!['id'], _studentId, message, _notesController.text);
    if (mounted) {
      setState(() { _isChatLoading = false; if (response != null) { _chatMessages.add({'role': 'model', 'message': response}); } });
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        final path = await AudioService.stopRecording();
        setState(() => _isRecording = false);
        if (path != null) {
          await _sendAudioMessage(path);
        }
      } else {
        await AudioService.startRecording();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Recording error: $e")));
      }
      setState(() => _isRecording = false);
    }
  }

  Future<void> _sendAudioMessage(String path) async {
    if (_selectedWorkspace == null) return;
    setState(() {
      _chatMessages.add({'role': 'user', 'message': '🎤 Voice Prompt'});
      _isChatLoading = true;
    });

    try {
      final List<int> bytes;
      if (kIsWeb) {
        // On web, path is a blob URL. We need to fetch the bytes.
        final response = await http.get(Uri.parse(path));
        bytes = response.bodyBytes;
      } else {
        bytes = await IoHelper.readAsBytes(path);
      }
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${WorkspaceService.baseUrl}/chat/audio'),
      );
      
      request.fields['user_id'] = _studentId;
      request.fields['workspace_id'] = _selectedWorkspace!['id'];
      
      // Determine file extension and MIME type based on platform
      final String fileName = kIsWeb ? 'voice_prompt.ogg' : 'voice_prompt.m4a';
      final String mimeType = kIsWeb ? 'audio/ogg' : 'audio/mp4';
      
      request.files.add(http.MultipartFile.fromBytes(
        'audio_file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _isChatLoading = false;
            if (data['answer'] != null) {
              _chatMessages.add({'role': 'model', 'message': data['answer']});
            }
          });
        }
      } else {
        throw Exception("Server returned ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChatLoading = false;
          _chatMessages.add({'role': 'model', 'message': "Audio chat failed: ${e.toString()}"});
        });
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedWorkspace == null) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
      if (result != null) {
        final platformFile = result.files.single;
        List<int>? fileBytes = platformFile.bytes;
        if (!kIsWeb && fileBytes == null && platformFile.path != null) { fileBytes = IoHelper.readFileSync(platformFile.path!); }
        if (fileBytes != null) {
          final success = await WorkspaceService.uploadFile(_selectedWorkspace!['id'], fileBytes, platformFile.name, _studentId);
          if (success) {
            final files = await WorkspaceService.getFiles(_selectedWorkspace!['id']);
            setState(() { _files = files; });
            if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("File uploaded successfully!"))); }
          }
        }
      }
    } catch (e) { debugPrint("File pick error: $e"); }
  }

  Future<void> _deleteFile(String fileId) async {
    if (await WorkspaceService.deleteFile(fileId)) {
      if (_selectedWorkspace != null) {
        final files = await WorkspaceService.getFiles(_selectedWorkspace!['id']);
        setState(() { _files = files; });
      }
    }
  }

  Future<void> _deleteWorkspace(String workspaceId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A2E) : Colors.white,
        title: Text("Delete Workspace?", style: GoogleFonts.inter(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
        content: Text("This will delete all notes, files, and chat history.", style: GoogleFonts.inter(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel", style: GoogleFonts.inter(color: Colors.grey))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text("Delete", style: GoogleFonts.inter(color: Colors.white))),
        ],
      ),
    );
    if (confirm == true) { await WorkspaceService.deleteWorkspace(workspaceId); _loadWorkspaces(); }
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_selectedWorkspace != null) return _buildWorkspaceDetail(isDark);
    return _buildWorkspaceList(isDark);
  }

  Widget _buildWorkspaceList(bool isDark) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.only(left: 88, top: 32, right: 32, bottom: 24),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Workspaces",
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Organize your studies and research",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                InkWell(
                  onTap: _createWorkspace,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.add_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7)),
                        const SizedBox(width: 8),
                        Text(
                          "New Workspace",
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
                : _workspaces.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_rounded, size: 64, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                            const SizedBox(height: 24),
                            Text("No workspaces yet", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white38 : Colors.black38)),
                            const SizedBox(height: 8),
                            Text("Create your first one to get started", style: GoogleFonts.inter(color: isDark ? Colors.white.withValues(alpha: 0.24) : Colors.black.withValues(alpha: 0.24))),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4, 
                            crossAxisSpacing: 24, 
                            mainAxisSpacing: 24, 
                            childAspectRatio: 1.1,
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
          // Header
          Container(
            padding: const EdgeInsets.only(left: 88, top: 24, right: 32, bottom: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 20),
                  onPressed: () { _saveNotes(); setState(() => _selectedWorkspace = null); },
                ),
                const SizedBox(width: 16),
                Text(
                  _selectedWorkspace?['name'] ?? 'Workspace', 
                  style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1E293B)),
                ),
                const Spacer(),
                _buildActionButton(Icons.save_rounded, "Save Notes", _saveNotes, isDark),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
                : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Row(
                      children: [
                        // Chat Pane
                        Expanded(
                          flex: 6,
                          child: GlassContainer(
                            borderRadius: 24,
                            child: Column(
                              children: [
                                _buildPaneHeader(Icons.auto_awesome_rounded, "Ayla Chat", Colors.indigoAccent, isDark),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(20),
                                    itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _chatMessages.length && _isChatLoading) {
                                        return _buildTypingIndicator(isDark);
                                      }
                                      final msg = _chatMessages[index];
                                      return _buildChatMessage(msg, isDark);
                                    },
                                  ),
                                ),
                                _buildChatInput(isDark),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        
                        // Right Side Panes
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              // Files Pane
                              Expanded(
                                flex: 4,
                                child: GlassContainer(
                                  borderRadius: 24,
                                  child: Column(
                                    children: [
                                      _buildPaneHeaderWithAction(
                                        Icons.file_copy_rounded, 
                                        "Materials", 
                                        Colors.amber, 
                                        Icons.add_rounded, 
                                        _uploadFile, 
                                        isDark,
                                      ),
                                      Expanded(
                                        child: _files.isEmpty
                                            ? _buildEmptyState(Icons.file_upload_outlined, "No files uploaded", isDark)
                                            : ListView.builder(
                                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                                itemCount: _files.length,
                                                itemBuilder: (context, index) => _buildFileItem(_files[index], isDark),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              // Notes Pane
                              Expanded(
                                flex: 6,
                                child: GlassContainer(
                                  borderRadius: 24,
                                  child: Column(
                                    children: [
                                      _buildPaneHeader(Icons.edit_note_rounded, "Workspace Notes", Colors.tealAccent, isDark),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                          child: TextField(
                                            controller: _notesController,
                                            maxLines: null,
                                            expands: true,
                                            style: GoogleFonts.inter(
                                              fontSize: 14, 
                                              height: 1.6, 
                                              color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: "Synthesize your knowledge here...\n\nAyla will use these notes to provide better context.",
                                              hintStyle: GoogleFonts.inter(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
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
          ),
        ],
      ),
    );
  }

  Widget _buildPaneHeader(IconData icon, String title, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white54 : Colors.black54,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaneHeaderWithAction(IconData icon, String title, Color color, IconData actionIcon, VoidCallback onAction, bool isDark, {String? tooltip}) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white54 : Colors.black54,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: tooltip,
            icon: Icon(actionIcon, size: 18, color: isDark ? Colors.white38 : Colors.black38),
            onPressed: onAction,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessage(Map<String, dynamic> msg, bool isDark) {
    final isUser = msg['role'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.35),
        decoration: BoxDecoration(
          color: isUser 
              ? Colors.indigoAccent.withValues(alpha: isDark ? 0.15 : 0.08) 
              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
          border: Border.all(
            color: isUser 
                ? Colors.indigoAccent.withValues(alpha: 0.2) 
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))
          ),
        ),
        child: Text(
          msg['message'] ?? '',
          style: GoogleFonts.inter(
            color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
            height: 1.6,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildChatInput(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black, fontSize: 14),
              decoration: InputDecoration(
                hintText: _isRecording ? "Listening..." : "Collaborate with Ayla...",
                hintStyle: GoogleFonts.inter(color: isDark ? Colors.white.withValues(alpha: 0.24) : Colors.black.withValues(alpha: 0.24)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                suffixIcon: IconButton(
                  icon: _isRecording ? const _PulseMicIcon() : Icon(Icons.mic_rounded, color: isDark ? Colors.white38 : Colors.black38),
                  onPressed: _toggleRecording,
                ),
              ),
              onSubmitted: (_) => _sendChatMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.send_rounded, color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7), size: 20),
              onPressed: _sendChatMessage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(Map<String, dynamic> file, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_rounded, size: 18, color: isDark ? Colors.white38 : Colors.black38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file['filename'] ?? 'File',
              style: GoogleFonts.inter(color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7), fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent.withValues(alpha: 0.5)),
            onPressed: () => _deleteFile(file['id']),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const SizedBox(
            width: 12, 
            height: 12, 
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)
          ),
          const SizedBox(width: 12),
          Text(
            _isRecording ? "Listening to your voice..." : "Ayla is thinking...", 
            style: GoogleFonts.inter(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Text(message, style: GoogleFonts.inter(color: isDark ? Colors.white.withValues(alpha: 0.24) : Colors.black.withValues(alpha: 0.24), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isDark ? Colors.white38 : Colors.black38),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white38 : Colors.black38),
            ),
          ],
        ),
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
    return GlassContainer(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.folder_rounded, size: 32, color: Colors.amber),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name, 
                    style: GoogleFonts.inter(
                      fontSize: 15, 
                      fontWeight: FontWeight.w700, 
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ), 
                    textAlign: TextAlign.center, 
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12, 
              right: 12, 
              child: IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: isDark ? Colors.white12 : Colors.black12), 
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseMicIcon extends StatefulWidget {
  const _PulseMicIcon();
  @override
  State<_PulseMicIcon> createState() => _PulseMicIconState();
}

class _PulseMicIconState extends State<_PulseMicIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4 * _controller.value), blurRadius: 10 * _controller.value, spreadRadius: 2 * _controller.value)],
        ),
        child: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent, size: 20),
      ),
    );
  }
}

