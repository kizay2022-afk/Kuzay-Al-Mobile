import 'package:onenm_local_llm/onenm_local_llm.dart';

class LocalAiService {
  static final OneNm _ai = OneNm(
    model: OneNmModel.tinyllama,
    settings: const GenerationSettings(
      temperature: 0.7,
      topK: 40,
      topP: 0.9,
      maxTokens: 256,
      repeatPenalty: 1.1,
    ),
  );

  static bool _ready = false;
  static Future<void>? _initializing;

  static Future<void> initialize() {
    if (_ready) return Future.value();
    return _initializing ??= _init();
  }

  static Future<void> _init() async {
    try {
      await _ai.initialize();
      _ready = true;
    } finally {
      _initializing = null;
    }
  }

  static Future<String> ask(String prompt, {String? system}) async {
    await initialize();
    final message = system == null || system.trim().isEmpty
        ? prompt
        : system.trim() + '\n\n' + prompt;
    return _ai.chat(message);
  }

  static Future<void> clearHistory() async {
    if (_ready) _ai.clearHistory();
  }

  static Future<void> dispose() async {
    if (_ready) {
      await _ai.dispose();
      _ready = false;
    }
  }
}
