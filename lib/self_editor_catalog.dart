class SelfEditorCatalog {
  static const files = <String>[
    'lib/main.dart',
    'lib/github_project.dart',
    'pubspec.yaml',
  ];

  static const blocks = <String, String>{
    'Шрифт приложения': 'ThemeData / fontFamily',
    'Цветовая тема': 'ThemeData / colorScheme',
    'Навигация': 'Drawer / routes',
    'Настройки ИИ': 'Store / provider settings',
    'Чат': 'ChatPage / AiService',
    'Workspace': 'WorkspacePage',
    'AI Designer': 'DesignerPage',
    'Саморедактор': 'SelfEditorPage',
    'Плагины': 'PluginsPage',
  };

  static bool isAllowedFile(String path) => files.contains(path);
}
