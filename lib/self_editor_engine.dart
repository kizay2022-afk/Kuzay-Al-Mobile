import 'dart:convert';
import 'github_project.dart';

class SelfPatch {
  final String filePath;
  final String summary;
  final String find;
  final String replace;
  const SelfPatch({required this.filePath, required this.summary, required this.find, required this.replace});
}

class SelfEditorEngine {
  static const allowedFiles = <String>['lib/main.dart','lib/github_project.dart','lib/self_editor_catalog.dart','lib/self_editor_engine.dart','pubspec.yaml'];
  static Future<Map<String,String>> load(String path) {
    if (!allowedFiles.contains(path)) throw Exception('Файл не разрешён для саморедактора: $path');
    return GitHubProject.fetchFile(path);
  }
  static SelfPatch parsePatch(String raw, String defaultFile) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*\\s*'), '').replaceFirst(RegExp(r'\\s*```$'), '').trim();
    final data = jsonDecode(cleaned);
    if (data['action'] != 'patch') throw Exception((data['summary'] ?? 'Изменение не поддерживается').toString());
    final file = (data['file'] ?? defaultFile).toString();
    if (!allowedFiles.contains(file)) throw Exception('AI выбрал запрещённый файл: $file');
    final find = (data['find'] ?? '').toString();
    final replace = (data['replace'] ?? '').toString();
    if (find.isEmpty) throw Exception('AI не указал фрагмент для поиска.');
    return SelfPatch(filePath:file, summary:(data['summary'] ?? 'Изменение').toString(), find:find, replace:replace);
  }
  static String apply(String source, SelfPatch patch) {
    final count = RegExp(RegExp.escape(patch.find), dotAll:true).allMatches(source).length;
    if (count != 1) throw Exception('Patch отклонён: найдено совпадений ' + count.toString() + ' вместо 1.');
    return source.replaceFirst(patch.find, patch.replace);
  }
}