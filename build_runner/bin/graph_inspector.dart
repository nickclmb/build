// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'package:build_runner/src/asset_graph/graph.dart';
import 'package:build_runner/src/asset_graph/node.dart';
import 'package:build_runner/src/package_graph/package_graph.dart';
import 'package:build_runner/src/util/constants.dart';

AssetGraph assetGraph;
PackageGraph packageGraph;

Future main(List<String> args) async {
  stdout.writeln(
      'Warning: this tool is unsupported and usage may change at any time, '
      'use at your own risk.');

  if (args.length != 1) {
    throw new ArgumentError(
        'Expected exactly one argument, the path to a build script to '
        'analyze.');
  }

  var parser = new ArgParser()
    ..addOption('graph-path');

  var mainArgs = parser.parse(args);

  File assetGraphFile;
  if (!mainArgs.options.contains('graph-path')) {
    var scriptPath = mainArgs.arguments.first;
    var scriptFile = new File(scriptPath);
    if (!scriptFile.existsSync()) {
      throw new ArgumentError(
          'Expected a build script at $scriptPath but didn\'t find one.');
    }

    assetGraphFile = new File(assetGraphPathFor(p.absolute(scriptPath)));
    if (!assetGraphFile.existsSync()) {
      throw new ArgumentError(
          'Unable to find AssetGraph for $scriptPath at ${assetGraphFile
              .path}');
    }
  } else {
    assetGraphFile = new File(mainArgs['graph-path'] as String);
    if (!assetGraphFile.existsSync()) {
      throw new ArgumentError(
          'Unable to find AssetGraph at ${assetGraphFile.path}');
    }
  }
  stdout.writeln('Loading asset graph at ${assetGraphFile.path}...');

  assetGraph = new AssetGraph.deserialize(assetGraphFile.readAsBytesSync());
  packageGraph = new PackageGraph.forThisPackage();

  var commandRunner = new CommandRunner(
      '', 'A tool for inspecting the AssetGraph for your build')
    ..addCommand(new InspectNodeCommand())
    ..addCommand(new GraphCommand())
    ..addCommand(new QueryCommand());

  stdout.writeln('Ready, please type in a command:');

  while (true) {
    stdout.writeln('');
    stdout.write('> ');
    var nextCommand = stdin.readLineSync();
    stdout.writeln('');
    try {
      await commandRunner.run(nextCommand.split(' '));
    } on UsageException catch(e) {
      stdout.writeln('Unrecognized option ${e.usage}');
      await commandRunner.run(['help']);
    }
  }
}

class InspectNodeCommand extends Command {
  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Lists all the information about an asset using a relative or package: uri';

  @override
  String get invocation => '${super.invocation} <dart-uri>';

  InspectNodeCommand() {
    argParser.addFlag('verbose', abbr: 'v');
  }

  @override
  run() {
    var stringUris = argResults.rest;
    if (stringUris.isEmpty) {
      stderr.writeln('Expected at least one uri for a node to inspect.');
    }
    for (var stringUri in stringUris) {
      var id = _idFromString(stringUri);
      if (id == null) {
        continue;
      }
      var node = assetGraph.get(id);
      if (node == null) {
        stderr.writeln('Unable to find an asset node for $stringUri.');
        continue;
      }

      var description = new StringBuffer()
        ..writeln('Asset: $stringUri')
        ..writeln('  type: ${node.runtimeType}');

      if (node is GeneratedAssetNode) {
        description.writeln('  state: ${node.state}');
        description.writeln('  wasOutput: ${node.wasOutput}');
        description.writeln('  phase: ${node.phaseNumber}');
        description.writeln('  isFailure: ${node.isFailure}');
      }

      _printAsset(AssetId asset) =>
          _listAsset(asset, description, indentation: '    ');

      if (argResults['verbose'] == true) {
        description.writeln('  primary outputs:');
        node.primaryOutputs.forEach(_printAsset);

        description.writeln('  secondary outputs:');
        node.outputs.difference(node.primaryOutputs).forEach(_printAsset);

        if (node is GeneratedAssetNode) {
          description.writeln('  inputs:');
          var inputs = assetGraph.allNodes
              .where((n) => n.outputs.contains(node.id))
              .map((n) => n.id);
          inputs.forEach(_printAsset);
        }
      }

      stdout.write(description);
    }
  }
}

class GraphCommand extends Command {
  @override
  String get name => 'graph';

  @override
  String get description => 'Lists all the nodes in the graph.';

  @override
  String get invocation => '${super.invocation} <dart-uri>';

  GraphCommand() {
    argParser.addFlag('generated',
        abbr: 'g', help: 'Show only generated assets.', defaultsTo: false);
    argParser.addFlag('original',
        abbr: 'o',
        help: 'Show only original source assets.',
        defaultsTo: false);
    argParser.addOption('package',
        abbr: 'p', help: 'Filters nodes to a certain package');
    argParser.addOption('pattern',
        abbr: 'm', help: 'glob pattern for path matching');
  }

