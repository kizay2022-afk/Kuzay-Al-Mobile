import 'package:flutter/material.dart';

void main() => runApp(const KuzayApp());

class KuzayApp extends StatelessWidget {
  const KuzayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kuzay AI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090909),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6A00),
          secondary: Color(0xFFFF8A30),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final input = TextEditingController();
  final messages = <String>[];

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      messages.add('Вы: $text');
      messages.add('Kuzay AI: Настройте API-ключ в разделе настроек.');
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kuzay AI',
          style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              child: Text('KUZAY AI',
                style: TextStyle(fontSize: 28, color: Color(0xFFFF6A00))),
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('New Chat'),
              onTap: () => Navigator.pop(context),
            ),
            const ListTile(
              leading: Icon(Icons.compare_arrows),
              title: Text('Compare AI'),
            ),
            const ListTile(
              leading: Icon(Icons.dashboard),
              title: Text('Workspace'),
            ),
            const ListTile(
              leading: Icon(Icons.brush),
              title: Text('AI Designer'),
            ),
            const ListTile(
              leading: Icon(Icons.extension),
              title: Text('Plugins'),
            ),
            const ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                        size: 64, color: Color(0xFFFF6A00)),
                      SizedBox(height: 12),
                      Text('Чем займёмся?',
                        style: TextStyle(fontSize: 24,
                          fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(messages[i]),
                    ),
                  ),
                ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Напишите сообщение...',
                        filled: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: send,
                    icon: const Icon(Icons.send,
                      color: Color(0xFFFF6A00)),
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
