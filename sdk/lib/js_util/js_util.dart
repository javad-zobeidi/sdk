// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Utility methods to manipulate `package:js` annotated JavaScript interop
/// objects in cases where the name to call is not known at runtime.
///
/// You should only use these methods when the same effect cannot be achieved
/// with `@JS()` annotations.
///
/// {@category Web}
library dart.js_util;

import 'dart:_foreign_helper' show JS;
import 'dart:collection' show HashMap;
import 'dart:async' show Completer;
import 'dart:_js_helper'
    show convertDartClosureToJS, assertInterop, assertInteropArgs;

/// Recursively converts a JSON-like collection to JavaScript compatible
/// representation.
///
/// WARNING: performance of this method is much worse than other util
/// methods in this library. Only use this method as a last resort. Prefer
/// instead to use `@anonymous` `@JS()` annotated classes to create map-like
/// objects for JS interop.
///
/// The argument must be a [Map] or [Iterable], the contents of which are also
/// deeply converted. Maps are converted into JavaScript objects. Iterables are
/// converted into arrays. Strings, numbers, bools, and `@JS()` annotated
/// objects are passed through unmodified. Dart objects are also passed through
/// unmodified, but their members aren't usable from JavaScript.
dynamic jsify(Object object) {
  if ((object is! Map) && (object is! Iterable)) {
    throw ArgumentError("object must be a Map or Iterable");
  }
  return _convertDataTree(object);
}

Object _convertDataTree(Object data) {
  var _convertedObjects = HashMap.identity();

  Object? _convert(Object? o) {
    if (_convertedObjects.containsKey(o)) {
      return _convertedObjects[o];
    }
    if (o is Map) {
      final convertedMap = JS('=Object', '{}');
      _convertedObjects[o] = convertedMap;
      for (var key in o.keys) {
        JS('=Object', '#[#]=#', convertedMap, key, _convert(o[key]));
      }
      return convertedMap;
    } else if (o is Iterable) {
      var convertedList = [];
      _convertedObjects[o] = convertedList;
      convertedList.addAll(o.map(_convert));
      return convertedList;
    } else {
      return o;
    }
  }

  return _convert(data)!;
}

@pragma('dart2js:tryInline')
Object get globalThis => JS('', 'globalThis');

T newObject<T>() => JS('=Object', '{}');

bool hasProperty(Object o, Object name) => JS('bool', '# in #', name, o);

T getProperty<T>(Object o, Object name) =>
    JS<dynamic>('Object|Null', '#[#]', o, name);

// A CFE transformation may optimize calls to `setProperty`, when [value] is
// statically known to be a non-function.
T setProperty<T>(Object o, Object name, T? value) {
  assertInterop(value);
  return JS('', '#[#]=#', o, name, value);
}

/// Unchecked version of setProperty, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _setPropertyUnchecked<T>(Object o, Object name, T? value) {
  return JS('', '#[#]=#', o, name, value);
}

// A CFE transformation may optimize calls to `callMethod` when [args] is a
// a list literal or const list containing at most 4 values, all of which are
// statically known to be non-functions.
T callMethod<T>(Object o, String method, List<Object?> args) {
  assertInteropArgs(args);
  return JS<dynamic>('Object|Null', '#[#].apply(#, #)', o, method, o, args);
}

/// Unchecked version for 0 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callMethodUnchecked0<T>(Object o, String method) {
  return JS<dynamic>('Object|Null', '#[#]()', o, method);
}

/// Unchecked version for 1 argument, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callMethodUnchecked1<T>(Object o, String method, Object? arg1) {
  return JS<dynamic>('Object|Null', '#[#](#)', o, method, arg1);
}

/// Unchecked version for 2 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callMethodUnchecked2<T>(
    Object o, String method, Object? arg1, Object? arg2) {
  return JS<dynamic>('Object|Null', '#[#](#, #)', o, method, arg1, arg2);
}

/// Unchecked version for 3 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callMethodUnchecked3<T>(
    Object o, String method, Object? arg1, Object? arg2, Object? arg3) {
  return JS<dynamic>(
      'Object|Null', '#[#](#, #, #)', o, method, arg1, arg2, arg3);
}

/// Unchecked version for 4 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callMethodUnchecked4<T>(Object o, String method, Object? arg1, Object? arg2,
    Object? arg3, Object? arg4) {
  return JS<dynamic>(
      'Object|Null', '#[#](#, #, #, #)', o, method, arg1, arg2, arg3, arg4);
}

/// Check whether [o] is an instance of [type].
///
/// The value in [type] is expected to be a JS-interop object that
/// represents a valid JavaScript constructor function.
bool instanceof(Object? o, Object type) =>
    JS('bool', '# instanceof #', o, type);

