// Local source audit only. Parse trees enumerate syntax, not runtime reachability.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Audit extends RecursiveAstVisitor<void> {
  Audit(this.path, this.source);
  final String path, source;
  final declarations = <Map<String, Object?>>[];
  final calls = <Map<String, Object?>>[];
  final callbacks = <Map<String, Object?>>[];
  final providers = <Map<String, Object?>>[];
  final dialogs = <Map<String, Object?>>[];
  final scopes = <String>[];
  int line(AstNode node) =>
      '\n'.allMatches(source.substring(0, node.offset)).length + 1;
  Map<String, Object?> entry(AstNode node) => {
    'file': path,
    'line': line(node),
    'offset': node.offset,
    'length': node.length,
    'scope': scopes.join('/'),
  };
  void declaration(
    AstNode node,
    String kind,
    String name,
    void Function() visit,
  ) {
    declarations.add({...entry(node), 'kind': kind, 'name': name});
    scopes.add(name);
    visit();
    scopes.removeLast();
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) => declaration(
    node,
    'class',
    node.name.toString(),
    () => super.visitClassDeclaration(node),
  );
  @override
  void visitEnumDeclaration(EnumDeclaration node) => declaration(
    node,
    'enum',
    node.name.toString(),
    () => super.visitEnumDeclaration(node),
  );
  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) => declaration(
    node,
    'extension',
    node.name?.toString() ?? '<anonymous>',
    () => super.visitExtensionDeclaration(node),
  );
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) => declaration(
    node,
    'function',
    node.name.toString(),
    () => super.visitFunctionDeclaration(node),
  );
  @override
  void visitMethodDeclaration(MethodDeclaration node) => declaration(
    node,
    node.isGetter
        ? 'getter'
        : node.isSetter
        ? 'setter'
        : 'method',
    node.name.toString(),
    () => super.visitMethodDeclaration(node),
  );
  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) => declaration(
    node,
    'constructor',
    '${node.returnType}.${node.name ?? 'new'}',
    () => super.visitConstructorDeclaration(node),
  );
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final name = node.name.toString();
    if (name.endsWith('Provider'))
      providers.add({
        ...entry(node),
        'name': name,
        'initializer': node.initializer?.toSource(),
      });
    super.visitVariableDeclaration(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final name = node.name.label.toString();
    if (const {
      'onPressed',
      'onTap',
      'onSelected',
      'onReveal',
      'onRetry',
      'onDone',
      'onChanged',
      'onInvalidate',
    }.contains(name)) {
      callbacks.add({
        ...entry(node),
        'event': name,
        'expression': node.expression.toSource(),
      });
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final first = node.argumentList.arguments.isEmpty
        ? null
        : node.argumentList.arguments.first;
    final target = first is StringLiteral ? first.stringValue : null;
    final item = {
      ...entry(node),
      'method': method,
      'receiver': node.target?.toSource(),
      'literal_first_argument': target,
      'arguments': node.argumentList.toSource(),
      'dispatch_target_static': target != null,
    };
    calls.add(item);
    if (method == 'showDialog' ||
        method.startsWith('showAdmin') && method.endsWith('Dialog'))
      dialogs.add(item);
    super.visitMethodInvocation(node);
  }
}

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Expected exact repository path.');
  final root = Directory(args.single).absolute.path;
  final paths =
      Directory('$root/lib/admin')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final units = <Map<String, Object?>>[];
  final errors = <Map<String, Object?>>[];
  for (final file in paths) {
    final source = file.readAsStringSync();
    final path = file.path.substring(root.length + 1);
    final parsed = parseString(
      content: source,
      path: file.path,
      throwIfDiagnostics: false,
    );
    for (final error in parsed.errors) {
      errors.add({
        'file': path,
        'offset': error.offset,
        'length': error.length,
        'code': error.errorCode.name,
        'message': error.message,
      });
    }
    final audit = Audit(path, source);
    parsed.unit.accept(audit);
    units.add({
      'file': path,
      'fixture_only': const {
        'admin_evidence_mode.dart',
        'admin_review_credentials.dart',
      }.contains(file.uri.pathSegments.last),
      'declarations': audit.declarations,
      'invocations': audit.calls,
      'providers': audit.providers,
      'dialogs': audit.dialogs,
      'callbacks': audit.callbacks,
    });
  }
  stdout.writeln(
    jsonEncode({
      'method':
          'Dart analyzer syntax AST; semantic resolution/reachability not claimed',
      'parser_errors': errors,
      'units': units,
    }),
  );
  if (errors.isNotEmpty) exitCode = 1;
}
