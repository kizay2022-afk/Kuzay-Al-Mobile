import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'github_project.dart';
import 'self_editor_engine.dart';
import 'self_editor_locator.dart';

const orange = Color(0xFFFF6A00);
const black = Color(0xFF090909);
const panel = Color(0xFF151515);
final ValueNotifier<String> kuzayFont = ValueNotifier<String>('sans-serif');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await SharedPreferences.getInstance();
  kuzayFont.value = p.getString('app_font') ?? 'sans-serif';
  runApp(const KuzayApp());
}

class KuzayApp extends StatelessWidget {
  const KuzayApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: kuzayFont,
    builder: (context, font, _) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Kuzay AI',
    theme: ThemeData(
      brightness: Brightness.dark,
      fontFamily: font,
      scaffoldBackgroundColor: black,
      colorScheme: const ColorScheme.dark(primary: orange, secondary: Color(0xFFFF8A30)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: orange)),
      ),
      cardTheme: CardTheme(color: panel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      appBarTheme: const AppBarTheme(backgroundColor: black, elevation: 0),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: orange, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(50)),
      ),
    ),
    home: const HomePage(),
  ));
}

class Store {
  static const secure = FlutterSecureStorage();
  static const providers = ['OpenAI', 'Gemini', 'Grok', 'Custom'];

  static String defaultModel(String p) {
    if (p == 'Gemini') return 'gemini-2.5-flash';
    if (p == 'Grok') return 'grok-3-mini';
    return 'gpt-4o-mini';
  }

  static String defaultUrl(String p) {
    if (p == 'Grok') return 'https://api.x.ai/v1/chat/completions';
    return 'https://api.openai.com/v1/chat/completions';
  }

  static Future<String> getKey(String provider) async => await secure.read(key: 'api_$provider') ?? '';
  static Future<void> setKey(String provider, String value) async => secure.write(key: 'api_$provider', value: value);

  static Future<String> getProvider() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('provider') ?? 'OpenAI';
  }
  static Future<String> getModel() async {
    final p = await SharedPreferences.getInstance();
    final provider = p.getString('provider') ?? 'OpenAI';
    return p.getString('model_$provider') ?? defaultModel(provider);
  }
  static Future<String> getUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('url_Custom') ?? defaultUrl('Custom');
  }
}

class AiService {
  static Future<String> ask({
    required String provider,
    required String model,
    required String prompt,
    String? system,
  }) async {
    final key = await Store.getKey(provider);
    if (key.trim().isEmpty) throw Exception('Для $provider не задан API-ключ. Откройте Settings.');
    if (provider == 'Gemini') return _gemini(key, model, prompt, system);
    final url = provider == 'Custom' ? await Store.getUrl() : Store.defaultUrl(provider);
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
      body: jsonEncode({
        'model': model,
        'messages': [
          if (system != null && system.isNotEmpty) {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt}
        ],
      }),
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ' + response.statusCode.toString() + ': ' + _short(response.body));
    }
    final data = jsonDecode(response.body);
    final value = data['choices']?[0]?['message']?['content'];
    if (value == null) throw Exception('Провайдер вернул неожиданный ответ.');
    return value.toString();
  }

  static Future<String> _gemini(String key, String model, String prompt, String? system) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key');
    final parts = <Map<String, String>>[];
    parts.add({'text': system != null && system.isNotEmpty ? system + '\n\n' + prompt : prompt});
    final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'contents': [{'parts': parts}]})).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Gemini HTTP ' + response.statusCode.toString() + ': ' + _short(response.body));
    }
    final data = jsonDecode(response.body);
    final value = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
    if (value == null) throw Exception('Gemini вернул неожиданный ответ.');
    return value.toString();
  }

  static String _short(String body) => body.length > 500 ? body.substring(0, 500) + '…' : body;
}

class ChatMessage {
  final String role;
  final String text;
  final String provider;
  const ChatMessage(this.role, this.text, this.provider);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[];
  String provider = 'OpenAI';
  String model = 'gpt-4o-mini';
  bool sending = false;
  bool listening = false;
  final stt.SpeechToText speech = stt.SpeechToText();
  String? attachedName;
  String? attachedText;

  @override void initState() { super.initState(); _loadSettings(); }

