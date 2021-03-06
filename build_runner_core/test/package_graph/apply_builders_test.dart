// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';

import 'package:build/build.dart';
import 'package:build_config/build_config.dart';
import 'package:test/test.dart';

import 'package:build_runner_core/src/generate/exceptions.dart';
import 'package:build_runner_core/src/generate/phase.dart';
import 'package:build_runner_core/src/package_graph/apply_builders.dart';
import 'package:build_runner_core/src/package_graph/target_graph.dart';

import 'package:_test_common/common.dart';
import 'package:_test_common/package_graphs.dart';

void main() {
  group('apply_builders.createBuildPhases', () {
    test('builderConfigOverrides overrides builder config globally', () async {
      var packageGraph = buildPackageGraph({
        rootPackage('a'): ['b'],
        package('b'): []
      });
      var targetGraph = await TargetGraph.forPackageGraph(packageGraph);
      var builderApplications = [
        apply('b|cool_builder', [(options) => new CoolBuilder(options)],
            toAllPackages())
      ];
      var phases = await createBuildPhases(
          targetGraph,
          builderApplications,
          {
            'b|cool_builder': {'option_a': 'a', 'option_c': 'c'},
          },
          false);
      for (InBuildPhase phase in phases) {
        expect((phase.builder as CoolBuilder).optionA, equals('a'));
        expect((phase.builder as CoolBuilder).optionB, equals('defaultB'));
        expect((phase.builder as CoolBuilder).optionC, equals('c'));
      }
    });

    test('applies root package global options before builderConfigOverrides',
        () async {
      var packageGraph = buildPackageGraph({
        rootPackage('a'): ['b'],
        package('b'): []
      });
      await runInBuildConfigZone(() async {
        var overrides = {
          'a': new BuildConfig(
            packageName: 'a',
            buildTargets: {
              'a:a': new BuildTarget(dependencies: new Set.of(['b:b']))
            },
            globalOptions: {
              'b|cool_builder': new GlobalBuilderConfig(
                options: const BuilderOptions(
                    const {'option_a': 'global a', 'option_b': 'global b'}),
                releaseOptions: const BuilderOptions(
                    const {'option_b': 'release global b'}),
              ),
            },
          )
        };
        var targetGraph = await TargetGraph.forPackageGraph(packageGraph,
            overrideBuildConfig: overrides);
        var builderApplications = [
          apply('b|cool_builder', [(options) => new CoolBuilder(options)],
              toAllPackages())
        ];
        var phases = await createBuildPhases(
            targetGraph,
            builderApplications,
            {
              'b|cool_builder': {'option_c': '--define c'},
            },
            true);
        for (InBuildPhase phase in phases) {
          expect((phase.builder as CoolBuilder).optionA, equals('global a'));
          expect((phase.builder as CoolBuilder).optionB,
              equals('release global b'));
          expect((phase.builder as CoolBuilder).optionC, equals('--define c'));
        }
      }, packageGraph.root.name,
          packageGraph.root.dependencies.map((node) => node.name).toList());
    });

    test('honors package filter', () async {
      var packageGraph = buildPackageGraph({
        rootPackage('a'): ['b'],
        package('b'): [],
      });
      var targetGraph = await TargetGraph.forPackageGraph(packageGraph);
      var builderApplications = [
        apply('b|cool_builder', [(options) => new CoolBuilder(options)],
            toDependentsOf('b')),
      ];
      var phases =
          await createBuildPhases(targetGraph, builderApplications, {}, false);
      expect(phases, hasLength(1));
      expect((phases.first as InBuildPhase).package, 'a');
    });

    test('honors appliesBuilders', () async {
      var packageGraph = buildPackageGraph({
        rootPackage('a'): ['b'],
        package('b'): [],
      });
      var targetGraph = await TargetGraph.forPackageGraph(packageGraph);
      var builderApplications = [
        apply('b|cool_builder', [(options) => new CoolBuilder(options)],
            toDependentsOf('b'),
            appliesBuilders: ['b|not_by_default']),
        apply(
            'b|not_by_default', [(_) => new TestBuilder()], toNoneByDefault()),
      ];
      var phases =
          await createBuildPhases(targetGraph, builderApplications, {}, false);
      expect(phases, hasLength(2));
      expect(phases.map((a) => (a as InBuildPhase).package), ['a', 'a']);
    });

    test('returns empty phases if a dependency is missing', () async {
      var packageGraph = buildPackageGraph({
        rootPackage('a'): ['b'],
        package('b'): [],
      });
      await runInBuildConfigZone(() async {
        var overrides = {
          'a': new BuildConfig(
            packageName: 'a',
            buildTargets: {
              'a:a':
                  new BuildTarget(dependencies: new Set.of(['b:not_default']))
            },
          )
        };
        var targetGraph = await TargetGraph.forPackageGraph(packageGraph,
            overrideBuildConfig: overrides);
        var builderApplications = [
          apply('b|cool_builder', [(options) => new CoolBuilder(options)],
              toAllPackages()),
        ];
        expect(
            () =>
                createBuildPhases(targetGraph, builderApplications, {}, false),
            throwsA(new TypeMatcher<CannotBuildException>()));
      }, packageGraph.root.name,
          packageGraph.root.dependencies.map((node) => node.name).toList());
    });
  });
}

class CoolBuilder extends Builder {
  final String optionA;
  final String optionB;
  final String optionC;

  CoolBuilder(BuilderOptions options)
      : optionA = options.config['option_a'] as String ?? 'defaultA',
        optionB = options.config['option_b'] as String ?? 'defaultB',
        optionC = options.config['option_c'] as String ?? 'defaultC';

  @override
  final buildExtensions = {
    '.txt': ['.out'],
  };

  @override
  Future build(BuildStep buildStep) async => throw new UnimplementedError();
}
