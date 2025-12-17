import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../workspace_service.dart';
import '../widgets/glass_container.dart';

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

  Future<void> _uploadFile() async {
    if (_selectedWorkspace == null) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
      if (result != null) {
        final platformFile = result.files.single;
        List<int>? fileBytes = platformFile.bytes;
        if (!kIsWeb && fileBytes == null && platformFile.path != null) { fileBytes = File(platformFile.path!).readAsBytesSync(); }
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
          Padding(
            padding: const EdgeInsets.only(left: 80, top: 24, right: 24, bottom: 24),
            child: Row(
              children: [
                Text("Your Workspaces", style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
                const Spacer(),
                ElevatedButton.icon(onPressed: _createWorkspace, icon: const Icon(Icons.add, size: 20), label: Text("New Workspace", style: GoogleFonts.inter()), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A7BD5), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12))),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A7BD5)))
                : _workspaces.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.folder_open_rounded, size: 80, color: isDark ? Colors.white24 : Colors.black26), const SizedBox(height: 16), Text("No workspaces yet", style: GoogleFonts.inter(fontSize: 18, color: Colors.grey)), const SizedBox(height: 8), Text("Create one to get started!", style: GoogleFonts.inter(color: Colors.grey))]))
                    : Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.2), itemCount: _workspaces.length, itemBuilder: (context, index) { final workspace = _workspaces[index]; return _WorkspaceCard(name: workspace['name'] ?? 'Untitled', onTap: () => _openWorkspace(workspace), onDelete: () => _deleteWorkspace(workspace['id'])); })),
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
          Padding(
            padding: const EdgeInsets.only(left: 80, top: 16, right: 16, bottom: 16),
            child: Row(
              children: [
                Container(decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.black12, borderRadius: BorderRadius.circular(8)), child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black), onPressed: () { _saveNotes(); setState(() => _selectedWorkspace = null); })),
                const SizedBox(width: 16),
                Text(_selectedWorkspace?['name'] ?? 'Workspace', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A7BD5)))
                : Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: GlassContainer(
                          margin: const EdgeInsets.all(8), borderRadius: 16, opacity: isDark ? 0.03 : 0.05, blur: 10,
                          child: Column(children: [
                            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12))), child: Row(children: [Icon(Icons.chat_rounded, color: const Color(0xFF3A7BD5), size: 20), const SizedBox(width: 8), Text("AI Chat", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black))])),
                            Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0), itemBuilder: (context, index) { if (index == _chatMessages.length && _isChatLoading) { return Padding(padding: const EdgeInsets.all(8), child: Row(children: [const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text("Ayla is thinking...", style: GoogleFonts.inter(color: Colors.grey))])); } final msg = _chatMessages[index]; final isUser = msg['role'] == 'user'; return Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.4), decoration: BoxDecoration(color: isUser ? const Color(0xFF3A7BD5).withOpacity(0.12) : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey[100]), borderRadius: BorderRadius.circular(16), border: Border.all(color: isUser ? const Color(0xFF3A7BD5).withOpacity(0.2) : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)))), child: Text(msg['message'] ?? '', style: GoogleFonts.inter(color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87, height: 1.5, fontSize: 14)))); })),
                            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12))), child: Row(children: [Expanded(child: TextField(controller: _chatController, style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black), decoration: InputDecoration(hintText: "Ask Ayla...", hintStyle: GoogleFonts.inter(color: Colors.grey), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)), onSubmitted: (_) => _sendChatMessage())), const SizedBox(width: 8), IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFF3A7BD5)), onPressed: _sendChatMessage)]))
                          ]),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Column(children: [
                          Expanded(
                            child: GlassContainer(
                              margin: const EdgeInsets.all(8), borderRadius: 16, opacity: isDark ? 0.03 : 0.05, blur: 10, 
                              child: Column(children: [
                                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12))), child: Row(children: [Icon(Icons.folder_rounded, color: Colors.amber, size: 20), const SizedBox(width: 8), Text("Files", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)), const Spacer(), TextButton.icon(onPressed: _uploadFile, icon: const Icon(Icons.upload_file, size: 16), label: Text("Upload", style: GoogleFonts.inter(fontSize: 12)))])), 
                                Expanded(child: _files.isEmpty ? Center(child: Text("No files yet", style: GoogleFonts.inter(color: Colors.grey))) : ListView.builder(itemCount: _files.length, itemBuilder: (context, index) { final file = _files[index]; return ListTile(leading: Icon(Icons.insert_drive_file, color: isDark ? Colors.white54 : Colors.black54), title: Text(file['filename'] ?? 'File', style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black)), trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[300]), onPressed: () => _deleteFile(file['id']))); }))
                              ])
                            )
                          ),
                          Expanded(
                            child: GlassContainer(
                              margin: const EdgeInsets.all(8), borderRadius: 16, opacity: isDark ? 0.03 : 0.05, blur: 10, 
                              child: Column(children: [
                                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12))), child: Row(children: [Icon(Icons.edit_note_rounded, color: Colors.blue, size: 20), const SizedBox(width: 8), Text("Notes", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)), const Spacer(), TextButton.icon(onPressed: _saveNotes, icon: const Icon(Icons.save, size: 16), label: Text("Save", style: GoogleFonts.inter(fontSize: 12)))])), 
                                Expanded(child: Padding(padding: const EdgeInsets.all(8), child: TextField(controller: _notesController, maxLines: null, expands: true, style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black), decoration: InputDecoration(hintText: "Write your notes here...\n\nAyla can read these notes and help you!", hintStyle: GoogleFonts.inter(color: Colors.grey), border: InputBorder.none))))
                              ])
                            )
                          ),
                        ]),
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
        decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? Colors.white12 : Colors.black12)),
        child: Stack(
          children: [
            Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.folder_rounded, size: 48, color: Colors.amber), const SizedBox(height: 12), Text(name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)])),
            Positioned(top: 4, right: 4, child: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey), onPressed: onDelete)),
          ],
        ),
      ),
    );
  }
}
