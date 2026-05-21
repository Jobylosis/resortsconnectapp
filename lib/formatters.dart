import 'package:flutter/services.dart';

class EmojiInputFormatter extends TextInputFormatter {
  static final _emojiRegex = RegExp(r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]', unicode: true);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (_emojiRegex.hasMatch(newValue.text)) {
      return TextEditingValue(
        text: newValue.text.replaceAll(_emojiRegex, ''),
        selection: TextSelection.collapsed(offset: newValue.text.replaceAll(_emojiRegex, '').length),
      );
    }
    return newValue;
  }
}
