import 'dart:io';

class ConsoleIo {
  const ConsoleIo();

  void out([Object value = '']) => stdout.writeln(value);
  void error([Object value = '']) => stderr.writeln(value);

  String? readLine(String prompt) {
    stdout.write(prompt);
    return stdin.readLineSync()?.trim();
  }

  String readHidden(String prompt) {
    if (!stdin.hasTerminal) {
      throw StateError('A terminal is required for hidden password input.');
    }

    stdout.write(prompt);
    final previousEcho = stdin.echoMode;
    try {
      stdin.echoMode = false;
      return stdin.readLineSync() ?? '';
    } finally {
      stdin.echoMode = previousEcho;
      stdout.writeln();
    }
  }
}
