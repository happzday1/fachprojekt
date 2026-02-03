import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Model for Google Calendar events
class GoogleCalendarEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String? location;
  final String? calendarId;
  final String colorHex;

  GoogleCalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.location,
    this.calendarId,
    this.colorHex = '#4285F4', // Default Google Blue
  });


}

/// Service to manage Google Calendar integration with real OAuth
class GoogleCalendarService {
  static const String _connectionKey = 'google_calendar_connected';
  
  static final GoogleCalendarService _instance = GoogleCalendarService._internal();
  
  factory GoogleCalendarService() => _instance;
  
  GoogleCalendarService._internal();
  
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<GoogleCalendarEvent>> eventsNotifier = ValueNotifier<List<GoogleCalendarEvent>>([]);
  
  bool get isConnected => isConnectedNotifier.value;
  List<GoogleCalendarEvent> get events => eventsNotifier.value;
  
  String? _connectedEmail;
  String? get connectedEmail => _connectedEmail;
  
  /// Initialize the service
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isConnectedNotifier.value = prefs.getBool(_connectionKey) ?? false;
      // TODO: In backend implementation, we will verify this status with the server
    } catch (e) {
      debugPrint('Error initializing Google Calendar service: $e');
      isConnectedNotifier.value = false;
    }
  }
  
  /// Connect to Google Calendar
  /// This will eventually trigger the backend OAuth flow
  Future<bool> connect() async {
    debugPrint('Frontend Connect triggered - TODO: Implement backend OAuth redirect');
    // For now, we just simulate a connection failure or show a dialog saying implementation pending
    return false;
  }
  
  /// Disconnect from Google Calendar
  Future<bool> disconnect() async {
    isConnectedNotifier.value = false;
    eventsNotifier.value = [];
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_connectionKey, false);
    
    return true;
  }
  
  /// Toggle connection state
  Future<bool> toggleConnection() async {
    if (isConnected) {
      return await disconnect();
    } else {
      return await connect();
    }
  }
  
  /// Refresh events - Placeholder for backend fetch
  Future<void> refreshEvents() async {
    if (isConnected) {
      debugPrint('Fetching events from backend...');
      // TODO: Call backend API to get events
    }
  }
  
  /// Get events for a specific date
  List<GoogleCalendarEvent> getEventsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    return eventsNotifier.value.where((event) {
      if (event.isAllDay) {
        return event.startTime.isBefore(endOfDay) && 
               event.endTime.isAfter(startOfDay);
      }
      return event.startTime.isAfter(startOfDay) && 
             event.startTime.isBefore(endOfDay);
    }).toList();
  }
}