  @override
  run() {
    var showGenerated = argResults['generated'] as bool;
    var showSources = argResults['original'] as bool;
    Iterable<AssetId> assets;
    if (showGenerated) {
      assets = assetGraph.outputs;
    } else if (showSources) {
      assets = assetGraph.sources;
    } else {
      assets = assetGraph.allNodes.map((n) => n.id);
    }

    var package = argResults['package'] as String;
    if (package != null) {
      assets = assets.where((id) => id.package == package);
    }

    var pattern = argResults['pattern'] as String;
    if (pattern != null) {
      var glob = new Glob(pattern);
      assets = assets.where((id) => glob.matches(id.path));
    }

    for (var id in assets) {
      _listAsset(id, stdout, indentation: '  ');
    }
  }
}


class QueryCommand extends Command {
  @override
  String get name => 'query';

  @override
  String get description => 'Lists nodes in graph by specified filters and shows requested fields.';

  @override
  String get invocation => '${super.invocation} <dart-uri>';

  QueryCommand() {
    argParser.addFlag('generated',
        abbr: 'g', help: 'Show only generated assets.', defaultsTo: false);
    argParser.addFlag('original',
        abbr: 'o',
        help: 'Show only original source assets.',
        defaultsTo: false);
    argParser.addOption('package',
        abbr: 'p', help: 'Filters nodes to a certain package');
    argParser.addOption('pattern',
        abbr: 'm', help: 'glob pattern for path matching');
    argParser.addOption('take', defaultsTo: '0',
        help: 'limit output qty');
    argParser.addOption('skip', defaultsTo: '0',
        help: 'skip first number of rows');
    argParser.addOption('sort',
        allowed: ['asset', 'inputs-qty', 'upstream-tree-qty'],
        defaultsTo: 'asset',
        help: 'sort output by field. Allowed options');
    argParser.addFlag('desc',
        help: 'sort output descending');
    argParser.addFlag('json',
        help: 'output as json');
    argParser.addOption('out',
        help: 'path to save data');
    argParser.addMultiOption('packages',
        help: 'path to save data');
    argParser.addMultiOption('select',
        allowed: ['asset', 'inputs-qty', 'inputs', 'upstream-tree-qty', 'upstream-tree'],
        defaultsTo: ['asset'],
        help: 'list of fields to select');
  }

  @override
  run() async {
    var showGenerated = argResults['generated'] as bool;
    var showSources = argResults['original'] as bool;
    Iterable<AssetNode> assetNodes;
    if (showGenerated) {
      assetNodes = assetGraph.allNodes.where((node) => node.isGenerated);
    } else if (showSources) {
      assetNodes = assetGraph.allNodes.where((n) => n is SourceAssetNode);
    } else {
      assetNodes = assetGraph.allNodes;
    }

    var package = argResults['package'] as String;
    if (package != null) {
      assetNodes = assetNodes.where((node) => node.id.package == package);
    }

    var packages = argResults['packages'] as List<String>;
    if (packages != null && packages.isNotEmpty) {
      assetNodes = assetNodes.where((node) => packages.contains(node.id.package));
    }

    var pattern = argResults['pattern'] as String;
    if (pattern != null) {
      var glob = new Glob(pattern);
      assetNodes = assetNodes.where((node) => glob.matches(node.id.path));
    }


    var isDesc = argResults['desc'] as bool;
    var sort = argResults['sort'] as String;
    if (sort == 'inputs-qty') {
      assetNodes = assetNodes.toList()
        ..sort(_getSortFunction(isDesc, _getInputs));
    }


    var skip = int.parse(argResults['skip'] as String);
    if (skip > 0) {
      assetNodes = assetNodes.skip(skip);
    }

    var take = int.parse(argResults['take'] as String);
    if (take > 0) {
      assetNodes = assetNodes.take(take);
    }

    var selects = argResults['select'] as List<String>;
    var isJson = argResults['json'] as bool;
    var outputPath = argResults['out'] as String;
    var needFreeResource = false;
    IOSink output = stdout;
    try {
      if (outputPath != null && outputPath != '') {
        var outputFile = new File(p.absolute(outputPath));
        if (outputFile.existsSync()) {
          outputFile.deleteSync();
        }
        outputFile.createSync(recursive: true);
        output = outputFile.openWrite();
        needFreeResource = true;
      }
      if (isJson) {
        output.write('[');
      }
      for (var node in assetNodes) {
        _listNode(node, output, indentation: '  ', selects: selects, isJson: isJson);
      }
      if (isJson) {
        output.write(']');
      }
    } finally {
      if (needFreeResource) {
        await output.flush()
            .whenComplete(() => output.close());
      }
    }
  }
}

typedef int _AssetIdSortFunction(AssetNode left, AssetNode right);
_AssetIdSortFunction _getSortFunction(bool isDescending, int getValueFunc(AssetNode asset)) {
  return (AssetNode left, AssetNode right) => (isDescending ? -1 : 1) * (getValueFunc(left) - getValueFunc(right));
}