T callConstructor<T>(Object constr, List<Object?>? arguments) {
  if (arguments == null) {
    return JS<dynamic>('Object', 'new #()', constr);
  } else {
    assertInteropArgs(arguments);
  }

  if (JS('bool', '# instanceof Array', arguments)) {
    int argumentCount = JS('int', '#.length', arguments);
    switch (argumentCount) {
      case 0:
        return JS<dynamic>('Object', 'new #()', constr);

      case 1:
        var arg0 = JS('', '#[0]', arguments);
        return JS<dynamic>('Object', 'new #(#)', constr, arg0);

      case 2:
        var arg0 = JS('', '#[0]', arguments);
        var arg1 = JS('', '#[1]', arguments);
        return JS<dynamic>('Object', 'new #(#, #)', constr, arg0, arg1);

      case 3:
        var arg0 = JS('', '#[0]', arguments);
        var arg1 = JS('', '#[1]', arguments);
        var arg2 = JS('', '#[2]', arguments);
        return JS<dynamic>(
            'Object', 'new #(#, #, #)', constr, arg0, arg1, arg2);

      case 4:
        var arg0 = JS('', '#[0]', arguments);
        var arg1 = JS('', '#[1]', arguments);
        var arg2 = JS('', '#[2]', arguments);
        var arg3 = JS('', '#[3]', arguments);
        return JS<dynamic>(
            'Object', 'new #(#, #, #, #)', constr, arg0, arg1, arg2, arg3);
    }
  }

  // The following code solves the problem of invoking a JavaScript
  // constructor with an unknown number arguments.
  // First bind the constructor to the argument list using bind.apply().
  // The first argument to bind() is the binding of 't', so add 'null' to
  // the arguments list passed to apply().
  // After that, use the JavaScript 'new' operator which overrides any binding
  // of 'this' with the new instance.
  var args = <dynamic>[null]..addAll(arguments);
  var factoryFunction = JS('', '#.bind.apply(#, #)', constr, constr, args);
  // Without this line, calling factoryFunction as a constructor throws
  JS('String', 'String(#)', factoryFunction);
  // This could return an UnknownJavaScriptObject, or a native
  // object for which there is an interceptor
  return JS<dynamic>('Object', 'new #()', factoryFunction);

  // TODO(sra): Investigate:
  //
  //     var jsObj = JS('', 'Object.create(#.prototype)', constr);
  //     JS('', '#.apply(#, #)', constr, jsObj,
  //         []..addAll(arguments.map(_convertToJS)));
  //     return _wrapToDart(jsObj);
}

/// Unchecked version for 0 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callConstructorUnchecked0<T>(Object constr) {
  return JS<dynamic>('Object', 'new #()', constr);
}

/// Unchecked version for 1 argument, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callConstructorUnchecked1<T>(Object constr, Object? arg1) {
  return JS<dynamic>('Object', 'new #(#)', constr, arg1);
}

/// Unchecked version for 2 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callConstructorUnchecked2<T>(Object constr, Object? arg1, Object? arg2) {
  return JS<dynamic>('Object', 'new #(#, #)', constr, arg1, arg2);
}

/// Unchecked version for 3 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callConstructorUnchecked3<T>(
    Object constr, Object? arg1, Object? arg2, Object? arg3) {
  return JS<dynamic>('Object', 'new #(#, #, #)', constr, arg1, arg2, arg3);
}

/// Unchecked version for 4 arguments, only used in a CFE transformation.
@pragma('dart2js:tryInline')
T _callConstructorUnchecked4<T>(
    Object constr, Object? arg1, Object? arg2, Object? arg3, Object? arg4) {
  return JS<dynamic>(
      'Object', 'new #(#, #, #, #)', constr, arg1, arg2, arg3, arg4);
}

/// Exception for when the promise is rejected with a `null` or `undefined`
/// value.
///
/// This is public to allow users to catch when the promise is rejected with
/// `null` or `undefined` versus some other value.
class NullRejectionException implements Exception {
  // Indicates whether the value is `undefined` or `null`.
  final bool isUndefined;

  NullRejectionException._(this.isUndefined);

  @override
  String toString() {
    var value = this.isUndefined ? 'undefined' : 'null';
    return 'Promise was rejected with a value of `$value`.';
  }
}

/// Converts a JavaScript Promise to a Dart [Future].
///
/// ```dart template:top
/// @JS()
/// external Promise<num> get threePromise; // Resolves to 3
///
/// final Future<num> threeFuture = promiseToFuture(threePromise);
///
/// final three = await threeFuture; // == 3
/// ```
Future<T> promiseToFuture<T>(Object jsPromise) {
  final completer = Completer<T>();

  final success = convertDartClosureToJS((r) => completer.complete(r), 1);
  final error = convertDartClosureToJS((e) {
    // Note that `completeError` expects a non-nullable error regardless of
    // whether null-safety is enabled, so a `NullRejectionException` is always
    // provided if the error is `null` or `undefined`.
    if (e == null) {
      return completer.completeError(
          NullRejectionException._(JS('bool', '# === undefined', e)));
    }
    return completer.completeError(e);
  }, 1);

  JS('', '#.then(#, #)', jsPromise, success, error);
  return completer.future;
}
