import 'package:flutter/material.dart';
import '../theme.dart';

/// Simple "How to use" page for the driver.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const List<List<String>> _steps = [
    ['Sign in', 'Type your name and the ambulance number (example: AMB-101). Tap CONTINUE.'],
    ['Allow location', 'When the phone asks for location permission, tap Allow. Keep the phone GPS (Location) turned on.'],
    ['Choose the hospital', 'Tap the box "Where do you want to go?". Type the hospital name, or tap a button like "Hospitals" to see saved hospitals near you.'],
    ['Place not in the list?', 'Tap on the map at the exact spot, then tap "SAVE THIS PLACE FOR NEXT TIME" and type its name. Next time it will be found by search.'],
    ['Check the route', 'The blue line is your route. Orange dots are junctions. They are chosen automatically.'],
    ['Start the trip', 'Tap START EMERGENCY TRIP. The app now sends your location to the police every 2 seconds.'],
    ['Drive', 'Keep the app open and the screen on. You will hear a voice message before each junction. Police posts on your way turn green when they have seen your alert.'],
    ['If you leave the route', 'Tap FIND NEW ROUTE. Police alerts are on hold until you are back on a route.'],
    ['Extra buttons during the trip', 'CRITICAL PATIENT tells police and road displays that it is very urgent. MESSAGE POLICE sends a short message. IOT CONTROL switches the display and buzzer of your ambulance, or of the police posts on your route.'],
    ['Quick start', 'No hospital chosen yet? Tap NEAREST HOSPITAL and the app picks the closest saved hospital and makes the route.'],
    ['Finish', 'When you reach the hospital the trip ends by itself. You can also tap STOP TRIP.'],
  ];

  static const List<String> _tips = [
    'The grey police icons on the map are police posts that are online now. Colored ones are on your route.',
    'Practice mode: before the route starts, turn on "Practice mode". The ambulance moves on the map by itself, so you can test at home.',
    'SEND TEST ALERT: sends a test message to police posts that are online. Use it to check that police can hear and see alerts.',
    'The first connection can take up to 1 minute because the free server sleeps. Please wait.',
    'These alerts help police but do not change traffic lights.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = [BtnColors.blue, BtnColors.teal, BtnColors.indigo, BtnColors.purple, BtnColors.orange, BtnColors.red, BtnColors.green, BtnColors.pink, BtnColors.olive, BtnColors.cyan, BtnColors.charcoal];
    return Scaffold(
      appBar: AppBar(title: const Text('How to use (Driver)')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          for (var i = 0; i < _steps.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: colors[i % colors.length], foregroundColor: Colors.white, child: Text('${i + 1}')),
                title: Text(_steps[i][0], style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(_steps[i][1])),
              ),
            ),
          const SizedBox(height: 8),
          const Text('Good to know', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          for (final t in _tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
              ]),
            ),
          const SizedBox(height: 14),
          FilledButton(style: solidButton(BtnColors.blue), onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
        ],
      ),
    );
  }
}
