import 'package:hive/hive.dart';

/// HTTP tabanli plugin tool — JSON ile tanimli, dis HTTP cagrisi yapar.
/// Kod calistirmaz, sadece HTTP (guvenli, sandbox'u delmez).
class HttpToolPlugin extends HiveObject {
  HttpToolPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.urlTemplate,
    required this.method,
    this.headers = const {},
    this.bodyTemplate,
    this.responseJsonPath,
    this.errorJsonPath,
    this.parameters = const {},
    this.enabled = true,
  });

  final String id;
  final String name; // tool function name, ornek: get_weather
  final String description;
  final String urlTemplate; // ornek: https://api.example.com/weather?city={{city}}
  final String method; // GET, POST, PUT, DELETE
  final Map<String, String> headers;
  final Map<String, dynamic>? bodyTemplate;
  final String? responseJsonPath; // ornek: data.result
  final String? errorJsonPath;
  final Map<String, dynamic> parameters; // JSON Schema properties
  bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'urlTemplate': urlTemplate,
        'method': method,
        'headers': headers,
        'bodyTemplate': bodyTemplate,
        'responseJsonPath': responseJsonPath,
        'errorJsonPath': errorJsonPath,
        'parameters': parameters,
        'enabled': enabled,
      };

  factory HttpToolPlugin.fromJson(Map<String, dynamic> json) => HttpToolPlugin(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        urlTemplate: json['urlTemplate'] as String? ?? json['url'] as String? ?? '',
        method: (json['method'] as String? ?? 'GET').toUpperCase(),
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        bodyTemplate: json['bodyTemplate'] as Map<String, dynamic>?,
        responseJsonPath: json['responseJsonPath'] as String?,
        errorJsonPath: json['errorJsonPath'] as String?,
        parameters: Map<String, dynamic>.from(json['parameters'] as Map? ?? {}),
        enabled: json['enabled'] as bool? ?? true,
      );

  /// OpenAI function calling formatina donustur
  Map<String, dynamic> toOpenAiToolJson() {
    final props = <String, dynamic>{};
    final required = <String>[];
    parameters.forEach((key, value) {
      if (value is String) {
        props[key] = {'type': value};
        required.add(key);
      } else if (value is Map) {
        props[key] = value;
      }
    });
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': props,
          'required': required,
        },
      },
    };
  }
}

class HttpToolPluginAdapter extends TypeAdapter<HttpToolPlugin> {
  @override
  final int typeId = 4;

  @override
  HttpToolPlugin read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return HttpToolPlugin(
      id: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String,
      urlTemplate: fields[3] as String,
      method: fields[4] as String,
      headers: Map<String, String>.from(fields[5] as Map? ?? {}),
      bodyTemplate: fields[6] == null ? null : Map<String, dynamic>.from(fields[6] as Map),
      responseJsonPath: fields[7] as String?,
      errorJsonPath: fields[8] as String?,
      parameters: Map<String, dynamic>.from(fields[9] as Map? ?? {}),
      enabled: fields[10] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, HttpToolPlugin obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.urlTemplate)
      ..writeByte(4)
      ..write(obj.method)
      ..writeByte(5)
      ..write(obj.headers)
      ..writeByte(6)
      ..write(obj.bodyTemplate)
      ..writeByte(7)
      ..write(obj.responseJsonPath)
      ..writeByte(8)
      ..write(obj.errorJsonPath)
      ..writeByte(9)
      ..write(obj.parameters)
      ..writeByte(10)
      ..write(obj.enabled);
  }
}