  Future<void> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      String? text;
      if (bytes != null && bytes.length <= 300000) {
        try { text = utf8.decode(bytes); } catch (_) {}
      }
      if (!mounted) return;
      setState(() { attachedName = file.name; attachedText = text; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл прикреплён: ' + file.name)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось открыть файл: ' + e.toString())));
    }
  }

  Future<void> toggleVoice() async {
    if (listening) { await speech.stop(); if (mounted) setState(() => listening = false); return; }
    final available = await speech.initialize(onStatus: (status) { if (status == 'done' && mounted) setState(() => listening = false); });
    if (!available) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Голосовой ввод недоступен на этом устройстве.'))); return; }
    if (mounted) setState(() => listening = true);
    await speech.listen(onResult: (result) { if (!mounted) return; setState(() => input.text = result.recognizedWords); });
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final selected = p.getString('provider') ?? 'OpenAI';
    if (!mounted) return;
    setState(() { provider = selected; model = p.getString('model_$selected') ?? Store.defaultModel(selected); });
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    final prompt = attachedText == null ? text : text + '\n\n[Прикреплённый файл: ' + attachedName! + ']\n' + attachedText!;
    input.clear();
    setState(() { messages.add(ChatMessage('user', text + (attachedName == null ? '' : '\n📎 ' + attachedName!), provider)); sending = true; });
    try {
      final answer = await AiService.ask(provider: provider, model: model, prompt: prompt);
      if (mounted) setState(() => messages.add(ChatMessage('assistant', answer, provider)));
    } catch (e) {
      if (mounted) setState(() => messages.add(ChatMessage('assistant', 'Ошибка: ' + e.toString(), provider)));
    } finally {
      if (mounted) {
        setState(() { sending = false; attachedName = null; attachedText = null; });
        await Future.delayed(const Duration(milliseconds: 50));
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    await _loadSettings();
  }

  void newChat() => setState(() => messages.clear());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(children: [Icon(Icons.pets, color: Colors.white), SizedBox(width: 8), Text('Kuzay AI', style: TextStyle(fontWeight: FontWeight.bold))]),
      actions: [IconButton(onPressed: () => open(const SettingsPage()), icon: const Icon(Icons.settings))],
    ),
    drawer: Drawer(
      backgroundColor: const Color(0xFF101010),
      child: ListView(children: [
        const DrawerHeader(decoration: BoxDecoration(color: Color(0xFF0D0D0D)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.pets, size: 48, color: Colors.white), SizedBox(height: 10),
          Text('KUZAY AI', style: TextStyle(fontSize: 26, color: orange, fontWeight: FontWeight.bold)),
          Text('AI workspace', style: TextStyle(color: Colors.white54)),
        ])),
        _nav(Icons.chat, 'New Chat', () { Navigator.pop(context); newChat(); }),
        _nav(Icons.compare_arrows, 'Compare AI', () { Navigator.pop(context); open(const ComparePage()); }),
        _nav(Icons.dashboard, 'Workspace', () { Navigator.pop(context); open(const WorkspacePage()); }),
        _nav(Icons.brush, 'AI Designer', () { Navigator.pop(context); open(const DesignerPage()); }),
        _nav(Icons.extension, 'Plugins', () { Navigator.pop(context); open(const PluginsPage()); }),
        _nav(Icons.build, 'Self Editor', () { Navigator.pop(context); open(const SelfEditorPage()); }),
        _nav(Icons.settings, 'Settings', () { Navigator.pop(context); open(const SettingsPage()); }),
      ]),
    ),
    body: Column(children: [
      Expanded(
        child: messages.isEmpty
          ? Center(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.pets, size: 82, color: Colors.white),
              const SizedBox(height: 16),
              const Text('Чем займёмся?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(provider + ' • ' + model, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: () => open(const SettingsPage()), icon: const Icon(Icons.key), label: const Text('Настроить ИИ')),
            ])))
          : ListView.builder(
              controller: scroll, padding: const EdgeInsets.all(12), itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[i]; final user = m.role == 'user';
                return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: Container(
                  constraints: const BoxConstraints(maxWidth: 360), margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: user ? const Color(0xFF3B1D0B) : panel, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user ? 'Вы' : m.provider, style: TextStyle(color: user ? orange : Colors.white54, fontSize: 12)),
                    const SizedBox(height: 5), SelectableText(m.text),
                    if (!user) Align(alignment: Alignment.centerRight, child: IconButton(icon: const Icon(Icons.copy, size: 17, color: Colors.white54), onPressed: () => Clipboard.setData(ClipboardData(text: m.text)))),
                  ]),
                ));
              },
            ),
      ),
      if (attachedName != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Align(alignment: Alignment.centerLeft, child: InputChip(label: Text('📎 ' + attachedName!), onDeleted: () => setState(() { attachedName = null; attachedText = null; })))),
      SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(6, 4, 6, 10), child: Row(children: [
        IconButton(tooltip:'Файл', onPressed: sending ? null : pickFile, icon: const Icon(Icons.attach_file, color: Colors.white70)),
        IconButton(tooltip:'Голос', onPressed: sending ? null : toggleVoice, icon: Icon(listening ? Icons.stop_circle : Icons.mic, color: listening ? orange : Colors.white70)),
        Expanded(child: TextField(controller: input, maxLines: 4, minLines: 1, decoration: const InputDecoration(hintText: 'Напишите сообщение…'))),
        const SizedBox(width: 4),
        IconButton(onPressed: sending ? null : send, icon: sending ? const SizedBox(width: 23, height: 23, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, color: orange)),
      ]))),
    ]),
  );

  Widget _nav(IconData icon, String title, VoidCallback action) => ListTile(leading: Icon(icon), title: Text(title), onTap: action);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String provider = 'OpenAI';
  final keyController = TextEditingController();
  final modelController = TextEditingController();
  final urlController = TextEditingController();
  bool obscure = true;
  bool testing = false;

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final selected = p.getString('provider') ?? 'OpenAI';
    final key = await Store.getKey(selected);
    if (!mounted) return;
    setState(() {
      provider = selected; keyController.text = key;
      modelController.text = p.getString('model_$selected') ?? Store.defaultModel(selected);
      urlController.text = p.getString('url_Custom') ?? Store.defaultUrl('Custom');
    });
  }

  Future<void> selectProvider(String value) async {
    await save(showMessage: false);
    final p = await SharedPreferences.getInstance();
    final key = await Store.getKey(value);
    setState(() {
      provider = value; keyController.text = key;
      modelController.text = p.getString('model_$value') ?? Store.defaultModel(value);
    });
  }

  Future<void> save({bool showMessage = true}) async {
    final p = await SharedPreferences.getInstance();
    await Store.setKey(provider, keyController.text.trim());
    await p.setString('provider', provider);
    await p.setString('model_$provider', modelController.text.trim());
    await p.setString('url_Custom', urlController.text.trim());
    if (showMessage && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
  }

  Future<void> test() async {
    await save(showMessage: false); setState(() => testing = true);
    try {
      final result = await AiService.ask(provider: provider, model: modelController.text.trim(), prompt: 'Ответь одним словом: OK');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Соединение работает: ' + result.trim())));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка соединения: ' + e.toString())));
    } finally { if (mounted) setState(() => testing = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Провайдер ИИ', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: provider, decoration: const InputDecoration(labelText: 'Provider'),
        items: Store.providers.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
        onChanged: (v) { if (v != null) selectProvider(v); },
      ),
      const SizedBox(height: 14), TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Model')),
      const SizedBox(height: 14),
      TextField(controller: keyController, obscureText: obscure, decoration: InputDecoration(labelText: 'API key', suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)))),
      if (provider == 'Custom') ...[const SizedBox(height: 14), TextField(controller: urlController, decoration: const InputDecoration(labelText: 'Chat Completions URL'))],
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: ElevatedButton.icon(onPressed: testing ? null : save, icon: const Icon(Icons.save), label: const Text('Сохранить'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: testing ? null : test, icon: testing ? const SizedBox(width: 18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.wifi_tethering), label: const Text('Проверить'))),
      ]),
      const SizedBox(height: 24),
      const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('API-ключи сохраняются локально в защищённом хранилище Android. Kuzay AI не имеет собственного сервера для передачи ключей.', style: TextStyle(color: Colors.white70)))),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SelfEditorPage())),icon:const Icon(Icons.build),label:const Text('Саморедактор приложения')),
      const SizedBox(height: 16),
      const Text('Примеры моделей', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('OpenAI: gpt-4o-mini\nGemini: gemini-2.5-flash\nGrok: модель, доступная вашему xAI API-аккаунту\nCustom: URL совместимого /chat/completions API'),
    ]),
  );
}

