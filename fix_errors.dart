import 'dart:io';

void main() async {
  final file = File('/tmp/analyze_errors.txt');
  if (!await file.exists()) {
    print('No errors file found.');
    return;
  }

  // Parse errors
  final lines = await file.readAsLines();
  final Map<String, List<Map<String, dynamic>>> fileErrors = {};
  
  for (var line in lines) {
    if (line.isEmpty || !line.contains(' • ')) {
      // It might be a regular line, try split by space depending on flutter format
      continue;
    }
    
    // Format: "  error • Invalid constant value • lib/shared/widgets/status_badge.dart:49:16 • invalid_constant"
    final parts = line.split(' • ');
    if (parts.length < 4) continue;
    
    final type = parts[0].trim(); // error or info
    final message = parts[1].trim();
    final locationInfo = parts[2].trim();
    final errorCode = parts[3].trim();
    
    final locParts = locationInfo.split(':');
    if (locParts.length < 3) continue;
    
    final filePath = locParts[0];
    final lineNumber = int.tryParse(locParts[1]) ?? -1;
    
    if (lineNumber == -1) continue;
    
    if (!fileErrors.containsKey(filePath)) {
      fileErrors[filePath] = [];
    }
    
    fileErrors[filePath]!.add({
      'line': lineNumber - 1, // 0-indexed
      'message': message,
      'code': errorCode
    });
  }
  
  // Process files
  int filesModified = 0;
  for (var entry in fileErrors.entries) {
    if (await _fixErrors(entry.key, entry.value)) {
      filesModified++;
    }
  }
  
  print('Fixed errors in $filesModified files.');
}

Future<bool> _fixErrors(String filePath, List<Map<String, dynamic>> errors) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      // In case it's relative to lib but the script runs in the root
      return false;
    }
    
    List<String> content = await file.readAsLines();
    bool changed = false;
    bool needsRelativeImport = false;
    
    // Sort errors descending by line to avoid offset issues
    errors.sort((a, b) => (b['line'] as int).compareTo(a['line'] as int));
    
    for (var error in errors) {
      final int lineIdx = error['line'] as int;
      if (lineIdx < 0 || lineIdx >= content.length) continue;
      
      final String line = content[lineIdx];
      final String code = error['code'] as String;
      final String message = error['message'] as String;
      
      // Fix 1: Invalid constant
      if (code == 'invalid_constant' || code == 'invalid_annotation_constant_value_from_deferred_library' || code == 'const_with_non_constant_argument') {
         if (line.contains('const ')) {
            content[lineIdx] = line.replaceAll(RegExp(r'\bconst\s+'), '');
            changed = true;
         }
         // Sometimes the const is on the parent (e.g. const Column(children: [Text(context.l10n...)]))
         // This is harder to fix blindly, but we'll try to walk up
         int currentLine = lineIdx;
         while (currentLine >= 0 && currentLine > lineIdx - 5) {
            String cLine = content[currentLine];
            if (cLine.contains('const ') && !cLine.contains('const [') && !cLine.contains('const null')) {
               content[currentLine] = cLine.replaceAll(RegExp(r'\bconst\s+'), '');
               changed = true;
               break;
            }
            if (cLine.contains('const [')) {
               content[currentLine] = cLine.replaceAll('const [', '[');
               changed = true;
               break; 
            }
            currentLine--;
         }
      }
      
      // Fix 2: URI does not exist (import package:cool instead of relative, or wrong relative)
      if (code == 'uri_does_not_exist' && message.contains('l10n.dart')) {
         needsRelativeImport = true;
      }
      
      // Fix 3: Depend on referenced packages (same thing)
      if (code == 'depend_on_referenced_packages' && message.contains("'cool'")) {
         needsRelativeImport = true;
      }
      
      // Fix 4: Context undefined
      // This happens when context is not in scope (e.g. inside a model class or a static list)
      if (code == 'undefined_identifier' && message.contains('context')) {
        // Regex to find context.l10n.<key>
        final match = RegExp(r'context\.l10n\.([a-zA-Z0-9_]+)').firstMatch(line);
        if (match != null) {
          final key = match.group(1);
          // Simple fallback: just convert the camelCase back as a temporary fix,
          // or run it against the original dictionary later.
          // Since it's a few files, we'll try to guess the original text based on key,
          // or run a basic format.
          if (key != null) {
              String original = key.replaceAll(RegExp(r'(?<!^)(?=[A-Z])'), ' ');
              original = original.substring(0, 1).toUpperCase() + original.substring(1);
              content[lineIdx] = line.replaceAll('context.l10n.$key', "'$original'");
              changed = true;
          }
        }
      }
    } // Close the for loop
    if (needsRelativeImport) {
       // Find the depth of the file to construct relative import
       // path is like lib/features/groups/screens/group.dart
       int depth = filePath.split('/').length - 2; // -1 for file, -1 for lib
       if (depth < 0) depth = 0;
       
       String relativeDots = List.filled(depth, '../').join('');
       if (relativeDots.isEmpty) relativeDots = './';
       // l10n is in lib/core/l10n/l10n.dart
       String relativeImport = "import '${relativeDots}core/l10n/l10n.dart';";
       
       // Replace the incorrect package import or add it
       bool replaced = false;
       for (int i = 0; i < content.length; i++) {
         if (content[i].contains("import 'package:cool/core/l10n/l10n.dart';")) {
           content[i] = relativeImport;
           replaced = true;
           changed = true;
           break;
         }
       }
       
       if (!replaced) {
          int lastImport = content.lastIndexWhere((l) => l.startsWith('import '));
          if (lastImport != -1) {
             content.insert(lastImport + 1, relativeImport);
          } else {
             content.insert(0, relativeImport);
          }
          changed = true;
       }
    }
    
    if (changed) {
      await file.writeAsString(content.join('\n'));
      return true;
    }
    return false;
  } catch (e) {
    print('Error on $filePath: $e');
    return false;
  }
}