int _getInputs(AssetNode asset) {
  if (asset is GeneratedAssetNode) {
    return asset.inputs.where((AssetId asset) => _wrikePackages.contains(asset.package)).length;
  } else {
    return 0;
  }
}

AssetId _idFromString(String stringUri) {
  var uri = Uri.parse(stringUri);
  if (uri.scheme == 'package') {
    return new AssetId(uri.pathSegments.first,
        p.url.join('lib', p.url.joinAll(uri.pathSegments.skip(1))));
  } else if (!uri.isAbsolute && (uri.scheme == '' || uri.scheme == 'file')) {
    return new AssetId(packageGraph.root.name, uri.path);
  } else {
    stderr.writeln('Unrecognized uri $uri, must be a package: uri or a '
        'relative path.');
    return null;
  }
}

_listNode(AssetNode output, StringSink buffer, {String indentation: '  ', Iterable<String> selects, bool isJson = false}) {
//  buffer.write('$indentation');
  final multilineSelects = <String>[];
  if (isJson) {
    buffer.write('{');
  }
  for (var select in selects) {
    if (_isMultilineSelect(select)) {
      multilineSelects.add(select);
    } else {
      if (isJson) {
        buffer.write('${JSON.encode(select)}: ${JSON.encode(_getAssetField(output, select))},');
      } else {
        buffer.write('$indentation${_getAssetField(output, select)}');
      }
    }
  }

  for (var select in multilineSelects) {
    if (isJson) {
      buffer.write('${JSON.encode(select)}: [');
    }
    for (var line in _getMultilineAssetFields(output, select)) {
      if (isJson) {
        buffer.write('${JSON.encode(line)},');
      } else {
        buffer.writeln('$indentation$indentation$line');
      }
    }

    if (isJson) {
      buffer.write('],');
    }
  }
  if (isJson) {
    buffer.write('},');
  } else {
    buffer.write('\n');
  }
}

bool _isMultilineSelect(String select) {
  return ['inputs', 'upstream-tree'].contains(select);
}

String _getAssetField(AssetNode node, String select) {
  if (select == 'asset') {
    var outputUri = node.id.uri;
    if (outputUri.scheme == 'package') {
      return node.id.uri.toString();
    } else {
      return node.id.path;
    }
  } else if (select == 'inputs-qty') {
    if (node is GeneratedAssetNode) {
      return node.inputs.length.toString();
    } else {
      return '0';
    }
  } else if (select == 'upstream-tree-qty') {

    if (node is GeneratedAssetNode) {
      return assetGraph.allNodes.where((n) {
        if (n is GeneratedAssetNode) {
          return n.inputs.any((i) => i == node.id);
        }
        return false;
      }).length.toString();
    } else {
      return '0';
    }
  }

  return '';
}

final _wrikePackages = [
  "spellchecker",
  "request_monitor",
  "wrike_performance_logger",
  "http_adaptors",
  "wrike_dal_i18n",
  "wrike_dal",
  "wrike_dal_core",
  "wrike_components",
  "mvp_inbox",
  "mvp_proofing",
  "mvp_mywork",
  "mvp_report",
  "mvp_le2_frontend",
  "resource_loader",
  "experiment_manager",
  "onboarding_components",
  "le_widget",
  "wrike_board",
  "wrike_timeline",
  "wrike_overview",
  "wrike_forms_core",
  "wrike_user_environment",
  "wtalk_lib",
  "wrike_attachments",
  "wrike_task_list",
  "wrike_notification_service",
  "wrike_qff",
  "wrike_calendar_app",
  "wrike_timelog_view",
  "wrike_dragdrop",
  "wrike_recurrence",
  "wrike_space_components",
  "wrike_space_api",
  "wrike_table_view",
  "wrike_tether",
  "wrike_task_view",
  "wrike_user_profile_menu",
  "wrike_commons",
];
Iterable<String> _getMultilineAssetFields(AssetNode node, String select) sync* {
  if (select == 'inputs') {
    if (node is GeneratedAssetNode) {
      var sortedInputs = node.inputs
          .where((AssetId asset) => _wrikePackages.contains(asset.package))
          .toList()
        ..sort((AssetId asset1, AssetId asset2) => asset1.package.compareTo(asset2.package));
      yield* sortedInputs.map((id) => id.toString());
    }
  } else if (select == 'upstream-tree') {
    var sortedList = assetGraph.allNodes.where((n) {
      if (n is GeneratedAssetNode) {
        return n.inputs.any((i) => i == node.id);
      }
      return false;
    })
        .map((n) => n.id)
        .toList()
      ..sort((AssetId asset1, AssetId asset2) => asset1.package.compareTo(asset2.package));

    yield* sortedList.map((id) => id.toString());
  }
}

_listAsset(AssetId output, StringSink buffer, {String indentation: '  '}) {
  var outputUri = output.uri;
  if (outputUri.scheme == 'package') {
    buffer.writeln('$indentation${output.uri}');
  } else {
    buffer.writeln('$indentation${output.path}');
  }
}