class ComparePage extends StatefulWidget {
  const ComparePage({super.key});
  @override State<ComparePage> createState() => _ComparePageState();
}
class _ComparePageState extends State<ComparePage> {
  final input = TextEditingController();
  final results = <String, String>{};
  bool busy = false;

  Future<void> compare() async {
    final prompt = input.text.trim();
    if (prompt.isEmpty || busy) return;
    setState(() { busy = true; results.clear(); });
    final p = await SharedPreferences.getInstance();
    final names = ['OpenAI', 'Gemini', 'Grok'];
    final providers = <String>[];
    for (final name in names) { if ((await Store.getKey(name)).isNotEmpty) providers.add(name); }
    if (providers.isEmpty) {
      if (mounted) setState(() { busy = false; results['Kuzay'] = 'Добавьте хотя бы один API-ключ в Settings.'; });
      return;
    }
    final futures = <Future<MapEntry<String,String>>>[];
    for (final name in providers) {
      final model = p.getString('model_$name') ?? Store.defaultModel(name);
      futures.add(AiService.ask(provider:name, model:model, prompt:prompt).then((v)=>MapEntry(name,v), onError:(e)=>MapEntry(name,'Ошибка: '+e.toString())));
    }
    final data = await Future.wait(futures);
    if (mounted) setState(() { for (final x in data) results[x.key] = x.value; busy = false; });
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Compare AI')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller:input,maxLines:4,decoration:const InputDecoration(labelText:'Один запрос для нескольких ИИ'))),
      Padding(padding: const EdgeInsets.symmetric(horizontal:16), child: SizedBox(width:double.infinity,child:ElevatedButton.icon(onPressed:busy?null:compare,icon:const Icon(Icons.compare_arrows),label:const Text('Сравнить')))),
      Expanded(child: ListView(padding:const EdgeInsets.all(16),children:results.entries.map((e)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(e.key,style:const TextStyle(color:orange,fontWeight:FontWeight.bold)),const SizedBox(height:8),SelectableText(e.value)])))).toList())),
    ]),
  );
}

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});
  @override State<WorkspacePage> createState()=>_WorkspacePageState();
}
class _WorkspacePageState extends State<WorkspacePage> {
  int tab=0;
  final code=TextEditingController(text:'// Kuzay Workspace\n\nvoid main() {\n  print("Hello from Kuzay");\n}');
  final notes=TextEditingController();
  final files=<String>[];
  String? selectedFile;
  String filePreview='';
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async { final p=await SharedPreferences.getInstance(); notes.text=p.getString('workspace_notes')??''; if(mounted)setState((){}); }
  Future<void> addFile() async {
    try {
      final r=await FilePicker.platform.pickFiles(withData:true,allowMultiple:true);
      if(r==null)return;
      setState(() {
        for(final f in r.files) { if(!files.contains(f.name)) files.add(f.name); }
        if(r.files.isNotEmpty) {
          selectedFile=r.files.first.name;
          final b=r.files.first.bytes;
          if(b!=null && b.length<=300000) { try { filePreview=utf8.decode(b); } catch(_) { filePreview='Бинарный файл: '+r.files.first.name; } }
          else { filePreview='Файл выбран: '+r.files.first.name+' (содержимое не отображается)'; }
        }
      });
    } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Ошибка файла: '+e.toString()))); }
  }
  Future<void> saveNotes() async {
    final p=await SharedPreferences.getInstance(); await p.setString('workspace_notes',notes.text);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Заметки сохранены')));
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Workspace'),actions:[IconButton(onPressed:saveNotes,icon:const Icon(Icons.save))]),
    body:Column(children:[
      SizedBox(height:58,child:Row(children:[_tab(0,'Chat',Icons.chat),_tab(1,'Code',Icons.code),_tab(2,'Files',Icons.folder),_tab(3,'Notes',Icons.notes)])),
      Expanded(child:Padding(padding:const EdgeInsets.all(12),child:
        tab==0 ? Column(children:[
          const Expanded(child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.auto_awesome,size:48,color:orange),SizedBox(height:12),Text('Workspace AI'),SizedBox(height:6),Text('Попросите изменить интерфейс, найти блок или открыть исходный код.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white54))]))),
          ElevatedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SelfEditorPage())),icon:const Icon(Icons.build),label:const Text('Открыть саморедактор')),
          const SizedBox(height:8),
          OutlinedButton.icon(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.chat),label:const Text('Открыть основной AI-чат'))
        ]) :
        tab==1 ? Column(children:[
          Expanded(child:TextField(controller:code,maxLines:null,expands:true,style:const TextStyle(fontFamily:'monospace'),decoration:const InputDecoration(labelText:'Редактор кода'))),
          const SizedBox(height:8),
          Row(children:[
            Expanded(child:OutlinedButton.icon(onPressed:()=>Clipboard.setData(ClipboardData(text:code.text)),icon:const Icon(Icons.copy),label:const Text('Копировать'))),
            const SizedBox(width:8),
            Expanded(child:ElevatedButton.icon(onPressed:()=>showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Выполнение кода'),content:const Text('Произвольный код внутри приложения не выполняется из соображений безопасности.'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK'))])),icon:const Icon(Icons.play_arrow),label:const Text('Запустить')))
          ])
        ]) :
        tab==2 ? Column(children:[
          Row(children:[Expanded(child:Text(files.length.toString()+' файлов',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(onPressed:addFile,icon:const Icon(Icons.add_circle,color:orange))]),
          Expanded(child:files.isEmpty ? const Center(child:Text('Добавьте файлы проекта')) : ListView(children:files.map((name)=>ListTile(selected:name==selectedFile,leading:const Icon(Icons.insert_drive_file),title:Text(name),onTap:()=>setState(()=>selectedFile=name))).toList())),
          if(selectedFile!=null) SizedBox(height:150,child:SingleChildScrollView(child:Text(filePreview)))
        ]) :
        Column(children:[Expanded(child:TextField(controller:notes,maxLines:null,expands:true,decoration:const InputDecoration(labelText:'Заметки проекта'))),const SizedBox(height:8),ElevatedButton.icon(onPressed:saveNotes,icon:const Icon(Icons.save),label:const Text('Сохранить заметки'))]
      ))),
    ]),
  );
  Widget _tab(int n,String title,IconData icon)=>Expanded(child:TextButton(onPressed:()=>setState(()=>tab=n),child:Column(children:[Icon(icon,size:21,color:tab==n?orange:Colors.white54),Text(title,style:TextStyle(fontSize:11,color:tab==n?orange:Colors.white54))])));
}

