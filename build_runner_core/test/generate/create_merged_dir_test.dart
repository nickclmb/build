// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:build_runner_core/src/asset_graph/graph.dart';
import 'package:build_runner_core/src/asset_graph/node.dart';
import 'package:build_runner_core/src/asset_graph/optional_output_tracker.dart';
import 'package:build_runner_core/src/generate/create_merged_dir.dart';
import 'package:build_runner_core/src/generate/phase.dart';

import 'package:_test_common/common.dart';
import 'package:_test_common/package_graphs.dart';
import 'package:_test_common/test_environment.dart';

main() {
  group('createMergedDir', () {
    AssetGraph graph;
    final phases = [
      new InBuildPhase(
          new TestBuilder(
              buildExtensions: appendExtension('.copy', from: '.txt')),
          'a'),
      new InBuildPhase(
          new TestBuilder(
              buildExtensions: appendExtension('.copy', from: '.txt')),
          'b')
    ];
    final sources = {
      makeAssetId('a|lib/a.txt'): 'a',
      makeAssetId('a|web/b.txt'): 'b',
      makeAssetId('b|lib/c.txt'): 'c',
      makeAssetId('a|foo/d.txt'): 'd',
    };
    final packageGraph = buildPackageGraph({
      rootPackage('a'): ['b'],
      package('b'): []
    });
    Directory tmpDir;
    Directory anotherTmpDir;
    TestBuildEnvironment environment;
    InMemoryRunnerAssetReader assetReader;
    OptionalOutputTracker optionalOutputTracker;

    setUp(() async {
      assetReader = new InMemoryRunnerAssetReader(sources);
      environment = new TestBuildEnvironment(reader: assetReader);
      graph = await AssetGraph.build(phases, sources.keys.toSet(),
          new Set<AssetId>(), packageGraph, assetReader);
      optionalOutputTracker = new OptionalOutputTracker(graph, [], phases);
      for (var id in graph.outputs) {
        var node = graph.get(id) as GeneratedAssetNode;
        node.state = GeneratedNodeState.upToDate;
        node.wasOutput = true;
        node.isFailure = false;
        assetReader.cacheStringAsset(id, sources[node.primaryInput]);
      }
      tmpDir = await Directory.systemTemp.createTemp('build_tests');
      anotherTmpDir = await Directory.systemTemp.createTemp('build_tests');
    });

    tearDown(() async {
      await tmpDir.delete(recursive: true);
    });

    test('creates a valid merged output directory', () async {
      var success = await createMergedOutputDirectories({tmpDir.path: null},
          graph, packageGraph, assetReader, environment, optionalOutputTracker);
      expect(success, isTrue);

      _expectAllFiles(tmpDir);
    });

    test('doesnt write deleted files', () async {
      var node =
          graph.get(new AssetId('b', 'lib/c.txt.copy')) as GeneratedAssetNode;
      node.deletedBy.add(node.id.addExtension('.post_anchor.1'));

      var success = await createMergedOutputDirectories({tmpDir.path: null},
          graph, packageGraph, assetReader, environment, optionalOutputTracker);
      expect(success, isTrue);

      var file = new File(p.join(tmpDir.path, 'packages/b/c.txt.copy'));
      expect(file.existsSync(), isFalse);
    });

    test('can create multiple merged directories', () async {
      var success = await createMergedOutputDirectories(
          {tmpDir.path: null, anotherTmpDir.path: null},
          graph,
          packageGraph,
          assetReader,
          environment,
          optionalOutputTracker);
      expect(success, isTrue);

      _expectAllFiles(tmpDir);
      _expectAllFiles(anotherTmpDir);
    });

    test('removes the provided root from the output path', () async {
      var success = await createMergedOutputDirectories({
        tmpDir.path: 'web',
      }, graph, packageGraph, assetReader, environment, optionalOutputTracker);
      expect(success, isTrue);

      var webFiles = <String, dynamic>{
        'b.txt': 'b',
        'b.txt.copy': 'b',
      };

      _expectFiles(webFiles, tmpDir);
    });

    test('does not output the input directory', () async {
      var success = await createMergedOutputDirectories({
        tmpDir.path: 'web',
      }, graph, packageGraph, assetReader, environment, optionalOutputTracker);
      expect(success, isTrue);

      expect(new Directory(p.join(tmpDir.path, 'web')).existsSync(), isFalse);
    });

    test('outputs the packages when input root is provided', () async {
      var success = await createMergedOutputDirectories(
          {tmpDir.path: 'web', anotherTmpDir.path: 'foo'},
          graph,
          packageGraph,
          assetReader,
          environment,
          optionalOutputTracker);
      expect(success, isTrue);

      var webFiles = <String, dynamic>{
        'packages/a/a.txt': 'a',
        'packages/a/a.txt.copy': 'a',
        'packages/b/c.txt': 'c',
        'packages/b/c.txt.copy': 'c',
        '.packages': 'a:packages/a/\r\nb:packages/b/\r\n\$sdk:packages/\$sdk/',
      };

      _expectFiles(webFiles, tmpDir);
    });

    test('only outputs files contained in the provided root', () async {
      var success = await createMergedOutputDirectories(
          {tmpDir.path: 'web', anotherTmpDir.path: 'foo'},
          graph,
          packageGraph,
          assetReader,
          environment,
          optionalOutputTracker);
      expect(success, isTrue);

      var webFiles = <String, dynamic>{
        'b.txt': 'b',
        'b.txt.copy': 'b',
      };

      var webNoFiles = new Set<String>()..addAll(['d.txt', 'd.txt.copy']);

      var fooFiles = <String, dynamic>{
        'd.txt': 'd',
        'd.txt.copy': 'd',
      };

      var fooNoFiles = new Set<String>()..addAll(['b.txt', 'b.txt.copy']);

      _expectFiles(webFiles, tmpDir);
      _expectNoFiles(webNoFiles, tmpDir);
      _expectFiles(fooFiles, anotherTmpDir);
      _expectNoFiles(fooNoFiles, anotherTmpDir);
    });

    test('doesnt write files that werent output', () async {
      var node =
          graph.get(new AssetId('b', 'lib/c.txt.copy')) as GeneratedAssetNode;
      node.wasOutput = false;
      node.isFailure = false;

      var success = await createMergedOutputDirectories({tmpDir.path: null},
          graph, packageGraph, assetReader, environment, optionalOutputTracker);
      expect(success, isTrue);

      var file = new File(p.join(tmpDir.path, 'packages/b/c.txt.copy'));
      expect(file.existsSync(), isFalse);
    });

    test('doesnt always write files not matching outputDirs', () async {
      var success = await createMergedOutputDirectories(
          {tmpDir.path: null},
          graph,
          packageGraph,
          assetReader,
          environment,
          new OptionalOutputTracker(graph, ['foo'], phases));
      expect(success, isTrue);

      var expectedFiles = <String, dynamic>{
        'foo/d.txt': 'd',
        'foo/d.txt.copy': 'd',
        'packages/a/a.txt': 'a',
        'packages/b/c.txt': 'c',
        'web/b.txt': 'b',
        '.packages': 'a:packages/a/\r\nb:packages/b/\r\n\$sdk:packages/\$sdk/',
      };
      _expectFiles(expectedFiles, tmpDir);
    });

    group('existing output dir handling', () {
      File garbageFile;
      Directory emptyDirectory;
      setUp(() {
        garbageFile = new File(p.join(tmpDir.path, 'garbage_file.txt'));
        garbageFile.createSync();
        emptyDirectory = new Directory(p.join(tmpDir.path, 'empty_directory'));
        emptyDirectory.createSync();
      });

      test('fails in non-interactive mode', () async {
        environment =
            new TestBuildEnvironment(reader: assetReader, throwOnPrompt: true);
        var success = await createMergedOutputDirectories(
            {tmpDir.path: null},
            graph,
            packageGraph,
            assetReader,
            environment,
            optionalOutputTracker);
        expect(success, isFalse);
      });

      test('can skip creating the directory', () async {
        environment.nextPromptResponse = 0;
        var success = await createMergedOutputDirectories(
            {tmpDir.path: null},
            graph,
            packageGraph,
            assetReader,
            environment,
            optionalOutputTracker);
        expect(success, isFalse,
            reason: 'Skipping creation of the directory should be considered a '
                'failure.');

        expect(garbageFile.existsSync(), isTrue,
            reason: 'Should not delete existing files.');
        var file = new File(p.join(tmpDir.path, 'web/b.txt'));
        expect(file.existsSync(), isFalse,
            reason: 'Should not copy any files.');
      });

      test('can delete the entire existing directory', () async {
        environment.nextPromptResponse = 1;
        var success = await createMergedOutputDirectories(
            {tmpDir.path: null},
            graph,
            packageGraph,
            assetReader,
            environment,
            optionalOutputTracker);
        expect(success, isTrue);

        expect(garbageFile.existsSync(), isFalse);
        _expectAllFiles(tmpDir);
      });

      test('can merge into the existing directory', () async {
        environment.nextPromptResponse = 2;
        var success = await createMergedOutputDirectories(
            {tmpDir.path: null},
            graph,
            packageGraph,
            assetReader,
            environment,
            optionalOutputTracker);
        expect(success, isTrue);

        expect(garbageFile.existsSync(), isTrue,
            reason: 'Existing files should be left alone.');
        expect(emptyDirectory.existsSync(), isTrue,
            reason: 'Does not remove existing empty directories.');
        _expectAllFiles(tmpDir);
      });
    });

    group('Empty directory cleanup', () {
      test('removes directories that become empty', () async {
        var success = await createMergedOutputDirectories(
            {tmpDir.path: null},
            graph,
            packageGraph,
            assetReader,
            environment,
            optionalOutputTracker);
        expect(success, isTrue);
        final removes = ['a|lib/a.txt', 'a|lib/a.txt.copy'];
        for (var remove in removes) {
          graph
              .get(makeAssetId(remove))
              .deletedBy
              .add(makeAssetId(remove).addExtension('.post_anchor.1'));
        }
        success = await createMergedOutputDirectories(
            {tmpDir.path: null},
            graph,
            packageGraph,
            assetReader,
            environment,
            optionalOutputTracker);
        expect(success, isTrue);
        var packageADir = p.join(tmpDir.path, 'packages', 'a');
        expect(new Directory(packageADir).existsSync(), isFalse);
      });
    });
  });
}

