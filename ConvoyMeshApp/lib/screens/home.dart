import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/room_service.dart';
import '../services/ble_service.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _joinCtrl = TextEditingController();
  bool _isLeader = false;

  @override
  Widget build(BuildContext context) {
    final room = RoomService();
    return Scaffold(
      appBar: AppBar(title: const Text('Convoy Mesh')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Crea o entra in una stanza', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final code = room.generateCode();
                      if (!mounted) return;
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(roomCode: code, isLeader: _isLeader)));
                    },
                    child: const Text('Crea stanza'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _joinCtrl,
              decoration: const InputDecoration(
                labelText: 'Codice stanza (6 cifre)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(value: _isLeader, onChanged: (v) => setState(()=> _isLeader = v ?? false)),
                const Text('Sono il capofila (facoltativo)'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final code = _joinCtrl.text.trim();
                  if (!room.isValidCode(code)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inserisci 6 cifre')));
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(roomCode: code, isLeader: _isLeader)));
                },
                child: const Text('Entra nella stanza'),
              ),
            ),
            const Spacer(),
            const Divider(),
            const Text('Suggerimenti:'),
            const Text('• Auto: tieni lo schermo acceso e alimentazione collegata.'),
            const Text('• Trekking: attiva la modalità trekking dalla mappa.'),
          ],
        ),
      ),
    );
  }
}
