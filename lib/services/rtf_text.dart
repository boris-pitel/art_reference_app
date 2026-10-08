import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class _RtfStyle {
  _RtfStyle({
    this.bold = false,
    this.italic = false,
    this.skip = false,
    this.uc = 1,
    this.fontSize = 16,
  });
  bool bold, italic, skip;
  int uc;
  double fontSize;
  _RtfStyle copy() => _RtfStyle(
    bold: bold,
    italic: italic,
    skip: skip,
    uc: uc,
    fontSize: fontSize,
  );
}

/// Reads common RTF formatting without interpreting embedded objects or fields.
List<TextSpan> rtfText(Uint8List bytes) {
  final source = latin1.decode(bytes);
  if (!source.startsWith(r'{\rtf')) {
    throw const FormatException('This file is not a valid RTF document.');
  }
  final spans = <TextSpan>[];
  final stack = <_RtfStyle>[];
  var state = _RtfStyle();
  var fallback = 0;
  var buffer = StringBuffer();
  TextStyle? activeStyle;
  void flush() {
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString(), style: activeStyle));
    }
    buffer = StringBuffer();
  }

  void emit(String text) {
    if (fallback > 0) {
      fallback--;
      return;
    }
    if (!state.skip && text.isNotEmpty) {
      final style = TextStyle(
        fontWeight: state.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: state.italic ? FontStyle.italic : FontStyle.normal,
        fontSize: state.fontSize,
      );
      if (activeStyle != style) {
        flush();
        activeStyle = style;
      }
      buffer.write(text);
    }
  }

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      stack.add(state.copy());
      continue;
    }
    if (char == '}') {
      if (stack.isNotEmpty) state = stack.removeLast();
      continue;
    }
    if (char != '\\') {
      if (char != '\r' && char != '\n') emit(char);
      continue;
    }
    if (++i >= source.length) break;
    final symbol = source[i];
    if (symbol == '\\' || symbol == '{' || symbol == '}') {
      emit(symbol);
      continue;
    }
    if (symbol == '*') {
      state.skip = true;
      continue;
    }
    if (symbol == "'" && i + 2 < source.length) {
      final code = int.tryParse(source.substring(i + 1, i + 3), radix: 16);
      if (code != null) emit(String.fromCharCode(code));
      i += 2;
      continue;
    }
    if (!RegExp('[a-zA-Z]').hasMatch(symbol)) {
      if (symbol == '~') emit('\u00a0');
      continue;
    }
    final start = i;
    while (i + 1 < source.length &&
        RegExp('[a-zA-Z]').hasMatch(source[i + 1])) {
      i++;
    }
    final word = source.substring(start, i + 1);
    var number = '';
    if (i + 1 < source.length && source[i + 1] == '-') {
      number = source[++i];
    }
    while (i + 1 < source.length && RegExp('[0-9]').hasMatch(source[i + 1])) {
      number += source[++i];
    }
    final value = int.tryParse(number);
    if (i + 1 < source.length && source[i + 1] == ' ') i++;
    if ([
      'fonttbl',
      'colortbl',
      'stylesheet',
      'info',
      'pict',
      'object',
      'fldinst',
      'header',
      'footer',
    ].contains(word)) {
      state.skip = true;
      continue;
    }
    if (word == 'b') state.bold = value != 0;
    if (word == 'i') state.italic = value != 0;
    if (word == 'fs' && value != null && value > 0) {
      state.fontSize = (value / 2).clamp(8, 72);
    }
    if (word == 'plain') {
      state.bold = false;
      state.italic = false;
      state.fontSize = 16;
    }
    if (word == 'par' || word == 'line') emit('\n');
    if (word == 'tab') emit('\t');
    if (word == 'bullet') emit('•');
    if (word == 'emdash') emit('—');
    if (word == 'endash') emit('–');
    if (word == 'lquote' || word == 'rquote') emit("'");
    if (word == 'ldblquote' || word == 'rdblquote') emit('"');
    if (word == 'uc') state.uc = value ?? 1;
    if (word == 'u' && value != null) {
      emit(String.fromCharCode(value < 0 ? value + 65536 : value));
      fallback = state.uc;
    }
    if (word == 'bin' && value != null && value > 0) {
      i = (i + value).clamp(0, source.length - 1);
    }
  }
  flush();
  return spans;
}