void _expectFiles(Map<String, dynamic> expectedFiles, Directory dir) {
  expectedFiles['.build.manifest'] =
      allOf(expectedFiles.keys.map(contains).toList());
  expectedFiles.forEach((path, content) {
    var file = new File(p.join(dir.path, path));
    expect(file.existsSync(), isTrue, reason: 'Missing file at $path.');
    expect(file.readAsStringSync(), content,
        reason: 'Incorrect content for file at $path');
  });
}

void _expectNoFiles(Set<String> expectedFiles, Directory dir) {
  for (var path in expectedFiles) {
    var file = new File(p.join(dir.path, path));
    expect(!file.existsSync(), isTrue, reason: 'File found at $path.');
  }
}

void _expectAllFiles(Directory dir) {
  var expectedFiles = <String, dynamic>{
    'foo/d.txt': 'd',
    'foo/d.txt.copy': 'd',
    'packages/a/a.txt': 'a',
    'packages/a/a.txt.copy': 'a',
    'packages/b/c.txt': 'c',
    'packages/b/c.txt.copy': 'c',
    'web/b.txt': 'b',
    'web/b.txt.copy': 'b',
    '.packages': 'a:packages/a/\r\nb:packages/b/\r\n\$sdk:packages/\$sdk/',
  };
  _expectFiles(expectedFiles, dir);
}
