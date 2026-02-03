import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
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

  /// Create from Google Calendar API Event
  factory GoogleCalendarEvent.fromGoogleEvent(gcal.Event event) {
    // Handle all-day events vs timed events
    final isAllDay = event.start?.date != null;
    
    DateTime startTime;
    DateTime endTime;
    
    if (isAllDay) {
      startTime = event.start?.date ?? DateTime.now();
      endTime = event.end?.date ?? startTime.add(const Duration(days: 1));
    } else {
      startTime = event.start?.dateTime?.toLocal() ?? DateTime.now();
      endTime = event.end?.dateTime?.toLocal() ?? startTime.add(const Duration(hours: 1));
    }

    return GoogleCalendarEvent(
      id: event.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: event.summary ?? 'Untitled Event',
      description: event.description,
      startTime: startTime,
      endTime: endTime,
      isAllDay: isAllDay,
      location: event.location,
      colorHex: _getColorFromColorId(event.colorId),
    );
  }

  /// Map Google Calendar color IDs to hex colors
  static String _getColorFromColorId(String? colorId) {
    const colorMap = {
      '1': '#7986CB', // Lavender
      '2': '#33B679', // Sage
      '3': '#8E24AA', // Grape
      '4': '#E67C73', // Flamingo
      '5': '#F6BF26', // Banana
      '6': '#F4511E', // Tangerine
      '7': '#039BE5', // Peacock
      '8': '#616161', // Graphite
      '9': '#3F51B5', // Blueberry
      '10': '#0B8043', // Basil
      '11': '#D50000', // Tomato
    };
    return colorMap[colorId] ?? '#4285F4'; // Default Google Blue
  }
}

/// Service to manage Google Calendar integration with real OAuth
class GoogleCalendarService {
  static const String _connectionKey = 'google_calendar_connected';
  static const String _emailKey = 'google_calendar_email';
  
  static final GoogleCalendarService _instance = GoogleCalendarService._internal();
  
  factory GoogleCalendarService() => _instance;
  
  GoogleCalendarService._internal();
  
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<GoogleCalendarEvent>> eventsNotifier = ValueNotifier<List<GoogleCalendarEvent>>([]);
  
  bool get isConnected => isConnectedNotifier.value;
  List<GoogleCalendarEvent> get events => eventsNotifier.value;
  
  String? _connectedEmail;
  String? get connectedEmail => _connectedEmail;
  
  GoogleSignInAccount? _currentUser;
  gcal.CalendarApi? _calendarApi;
  
  // Google Sign-In configuration with Calendar scope
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      gcal.CalendarApi.calendarReadonlyScope,
    ],
  );
  
  /// Initialize the service and try silent sign-in
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _connectedEmail = prefs.getString(_emailKey);
      
      // Listen for sign-in changes
      _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
        _handleSignInChange(account);
      });
      
      // Try silent sign-in
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        await _handleSignInChange(account);
      } else {
        // Fallback to saved state
        isConnectedNotifier.value = prefs.getBool(_connectionKey) ?? false;
      }
    } catch (e) {
      debugPrint('Error initializing Google Calendar service: $e');
      isConnectedNotifier.value = false;
    }
  }
  
  /// Handle sign-in state changes
  Future<void> _handleSignInChange(GoogleSignInAccount? account) async {
    _currentUser = account;
    
    if (account != null) {
      try {
        // Get authenticated HTTP client
        final httpClient = await _googleSignIn.authenticatedClient();
        
        if (httpClient != null) {
          _calendarApi = gcal.CalendarApi(httpClient);
          isConnectedNotifier.value = true;
          _connectedEmail = account.email;
          
          // Save state
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_connectionKey, true);
          await prefs.setString(_emailKey, account.email);
          
          // Fetch events
          await fetchEvents();
        }
      } catch (e) {
        debugPrint('Error setting up Calendar API: $e');
        isConnectedNotifier.value = false;
      }
    } else {
      _calendarApi = null;
      isConnectedNotifier.value = false;
      eventsNotifier.value = [];
    }
  }
  
  /// Connect to Google Calendar - triggers OAuth flow
  Future<bool> connect() async {
    try {
      final account = await _googleSignIn.signIn();
      
      if (account != null) {
        await _handleSignInChange(account);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error connecting to Google Calendar: $e');
      return false;
    }
  }
  
  /// Disconnect from Google Calendar
  Future<bool> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      
      _currentUser = null;
      _calendarApi = null;
      _connectedEmail = null;
      isConnectedNotifier.value = false;
      eventsNotifier.value = [];
      
      // Clear saved state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_connectionKey, false);
      await prefs.remove(_emailKey);
      
      return true;
    } catch (e) {
      debugPrint('Error disconnecting from Google Calendar: $e');
      return false;
    }
  }
  
  /// Toggle connection state
  Future<bool> toggleConnection() async {
    if (isConnected) {
      return await disconnect();
    } else {
      return await connect();
    }
  }
  
  /// Fetch calendar events for the next 90 days from ALL selected calendars
  Future<List<GoogleCalendarEvent>> fetchEvents({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (_calendarApi == null) {
      debugPrint('Calendar API not initialized');
      return [];
    }
    
    try {
      final now = startDate ?? DateTime.now();
      final ninetyDaysFromNow = endDate ?? now.add(const Duration(days: 90));
      
      // 1. Get list of all user's calendars
      final calendarList = await _calendarApi!.calendarList.list();
      final allCalendars = calendarList.items ?? [];
      
      final allEvents = <GoogleCalendarEvent>[];
      
      debugPrint('Found ${allCalendars.length} calendars. Fetching events...');

      // 2. Fetch events from each selected calendar
      for (final calendar in allCalendars) {
        // Only fetch from selected calendars (visible in Google Calendar UI)
        if (calendar.selected != true && calendar.primary != true) continue;
        
        try {
          final events = await _calendarApi!.events.list(
            calendar.id!,
            timeMin: now.toUtc(),
            timeMax: ninetyDaysFromNow.toUtc(),
            singleEvents: true,
            orderBy: 'startTime',
            maxResults: 50,
          );
          
          if (events.items != null) {
            for (final event in events.items!) {
              // Skip events without a start time
              if (event.start == null) continue;
              // Skip declined events
              if (event.status == 'cancelled') continue;
              
              allEvents.add(GoogleCalendarEvent.fromGoogleEvent(event));
            }
          }
        } catch (e) {
          debugPrint('Error fetching events for calendar ${calendar.summary}: $e');
          // Continue to next calendar even if one fails
        }
      }
      
      // Sort all combined events by time
      allEvents.sort((a, b) => a.startTime.compareTo(b.startTime));
      
      eventsNotifier.value = allEvents;
      debugPrint('Fetched total of ${allEvents.length} events from ${allCalendars.length} calendars');
      return allEvents;
    } catch (e) {
      debugPrint('Error fetching Google Calendar events: $e');
      return [];
    }
  }
  
  /// Get events for a specific date
  List<GoogleCalendarEvent> getEventsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    return eventsNotifier.value.where((event) {
      // For all-day events, check if the date falls within the range
      if (event.isAllDay) {
        return event.startTime.isBefore(endOfDay) && 
               event.endTime.isAfter(startOfDay);
      }
      // For timed events, check if start time is on this day
      return event.startTime.isAfter(startOfDay) && 
             event.startTime.isBefore(endOfDay);
    }).toList();
  }
  
  /// Refresh events
  Future<void> refreshEvents() async {
    if (isConnected) {
      await fetchEvents();
    }
  }
}
