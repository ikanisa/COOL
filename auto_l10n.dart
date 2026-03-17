import 'dart:io';
import 'dart:convert';

void main() async {
  final l10nFile = File('lib/l10n/app_en.arb');
  if (!await l10nFile.exists()) {
    print('app_en.arb not found.');
    return;
  }

  // Load existing l10n keys
  final l10nContent = await l10nFile.readAsString();
  final Map<String, dynamic> arbMap = json.decode(l10nContent);
  final Set<String> existingKeys = arbMap.keys.toSet();

  // Read hardcoded results
  final resultsFile = File('/tmp/hardcoded_results.txt');
  if (!await resultsFile.exists()) {
    print('hardcoded_results.txt not found.');
    return;
  }

  final lines = await resultsFile.readAsLines();
  final Map<String, List<Map<String, dynamic>>> fileModifications = {};
  
  // Clean up existing known keys that might clash
  arbMap.removeWhere((key, value) => key.startsWith('@') && key != '@@locale');

  int newKeysAdded = 0;
  
  for (var line in lines) {
    if (line.isEmpty || !line.contains(':')) continue;
    
    // Parse format: /path/to/file.dart:lineNumber: "String content"
    final firstColon = line.indexOf(':');
    final secondColon = line.indexOf(':', firstColon + 1);
    
    if (firstColon == -1 || secondColon == -1) continue;
    
    final filePath = line.substring(0, firstColon);
    final lineNumberStr = line.substring(firstColon + 1, secondColon);
    int lineNumber = int.tryParse(lineNumberStr) ?? -1;
    
    if (lineNumber == -1) continue;
    
    // Extract everything after the second colon
    String contentLine = line.substring(secondColon + 1).trim();
    
    // Simple extraction of literal text (we already know what they look like)
    // Most common: Text('something') or label: 'something'
    String? capturedText;
    
    // Try single quotes
    var sqStart = contentLine.indexOf("'");
    var sqEnd = contentLine.lastIndexOf("'");
    
    // Try double quotes
    var dqStart = contentLine.indexOf('"');
    var dqEnd = contentLine.lastIndexOf('"');
    
    if (sqStart != -1 && sqEnd != -1 && sqEnd > sqStart) {
      // Avoid extracting from things like '${var}' by skipping lines with $
      if (!contentLine.contains(r'$')) {
        capturedText = contentLine.substring(sqStart + 1, sqEnd);
        // Ensure it's not empty and contains letters
        if (capturedText.trim().isEmpty || !capturedText.contains(RegExp(r'[a-zA-Z]'))) {
           capturedText = null;
        }
      }
    } else if (dqStart != -1 && dqEnd != -1 && dqEnd > dqStart) {
      if (!contentLine.contains(r'$')) {
        capturedText = contentLine.substring(dqStart + 1, dqEnd);
        if (capturedText.trim().isEmpty || !capturedText.contains(RegExp(r'[a-zA-Z]'))) {
           capturedText = null;
        }
      }
    }
    
    if (capturedText == null) continue;
    
    // Generate a reasonable key
    String key = _generateKey(capturedText);
    if (key.isEmpty) continue;
    
    // Add to mapping if not exists
    if (!arbMap.containsKey(key)) {
      arbMap[key] = capturedText;
      newKeysAdded++;
    } else {
      // Check if value is the same, if not, create a variant key
      if (arbMap[key] != capturedText) {
        int suffix = 1;
        String newKey = '${key}$suffix';
        while (arbMap.containsKey(newKey)) {
          suffix++;
          newKey = '${key}$suffix';
        }
        key = newKey;
        arbMap[key] = capturedText;
        newKeysAdded++;
      }
    }
    
    // Record modification for the dart file
    if (!fileModifications.containsKey(filePath)) {
      fileModifications[filePath] = [];
    }
    
    fileModifications[filePath]!.add({
      'line': lineNumber,
      'original': capturedText,
      'key': key,
      'isSingleQuote': sqStart != -1,
    });
  }
  
  // Write updated arb file
  if (newKeysAdded > 0) {
    print('Adding $newKeysAdded new keys to app_en.arb');
    const encoder = JsonEncoder.withIndent('  ');
    await l10nFile.writeAsString(encoder.convert(arbMap));
  } else {
    print('No new keys to add.');
  }
  
  // Apply modifications to files
  int filesModifiedCount = 0;
  for (var entry in fileModifications.entries) {
    if (_applyModifications(entry.key, entry.value)) {
      filesModifiedCount++;
    }
  }
  
  print('Done! Modified $filesModifiedCount files.');
}

