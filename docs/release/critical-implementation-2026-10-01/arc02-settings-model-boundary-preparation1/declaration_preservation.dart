import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> args) {
  if (args.length != 3) throw ArgumentError('Expected before, main and part.');
  final units = args.map((path) => parseString(content: File(path).readAsStringSync(), path: path, throwIfDiagnostics: false)).toList();
  final errors = [for (var i = 0; i < units.length; i++) for (final error in units[i].errors) {'path': args[i], 'code': error.errorCode.name, 'message': error.message}];
  Map<String, Object?> declaration(CompilationUnitMember item) => {'kind': item.runtimeType.toString(), 'syntax': item.toSource()};
  final before = units[0].unit.declarations.map(declaration).toList();
  final after = [for (final unit in units.skip(1)) ...unit.unit.declarations.map(declaration)];
  final beforeImports = units[0].unit.directives.whereType<ImportDirective>().map((x) => x.toSource()).toList();
  final afterImports = units[1].unit.directives.whereType<ImportDirective>().map((x) => x.toSource()).toList();
  final part = units[1].unit.directives.whereType<PartDirective>().toList();
  final partOf = units[2].unit.directives.whereType<PartOfDirective>().toList();
  final preserved = jsonEncode(before) == jsonEncode(after);
  final directiveBinding = part.length == 1 && part.single.uri.stringValue == 'admin_governed_settings_history_models.dart' && partOf.length == 1 && partOf.single.uri?.stringValue == 'admin_governed_settings_models.dart' && units[2].unit.directives.length == 1;
  final importsPreserved = jsonEncode(beforeImports) == jsonEncode(afterImports);
  final success = errors.isEmpty && preserved && importsPreserved && directiveBinding;
  stdout.writeln(jsonEncode({'status': success ? 'pass' : 'fail', 'parser_errors': errors, 'original_declaration_count': before.length, 'proposed_declaration_count': after.length, 'all_declaration_syntax_and_order_preserved': preserved, 'all_original_imports_preserved': importsPreserved, 'part_library_binding_valid': directiveBinding, 'semantic_type_resolution_or_runtime_behavior_proven': false}));
  if (!success) exitCode = 1;
}