class DesignerPage extends StatefulWidget {
  const DesignerPage({super.key});
  @override State<DesignerPage> createState()=>_DesignerPageState();
}
class _DesignerPageState extends State<DesignerPage> {
  final prompt=TextEditingController();
  String style='Dark';
  String preview='Ваш интерфейс появится здесь';
  bool busy=false;

  Future<void> generate() async {
    if(prompt.text.trim().isEmpty)return;
    setState(()=>busy=true);
    try {
      final provider=await Store.getProvider(); final model=await Store.getModel(); final key=await Store.getKey(provider);
      if(key.isEmpty) { preview='Добавьте API-ключ в Settings, чтобы Designer использовал ИИ.'; }
      else { preview=await AiService.ask(provider:provider,model:model,prompt:'Ты AI Designer. Для запроса "' + prompt.text.trim() + '" создай краткое описание мобильного интерфейса в стиле ' + style + ': экраны, элементы, навигация и внешний вид. Не пиши код.'); }
    } catch(e) { preview='Ошибка: ' + e.toString(); }
    if(mounted)setState(()=>busy=false);
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('AI Designer')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      TextField(controller:prompt,maxLines:4,decoration:const InputDecoration(labelText:'Что создать?',hintText:'Например: приложение магазина игр')),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:style,items:['Dark','Light','Orange','Minimal'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>style=v!),decoration:const InputDecoration(labelText:'Стиль')),
      const SizedBox(height:12),
      ElevatedButton.icon(onPressed:busy?null:generate,icon:const Icon(Icons.auto_awesome),label:Text(busy?'Создание…':'Создать')),
      const SizedBox(height:18),
      Card(child:Padding(padding:const EdgeInsets.all(18),child:SelectableText(preview,style:const TextStyle(fontSize:16)))),
    ]),
  );
}


