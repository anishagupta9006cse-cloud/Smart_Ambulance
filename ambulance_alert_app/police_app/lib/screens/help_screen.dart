import 'package:flutter/material.dart';
import '../theme.dart';

/// Simple "How to use" page for traffic police.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const List<List<String>> _steps = [
    ['Sign in', 'Type your name and your police post name (example: Station Road Chowk).'],
    ['Set your post location', 'Stand at your post and tap USE MY GPS. Or tap CHOOSE ON MAP and pick the spot. You can also search a saved place.'],
    ['Choose the alert distance', 'Pick how far your area reaches. Use 300 m for a small chowk and 1200 m for a big junction.'],
    ['Start duty', 'Tap START DUTY. Keep the app open and the screen on while you are on duty.'],
    ['When an ambulance is coming', 'The phone speaks, vibrates and shows an orange or red card with the distance and time. The map shows where the ambulance is.'],
    ['Tell the driver', 'Tap I SAW IT, CLEARING THE LANE or NEED HELP. The driver sees your answer on the driver app.'],
    ['After it passes', 'When the ambulance has passed your post, the alert turns off by itself.'],
    ['IoT display and buzzer', 'Tap IOT CONTROL on the map screen. Show a message on the road display, ring the buzzer, or leave AUTO MODE on so it switches itself when an ambulance comes.'],
    ['Finish duty', 'When your shift ends open the menu (three dots) and tap Finish duty.'],
  ];

  static const List<String> _tips = [
    'You only get alerts when the ambulance route passes through your area, and only while it is coming towards you.',
    'Menu > Test sound and voice: checks that your phone volume and voice work.',
    'If the card says "Alert on hold", the ambulance GPS signal is lost or it left the route. Follow your normal duty steps.',
    'The buttons only send a message to the driver. They do not change traffic lights.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = [BtnColors.blue, BtnColors.teal, BtnColors.indigo, BtnColors.olive, BtnColors.orange, BtnColors.red, BtnColors.green, BtnColors.purple, BtnColors.charcoal];
    return Scaffold(
      appBar: AppBar(title: const Text('How to use (Police)')),
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
