// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/macros/api.dart' as macro;
import 'package:_fe_analyzer_shared/src/macros/executor.dart' as macro;
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart'
    as macro;
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart'
    as macro;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/summary2/library_builder.dart';
import 'package:analyzer/src/summary2/macro.dart';
import 'package:analyzer/src/summary2/macro_application_error.dart';

class LibraryMacroApplier {
  final LibraryBuilder libraryBuilder;

  final Map<ClassDeclaration, macro.ClassDeclaration> _classDeclarations = {};

  LibraryMacroApplier(this.libraryBuilder);

  /// TODO(scheglov) check `shouldExecute`.
  /// TODO(scheglov) check `supportsDeclarationKind`.
  Future<String?> executeMacroTypesPhase() async {
    var macroResults = <macro.MacroExecutionResult>[];
    for (var unitElement in libraryBuilder.element.units) {
      for (var classElement in unitElement.classes) {
        classElement as ClassElementImpl;
        var classNode = libraryBuilder.linker.elementNodes[classElement];
        // TODO(scheglov) support other declarations
        if (classNode is ClassDeclaration) {
          var annotationList = classNode.metadata;
          for (var i = 0; i < annotationList.length; i++) {
            final annotation = annotationList[i];
            var annotationNameNode = annotation.name;
            var argumentsNode = annotation.arguments;
            if (annotationNameNode is SimpleIdentifier &&
                argumentsNode != null) {
              // TODO(scheglov) Create a Scope.
              for (var import in libraryBuilder.element.imports) {
                var importedLibrary = import.importedLibrary;
                if (importedLibrary is LibraryElementImpl) {
                  var importedUri = importedLibrary.source.uri;
                  if (!libraryBuilder.linker.builders
                      .containsKey(importedUri)) {
                    var lookupResult = importedLibrary.scope.lookup(
                      annotationNameNode.name,
                    );
                    var getter = lookupResult.getter;
                    if (getter is ClassElementImpl && getter.isMacro) {
                      var macroExecutor = importedLibrary.bundleMacroExecutor;
                      if (macroExecutor != null) {
                        try {
                          final arguments = _buildArguments(
                            annotationIndex: i,
                            node: argumentsNode,
                          );
                          final macroResult = await _runSingleMacro(
                            macroExecutor,
                            getClassDeclaration(classNode),
                            getter,
                            arguments,
                          );
                          if (macroResult.isNotEmpty) {
                            macroResults.add(macroResult);
                          }
                        } on MacroApplicationError catch (e) {
                          classElement.macroApplicationErrors.add(e);
                        } catch (e, stackTrace) {
                          classElement.macroApplicationErrors.add(
                            UnknownMacroApplicationError(
                              annotationIndex: i,
                              stackTrace: stackTrace.toString(),
                              message: e.toString(),
                            ),
                          );
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    var macroExecutor = libraryBuilder.linker.macroExecutor;
    if (macroExecutor != null && macroResults.isNotEmpty) {
      var code = macroExecutor.buildAugmentationLibrary(
        macroResults,
        _resolveIdentifier,
        _inferOmittedType,
      );
      return code.trim();
    }
    return null;
  }

  macro.ClassDeclaration getClassDeclaration(ClassDeclaration node) {
    return _classDeclarations[node] ??= _buildClassDeclaration(node);
  }

  macro.TypeAnnotation _inferOmittedType(
    macro.OmittedTypeAnnotation omittedType,
  ) {
    throw UnimplementedError();
  }

  macro.ResolvedIdentifier _resolveIdentifier(macro.Identifier identifier) {
    throw UnimplementedError();
  }

  Future<macro.MacroExecutionResult> _runSingleMacro(
    BundleMacroExecutor macroExecutor,
    macro.Declaration declaration,
    ClassElementImpl classElement,
    macro.Arguments arguments,
  ) async {
    var macroInstance = await macroExecutor.instantiate(
      libraryUri: classElement.librarySource.uri,
      className: classElement.name,
      constructorName: '', // TODO
      arguments: arguments,
      declaration: declaration,
      identifierResolver: _FakeIdentifierResolver(),
    );
    return await macroInstance.executeTypesPhase();
  }

  static macro.Arguments _buildArguments({
    required int annotationIndex,
    required ArgumentList node,
  }) {
    final positional = <Object?>[];
    final named = <String, Object?>{};
    for (var i = 0; i < node.arguments.length; ++i) {
      final argument = node.arguments[i];
      final evaluation = _ArgumentEvaluation(
        annotationIndex: annotationIndex,
        argumentIndex: i,
      );
      if (argument is NamedExpression) {
        final value = evaluation.evaluate(argument.expression);
        named[argument.name.label.name] = value;
      } else {
        final value = evaluation.evaluate(argument);
        positional.add(value);
      }
    }
    return macro.Arguments(positional, named);
  }

  static macro.ClassDeclarationImpl _buildClassDeclaration(
    ClassDeclaration node,
  ) {
    return macro.ClassDeclarationImpl(
      id: macro.RemoteInstance.uniqueId,
      identifier: _buildIdentifier(node.name),
      typeParameters: _buildTypeParameters(node.typeParameters),
      interfaces: _buildTypeAnnotations(node.implementsClause?.interfaces),
      isAbstract: node.abstractKeyword != null,
      isExternal: false,
      mixins: _buildTypeAnnotations(node.withClause?.mixinTypes),
      superclass: node.extendsClause?.superclass.mapOrNull(
        _buildTypeAnnotation,
      ),
    );
  }

  static macro.IdentifierImpl _buildIdentifier(Identifier node) {
    final String name;
    if (node is SimpleIdentifier) {
      name = node.name;
    } else {
      name = (node as PrefixedIdentifier).identifier.name;
    }
    return _IdentifierImpl(
      id: macro.RemoteInstance.uniqueId,
      name: name,
    );
  }

  static macro.TypeAnnotationImpl _buildTypeAnnotation(TypeAnnotation node) {
    if (node is NamedType) {
      return macro.NamedTypeAnnotationImpl(
        id: macro.RemoteInstance.uniqueId,
        identifier: _buildIdentifier(node.name),
        isNullable: node.question != null,
        typeArguments: _buildTypeAnnotations(node.typeArguments?.arguments),
      );
    } else {
      throw UnimplementedError('(${node.runtimeType}) $node');
    }
  }

  static List<macro.TypeAnnotationImpl> _buildTypeAnnotations(
    List<TypeAnnotation>? elements,
  ) {
    if (elements != null) {
      return elements.map(_buildTypeAnnotation).toList();
    } else {
      return const [];
    }
  }

  static macro.TypeParameterDeclarationImpl _buildTypeParameter(
    TypeParameter node,
  ) {
    return macro.TypeParameterDeclarationImpl(
      id: macro.RemoteInstance.uniqueId,
      identifier: _buildIdentifier(node.name),
      bound: node.bound?.mapOrNull(_buildTypeAnnotation),
    );
  }

  static List<macro.TypeParameterDeclarationImpl> _buildTypeParameters(
    TypeParameterList? typeParameterList,
  ) {
    if (typeParameterList != null) {
      return typeParameterList.typeParameters.map(_buildTypeParameter).toList();
    } else {
      return const [];
    }
  }
}

/// Helper class for evaluating arguments for a single constructor based
/// macro application.
class _ArgumentEvaluation {
  final int annotationIndex;
  final int argumentIndex;

  _ArgumentEvaluation({
    required this.annotationIndex,
    required this.argumentIndex,
  });

  Object? evaluate(Expression node) {
    if (node is AdjacentStrings) {
      return node.strings.map(evaluate).join('');
    } else if (node is BooleanLiteral) {
      return node.value;
    } else if (node is DoubleLiteral) {
      return node.value;
    } else if (node is IntegerLiteral) {
      return node.value;
    } else if (node is ListLiteral) {
      return node.elements.cast<Expression>().map(evaluate).toList();
    } else if (node is NullLiteral) {
      return null;
    } else if (node is PrefixExpression &&
        node.operator.type == TokenType.MINUS) {
      final operandValue = evaluate(node.operand);
      if (operandValue is double) {
        return -operandValue;
      } else if (operandValue is int) {
        return -operandValue;
      }
    } else if (node is SetOrMapLiteral) {
      final result = <Object?, Object?>{};
      for (final element in node.elements) {
        if (element is! MapLiteralEntry) {
          _throwError(element, 'MapLiteralEntry expected');
        }
        final key = evaluate(element.key);
        final value = evaluate(element.value);
        result[key] = value;
      }
      return result;
    } else if (node is SimpleStringLiteral) {
      return node.value;
    }
    _throwError(node, 'Not supported: ${node.runtimeType}');
  }

  Never _throwError(AstNode node, String message) {
    throw ArgumentMacroApplicationError(
      annotationIndex: annotationIndex,
      argumentIndex: argumentIndex,
      message: message,
    );
  }
}

class _FakeIdentifierResolver extends macro.IdentifierResolver {
  @override
  Future<macro.Identifier> resolveIdentifier(Uri library, String name) {
    // TODO: implement resolveIdentifier
    throw UnimplementedError();
  }
}

class _IdentifierImpl extends macro.IdentifierImpl {
  _IdentifierImpl({required int id, required String name})
      : super(id: id, name: name);
}

extension on macro.MacroExecutionResult {
  bool get isNotEmpty =>
      libraryAugmentations.isNotEmpty || classAugmentations.isNotEmpty;
}

extension _IfNotNull<T> on T? {
  R? mapOrNull<R>(R Function(T) mapper) {
    final self = this;
    return self != null ? mapper(self) : null;
  }
}
