import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GitHubProject {
  static const repo = 'kizay2022-afk/Kuzay-Al-Mobile';
  static const path = 'lib/main.dart';
  static const api = 'https://api.github.com';
  static const secure = FlutterSecureStorage();

  static Future<String> token() async => await secure.read(key: 'github_token') ?? '';
  static Future<void> setToken(String value) async => secure.write(key: 'github_token', value: value);

  static Future<Map<String,String>> fetchFile(String filePath) async {
    final safePath = Uri.encodeComponent(filePath).replaceAll('%2F', '/');
    final r = await http.get(Uri.parse('$api/repos/$repo/contents/$safePath?ref=main'),
      headers: {'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}).timeout(const Duration(seconds:30));
    if (r.statusCode != 200) throw Exception('GitHub HTTP ${r.statusCode}');
    final d = jsonDecode(r.body);
    if (d['type'] != 'file') throw Exception('Это не файл: $filePath');
    final bytes = base64Decode((d['content'] as String).replaceAll(RegExp(r'\s'), ''));
    return {'sha': d['sha'].toString(), 'content': utf8.decode(bytes)};
  }

  static Future<Map<String,String>> fetchMain() async {
    return fetchFile(path);
  }

  static Future<String> updateFile({required String filePath, required String content, required String sha, required String message}) async {
    final key = await token();
    if (key.trim().isEmpty) throw Exception('Добавьте GitHub token.');
    final safePath = Uri.encodeComponent(filePath).replaceAll('%2F', '/');
    final r = await http.put(Uri.parse('$api/repos/$repo/contents/$safePath'),
      headers: {'Accept':'application/vnd.github+json','Authorization':'Bearer $key','X-GitHub-Api-Version':'2022-11-28','Content-Type':'application/json'},
      body: jsonEncode({'message':message,'content':base64Encode(utf8.encode(content)),'sha':sha,'branch':'main'})).timeout(const Duration(seconds:60));
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('GitHub HTTP ${r.statusCode}: ${r.body}');
    final data = jsonDecode(r.body);
    return data['commit']?['sha']?.toString() ?? '';
  }

  static Future<Map<String,String>> buildStatus(String commitSha) async {
    final r = await http.get(Uri.parse('$api/repos/$repo/actions/runs?branch=main&per_page=10'), headers: {'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}).timeout(const Duration(seconds:30));
    if(r.statusCode!=200) throw Exception('GitHub Actions HTTP ${r.statusCode}');
    final runs=(jsonDecode(r.body)['workflow_runs'] as List<dynamic>?)??const [];
    for(final item in runs){
      final run=item as Map<String,dynamic>;
      if(run['head_sha']?.toString()==commitSha){
        return {'id':run['id'].toString(),'status':run['status']?.toString()??'unknown','conclusion':run['conclusion']?.toString()??'','html_url':run['html_url']?.toString()??''};
      }
    }
    return {'id':'','status':'queued','conclusion':'','html_url':'https://github.com/$repo/actions'};
  }

  static Future<void> updateMain({required String content, required String sha, required String message}) async {
    await updateFile(filePath:path, content:content, sha:sha, message:message);
  }

  static Future<void> updateMainLegacy({required String content, required String sha, required String message}) async {
    final key = await token();
    if (key.trim().isEmpty) throw Exception('Добавьте GitHub token.');
    final r = await http.put(Uri.parse('$api/repos/$repo/contents/$path'),
      headers: {'Accept':'application/vnd.github+json','Authorization':'Bearer $key','X-GitHub-Api-Version':'2022-11-28','Content-Type':'application/json'},
      body: jsonEncode({'message':message,'content':base64Encode(utf8.encode(content)),'sha':sha,'branch':'main'})).timeout(const Duration(seconds:60));
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('GitHub HTTP ${r.statusCode}: ${r.body}');
  }
}