bool _applyModifications(String filePath, List<Map<String, dynamic>> modifications) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return false;
    
    List<String> lines = file.readAsLinesSync();
    bool fileChanged = false;
    bool needsImport = false;
    
    // Sort modifications by line descending so we don't mess up line numbers when doing multiple replacements on a line
    // Or just do string replacement if we do it once per line
    Map<int, List<Map<String, dynamic>>> lineMods = {};
    for (var mod in modifications) {
      final lineIdx = (mod['line'] as int) - 1; // 0-indexed
      if (lineIdx >= 0 && lineIdx < lines.length) {
        if (!lineMods.containsKey(lineIdx)) {
          lineMods[lineIdx] = [];
        }
        lineMods[lineIdx]!.add(mod);
      }
    }
    
    for (var lineIdx in lineMods.keys) {
      String line = lines[lineIdx];
      String originalLine = line;
      
      for (var mod in lineMods[lineIdx]!) {
        String originalText = mod['original'];
        String key = mod['key'];
        bool isSq = mod['isSingleQuote'];
        
        // Search for 'text' or "text" and replace with context.l10n.key
        String searchTarget = isSq ? "'$originalText'" : '"$originalText"';
        String replacement = 'context.l10n.$key';
        
        // Handling const removals if needed
        // Since we are moving from const String to context.l10n (which is a method call),
        // we might break const constructors. We'll do a simple regex replace to remove const from the line if it has one
        if (line.contains(searchTarget)) {
           line = line.replaceAll(searchTarget, replacement);
           needsImport = true;
           // Remove consts close to the element
           line = line.replaceAll(RegExp(r'const\s+Text\('), 'Text(');
           line = line.replaceAll(RegExp(r'const\s+'), ''); // aggressive but safe for most widget trees in a single line context
        }
      }
      
      if (line != originalLine) {
        lines[lineIdx] = line;
        fileChanged = true;
      }
    }
    
    if (fileChanged) {
      // Add import if not present
      if (needsImport) {
        bool hasImport = lines.any((l) => l.contains("core/l10n/l10n.dart"));
        if (!hasImport) {
          // Find last import
          int lastImportIdx = -1;
          for (int i = 0; i < lines.length; i++) {
            if (lines[i].startsWith('import ')) {
              lastImportIdx = i;
            }
          }
          
          if (lastImportIdx != -1) {
            // Need relative path since files are in different depths
            // Quick hack: just use an absolute package import
            lines.insert(lastImportIdx + 1, "import 'package:cool_app/core/l10n/l10n.dart';");
          } else {
             lines.insert(0, "import 'package:cool_app/core/l10n/l10n.dart';");
          }
        }
      }
      
      file.writeAsStringSync(lines.join('\n'));
      return true;
    }
    return false;
  } catch (e) {
    print('Failed to modify $filePath: $e');
    return false;
  }
}

String _generateKey(String text) {
  // Remove special characters, keep alphanumeric
  String clean = text.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
  if (clean.isEmpty) return 'key${text.hashCode.abs()}';
  
  List<String> words = clean.split(RegExp(r'\s+'));
  if (words.isEmpty) return 'key${text.hashCode.abs()}';
  
  // Take up to first 4 words
  int wordCount = words.length > 4 ? 4 : words.length;
  String key = words[0].toLowerCase();
  
  for (int i = 1; i < wordCount; i++) {
    if (words[i].isEmpty) continue;
    key += words[i].substring(0, 1).toUpperCase() + words[i].substring(1).toLowerCase();
  }
  
  // Ensure the key starts with a lowercase letter
  if (key.isNotEmpty && RegExp(r'^[0-9_]').hasMatch(key)) {
    key = 'str' + key.substring(0, 1).toUpperCase() + key.substring(1);
  } else if (key.isEmpty) {
     key = 'key${text.hashCode.abs()}';
  }
  
  // Avoid dart keywords
  final keywords = ['continue', 'class', 'for', 'if', 'else', 'return', 'void', 'null', 'true', 'false', 'default', 'new', 'in', 'is', 'as', 'var', 'final', 'const'];
  if (keywords.contains(key)) {
    key += 'Key';
  }
  
  return key;
}
