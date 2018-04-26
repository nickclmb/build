// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meta_module.dart';

// **************************************************************************
// Generator: JsonSerializableGenerator
// **************************************************************************

MetaModule _$MetaModuleFromJson(Map<String, dynamic> json) =>
    new MetaModule((json['m'] as List)
        .map((e) => new Module.fromJson(e as Map<String, dynamic>)));

abstract class _$MetaModuleSerializerMixin {
  Set<Module> get modules;
  Map<String, dynamic> toJson() => <String, dynamic>{'m': modules.toList()};
}