class SelfEditorPage extends StatefulWidget {
  const SelfEditorPage({super.key});
  @override State<SelfEditorPage> createState()=>_SelfEditorPageState();
}

class _SelfEditorPageState extends State<SelfEditorPage>{
  final command=TextEditingController(), token=TextEditingController();
  int tab=0;
  bool busy=false,loaded=false;
  String filePath='lib/main.dart', source='', sha='', status='Готов';
  String? find,replace,summary,patchFile;
  int? highlightStart,highlightEnd;
  String buildStatus='';
  String buildUrl='';
  Timer? buildTimer;
  final files=SelfEditorEngine.allowedFiles;
  final blockList=const ['Шрифт приложения','Цветовая тема','Навигация','Настройки ИИ','Чат','Workspace','AI Designer','Саморедактор','Плагины'];

  @override void initState(){super.initState();GitHubProject.token().then((v){token.text=v;});}

  Future<void> load([String? path])async{
    final target=path??filePath;
    setState(()=>busy=true);
    try{
      final d=await SelfEditorEngine.load(target);
      setState((){filePath=target;source=d['content']!;sha=d['sha']!;loaded=true;find=null;replace=null;status='Загружен $target';tab=1;});
    }catch(e){setState(()=>status='Ошибка: '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> prepare()async{
    final q=command.text.trim();
    if(q.isEmpty||busy)return;
    setState(()=>busy=true);
    try{
      if(!loaded){final d=await SelfEditorEngine.load(filePath);source=d['content']!;sha=d['sha']!;loaded=true;}
      final p=await Store.getProvider(),m=await Store.getModel();
      final selected=find;
      final context=selected==null?source:'ВЫБРАННЫЙ БЛОК:\n'+selected+'\n\nПОЛНЫЙ ИСХОДНИК ДЛЯ КОНТЕКСТА:\n'+source;
      final a=await AiService.ask(provider:p,model:m,prompt:'Ты безопасный редактор Flutter проекта. Верни только JSON: {"action":"patch","file":"путь","summary":"описание","find":"точный фрагмент","replace":"новый фрагмент"} или {"action":"unsupported","summary":"причина"}. file должен быть одним из: '+SelfEditorEngine.allowedFiles.join(', ')+'. find должен существовать в выбранном исходнике ровно один раз. Если выбран блок, изменяй прежде всего его. Только небольшой patch. Не удаляй безопасность, API key storage или проверки. Не добавляй произвольное выполнение кода. Запрос: '+q+'\nТЕКУЩИЙ ФАЙЛ: '+filePath+'\n'+context);
      final patch=SelfEditorEngine.parsePatch(a,filePath);
      String patchSource=source;
      String patchSha=sha;
      if(patch.filePath!=filePath){
        final d=await SelfEditorEngine.load(patch.filePath);
        patchSource=d['content']!;patchSha=d['sha']!;
      }
      SelfEditorEngine.apply(patchSource,patch);
      final loc=SelfEditorLocator.locate(patchSource,patch.find);
      setState((){patchFile=patch.filePath;find=patch.find;replace=patch.replace;summary=patch.summary;highlightStart=loc?.startLine;highlightEnd=loc?.endLine;status='Patch готов для '+patch.filePath+'. Строки '+(loc?.startLine.toString()??'?')+'–'+(loc?.endLine.toString()??'?')+'. Проверь Diff.';tab=2;});
      if(patch.filePath!=filePath){filePath=patch.filePath;source=patchSource;sha=patchSha;loaded=true;}
    }catch(e){setState(()=>status='Ошибка AI: '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> apply()async{
    if(find==null||replace==null||busy)return;
    setState(()=>busy=true);
    try{
      final target=patchFile??filePath;
      final d=await SelfEditorEngine.load(target);
      final current=d['content']!;
      final currentSha=d['sha']!;
      final patch=SelfPatch(filePath:target,summary:summary??'Изменение',find:find!,replace:replace!);
      final updated=SelfEditorEngine.apply(current,patch);
      final commit=await GitHubProject.updateFile(filePath:target,content:updated,sha:currentSha,message:'Kuzay AI Self Editor: '+(summary??'patch'));
      setState((){filePath=target;source=updated;sha=currentSha;find=null;replace=null;patchFile=null;highlightStart=null;highlightEnd=null;buildStatus='queued';buildUrl='';status='Изменение применено. Ожидаю GitHub Actions…';tab=1;});
      _watchBuild(commit);
    }catch(e){setState(()=>status='Ошибка применения: '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Widget github()=>ListView(children:[
    const Text('GitHub проекта',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    const Text('Для записи нужен GitHub token с правом Contents: Write.',style:TextStyle(color:Colors.white54)),
    const SizedBox(height:12),
    TextField(controller:token,obscureText:true,decoration:const InputDecoration(labelText:'GitHub token')),
    const SizedBox(height:8),
    Row(children:[
      Expanded(child:OutlinedButton(onPressed:()=>GitHubProject.setToken(token.text.trim()),child:const Text('Сохранить'))),
      const SizedBox(width:8),
      Expanded(child:ElevatedButton(onPressed:busy?null:()=>load(filePath),child:const Text('Загрузить файл')))
    ]),
    const SizedBox(height:12),
    const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('Token хранится локально в защищённом хранилище Android. Не отправляйте его ИИ.')))
  ]);

  Widget diff()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(summary??'Изменение',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    Text('Файл: '+(patchFile??filePath),style:const TextStyle(color:Colors.white54)),
    const SizedBox(height:8),
    Expanded(child:Card(child:SingleChildScrollView(padding:const EdgeInsets.all(10),child:SelectableText(_lineDiff(find??'',replace??''),style:const TextStyle(fontFamily:'monospace',fontSize:12))))),
    Row(children:[
      Expanded(child:OutlinedButton(onPressed:()=>setState((){find=null;replace=null;patchFile=null;highlightStart=null;highlightEnd=null;}),child:const Text('Отмена'))),
      const SizedBox(width:8),
      Expanded(child:ElevatedButton(onPressed:busy?null:apply,child:const Text('Применить')))
    ])
  ]);

  String _lineDiff(String before,String after){
    final a=before.split('\\n'),b=after.split('\\n');
    final out=<String>[];
    final n=a.length>b.length?a.length:b.length;
    for(var i=0;i<n;i++){
      if(i<a.length&&i<b.length&&a[i]==b[i])out.add('  '+a[i]);
      else{
        if(i<a.length)out.add('- '+a[i]);
        if(i<b.length)out.add('+ '+b[i]);
      }
    }
    return out.join('\\n');
  }

  void _watchBuild(String commit) {
    buildTimer?.cancel();
    var attempts=0;
    Future<void> poll() async {
      if(!mounted)return;
      try{
        final b=await GitHubProject.buildStatus(commit);
        if(!mounted)return;
        setState((){buildStatus=b['conclusion']?.isNotEmpty==true?b['conclusion']!:b['status']??'unknown';buildUrl=b['html_url']??'';});
        if(b['conclusion']?.isNotEmpty==true){buildTimer?.cancel();return;}
      }catch(_){if(mounted)setState(()=>buildStatus='error');}
      attempts++;
      if(attempts<30)buildTimer=Timer(const Duration(seconds:10),poll);
    }
    poll();
  }

  Widget buildCard()=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('Сборка APK',style:TextStyle(fontWeight:FontWeight.bold)),
    Text(buildStatus.isEmpty?'После применения здесь появится статус GitHub Actions.':buildStatus),
    if(buildUrl.isNotEmpty)SelectableText(buildUrl,style:const TextStyle(color:orange,fontSize:12)),
  ])));

  Widget sourceView()=>Column(children:[
    Row(children:[
      Expanded(child:Text(loaded?filePath+' • '+sha.substring(0,8):'Исходник не загружен')),
      DropdownButton<String>(value:filePath,items:files.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:busy?null:(v){if(v!=null)load(v);}),
      IconButton(onPressed:busy?null:()=>load(filePath),icon:const Icon(Icons.refresh,color:orange))
    ]),
    Expanded(child:SingleChildScrollView(child:SelectableText(loaded?SelfEditorLocator.numbered(source,highlightStart:highlightStart,highlightEnd:highlightEnd).join('\n'):'Выберите файл и нажмите загрузить.',style:const TextStyle(fontFamily:'monospace',fontSize:12))))
  ]);

  Widget blockView()=>ListView(children:[
    const Text('Блоки приложения',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const SizedBox(height:6),
    const Text('Нажмите на блок — Kuzay найдёт связанный код и покажет его строки.',style:TextStyle(color:Colors.white54)),
    const SizedBox(height:6),
    ...blockList.map((x)=>Card(child:ListTile(
      title:Text(x),
      subtitle:Text(_blockHint(x)),
      leading:const Icon(Icons.code,color:orange),
      trailing:const Icon(Icons.arrow_forward_ios,size:16,color:Colors.white38),
      onTap:()=>_selectBlock(x),
    )))
  ]);

  String _blockHint(String name){
    const hints={
      'Шрифт приложения':'ThemeData / fontFamily',
      'Цветовая тема':'ThemeData / colorScheme',
      'Навигация':'Drawer / routes',
      'Настройки ИИ':'Store / provider settings',
      'Чат':'HomePage / AiService',
      'Workspace':'WorkspacePage',
      'AI Designer':'DesignerPage',
      'Саморедактор':'SelfEditorPage',
      'Плагины':'PluginsPage',
    };
    return hints[name]??'Код приложения';
  }

  Future<void> _selectBlock(String name) async {
    if(busy)return;
    setState(()=>busy=true);
    try{
      if(!loaded){
        final d=await SelfEditorEngine.load(filePath);
        source=d['content']!;sha=d['sha']!;loaded=true;
      }
      final ranges={
        'Шрифт приложения':RegExp(r'fontFamily:\s*font'),
        'Цветовая тема':RegExp(r'colorScheme:\s*const ColorScheme'),
        'Навигация':RegExp(r'drawer:\s*Drawer'),
        'Настройки ИИ':RegExp(r'class Store'),
        'Чат':RegExp(r'class HomePage'),
        'Workspace':RegExp(r'class WorkspacePage'),
        'AI Designer':RegExp(r'class DesignerPage'),
        'Саморедактор':RegExp(r'class SelfEditorPage'),
        'Плагины':RegExp(r'class PluginsPage'),
      };
      final re=ranges[name];
      if(re==null) throw Exception('Для блока нет карты исходника.');
      final m=re.firstMatch(source);
      if(m==null) throw Exception('Не найдено соответствие в $filePath.');
      final start=m.start;
      final endLine=(start<source.length?source.substring(0,start):source).split('\n').length;
      int endOffset=endLine;
      final loc=SelfEditorLocator.locate(source,source.substring(m.start,m.end));
      setState((){
        find=source.substring(m.start,m.end);
        replace=find;
        patchFile=filePath;
        highlightStart=loc?.startLine??endLine;
        highlightEnd=loc?.endLine??endLine;
        summary='Блок: '+name;
        status='Выбран блок «'+name+'» — строка '+highlightStart.toString();
        tab=1;
      });
    }catch(e){
      setState(()=>status='Ошибка поиска блока: '+e.toString());
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext c)=>Scaffold(
    appBar:AppBar(title:const Text('Саморедактор Kuzay AI')),
    body:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
        DropdownButtonFormField<String>(
          value:filePath,
          items:files.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
          onChanged:busy?null:(v){if(v!=null){setState(()=>filePath=v);load(v);}},
          decoration:const InputDecoration(labelText:'Файл проекта')
        ),
        const SizedBox(height:8),
        TextField(controller:command,maxLines:2,decoration:const InputDecoration(hintText:'Например: «добавь две нейросети»')),
        const SizedBox(height:6),
        Row(children:[Expanded(child:Text(status,style:const TextStyle(color:Colors.white54))),IconButton(onPressed:busy?null:prepare,icon:const Icon(Icons.auto_awesome,color:orange))])
      ]))),
      Row(children:[
        Expanded(child:TextButton(onPressed:()=>setState(()=>tab=0),child:const Text('Блоки'))),
        Expanded(child:TextButton(onPressed:()=>setState(()=>tab=1),child:const Text('Исходник'))),
        Expanded(child:TextButton(onPressed:()=>setState(()=>tab=2),child:const Text('Diff'))),
        Expanded(child:TextButton(onPressed:()=>setState(()=>tab=3),child:const Text('GitHub')))
      ]),
      if(buildStatus.isNotEmpty) buildCard(),
      const SizedBox(height:6),
      Expanded(child:tab==0?blockView():tab==1?sourceView():tab==2?diff():github())
    ])));
}
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});
  @override State<PluginsPage> createState()=>_PluginsPageState();
}
class _PluginsPageState extends State<PluginsPage> {
  final plugins=<String,bool>{'Calculator':true,'Code Helper':true,'File Tools':true,'Web Search':false};
  final calc=TextEditingController();
  String calcResult='';
  void calculate(){
    final x=calc.text.replaceAll(' ','');
    final m=RegExp(r'^(-?\d+(?:\.\d+)?)([+\-*/])(-?\d+(?:\.\d+)?)$').firstMatch(x);
    if(m==null){setState(()=>calcResult='Поддерживаются простые операции: 2+2, 10*5, 8/2');return;}
    final a=double.parse(m.group(1)!); final b=double.parse(m.group(3)!); final op=m.group(2);
    if(op=='/' && b==0){setState(()=>calcResult='Деление на ноль');return;}
    final v=op=='+'?a+b:op=='-'?a-b:op=='*'?a*b:a/b;
    setState(()=>calcResult=v.toStringAsFixed(v%1==0?0:6));
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Plugins')),
    body:ListView(padding:const EdgeInsets.all(12),children:[
      const Card(child:Padding(padding:EdgeInsets.all(14),child:Text('Безопасные встроенные инструменты. Они работают локально и не выполняют произвольный код.'))),
      ...plugins.entries.map((e)=>SwitchListTile(title:Text(e.key),subtitle:Text(e.value?'Включён':'Выключен'),value:e.value,onChanged:(v)=>setState(()=>plugins[e.key]=v))),
      if(plugins['Calculator']==true) ...[
        const SizedBox(height:12), const Text('Калькулятор',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:8), TextField(controller:calc,decoration:const InputDecoration(hintText:'Например: 25*4')),
        const SizedBox(height:8), ElevatedButton(onPressed:calculate,child:const Text('Посчитать')),
        if(calcResult.isNotEmpty) Padding(padding:const EdgeInsets.all(12),child:SelectableText(calcResult,style:const TextStyle(fontSize:20,color:orange)))
      ],
      if(plugins['Web Search']==true) const Card(child:Padding(padding:EdgeInsets.all(14),child:Text('Web Search включён как разрешение. Для реального поиска нужен настроенный поисковый API.'))),
      const SizedBox(height:10),
      OutlinedButton.icon(onPressed:()=>showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Безопасность'),content:const Text('Плагины не выполняют загруженный произвольный код. Доступ к инструментам включается пользователем.'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK'))])),icon:const Icon(Icons.security),label:const Text('О безопасности'))
    ]),
  );
}
