import 'dart:convert';

/// Content-warning classification used by Mihon-compatible repository metadata.
enum MihonContentWarning { unspecified, safe, mixed, nsfw }

class MihonRepositoryContact {
  const MihonRepositoryContact({this.website, this.discord});
  final String? website;
  final String? discord;
}

class MihonSourceRecord {
  const MihonSourceRecord({
    required this.id,
    required this.name,
    required this.language,
    this.homeUrl,
    this.mirrorUrls = const [],
    this.message,
  });

  final int id;
  final String name;
  final String language;
  final Uri? homeUrl;
  final List<Uri> mirrorUrls;
  final String? message;
}

class MihonExtensionResources {
  const MihonExtensionResources({this.apkUrl, this.iconUrl, this.jarUrl});
  final Uri? apkUrl;
  final Uri? iconUrl;
  final Uri? jarUrl;
}

class MihonExtensionRecord {
  const MihonExtensionRecord({
    required this.name,
    required this.packageName,
    required this.resources,
    required this.versionCode,
    required this.versionName,
    required this.contentWarning,
    required this.sources,
    this.extensionLib,
  });

  final String name;
  final String packageName;
  final MihonExtensionResources resources;
  final String? extensionLib;
  final int versionCode;
  final String versionName;
  final MihonContentWarning contentWarning;
  final List<MihonSourceRecord> sources;
}

/// Parsed metadata from a Mihon/Tachiyomi-style protobuf repository index.
///
/// This parser only reads repository metadata. It does not verify APK signing
/// keys and does not make compiled Android extensions executable in KuroToon.
class MihonRepositoryIndex {
  const MihonRepositoryIndex({
    required this.name,
    required this.badgeLabel,
    required this.signingKey,
    required this.contact,
    required this.extensions,
    this.extensionListUrl,
  });

  final String name;
  final String badgeLabel;
  final String signingKey;
  final MihonRepositoryContact? contact;
  final List<MihonExtensionRecord> extensions;
  final Uri? extensionListUrl;

  bool get hasExternalExtensionList => extensionListUrl != null;
  int get sourceCount => extensions.fold<int>(0, (sum, extension) => sum + extension.sources.length);

  factory MihonRepositoryIndex.parse(
    List<int> bytes, {
    required Uri indexUri,
    int maxBytes = 4 * 1024 * 1024,
    int maxExtensions = 100000,
  }) {
    if (bytes.length > maxBytes) {
      throw FormatException('Mihon repository index exceeds the configured byte limit.');
    }
    final fields = _ProtoReader(bytes).readAll();
    var name = '';
    var badgeLabel = '';
    var signingKey = '';
    MihonRepositoryContact? contact;
    List<MihonExtensionRecord> extensions = const [];
    Uri? extensionListUrl;
    var hasExtensionListChoice = false;

    for (final field in fields) {
      switch (field.number) {
        case 1:
          name = _stringField(field, 'repository name');
          break;
        case 2:
          badgeLabel = _stringField(field, 'badge label');
          break;
        case 3:
          signingKey = _stringField(field, 'signing key');
          break;
        case 4:
          contact = _parseContact(_bytesField(field, 'contact'));
          break;
        case 101:
          final list = _parseExtensionList(_bytesField(field, 'extension list'), maxExtensions: maxExtensions);
          extensions = list;
          extensionListUrl = null;
          hasExtensionListChoice = true;
          break;
        case 102:
          final rawUrl = _stringField(field, 'extension list URL');
          final uri = indexUri.resolve(rawUrl);
          if (!uri.isAbsolute || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
              (uri.hasPort && uri.port != 443) || uri.hasFragment) {
            throw const FormatException('Mihon extension-list URL must be a clean HTTPS URL.');
          }
          extensionListUrl = uri;
          extensions = const [];
          hasExtensionListChoice = true;
        default:
          break;
      }
    }

    if (name.trim().isEmpty || signingKey.trim().isEmpty || !hasExtensionListChoice) {
      throw const FormatException('Mihon index is missing its repository name, signing key, or extension list.');
    }
    return MihonRepositoryIndex(
      name: name,
      badgeLabel: badgeLabel,
      signingKey: signingKey,
      contact: contact,
      extensions: List.unmodifiable(extensions),
      extensionListUrl: extensionListUrl,
    );
  }

  /// Streams records from an externally hosted ExtensionList protobuf payload.
  /// The byte payload is bounded, but decoded records are yielded one at a time
  /// so callers can persist large catalogs in batches without retaining them all.
  static Iterable<MihonExtensionRecord> decodeExtensionList(
    List<int> bytes, {
    int maxBytes = 16 * 1024 * 1024,
    int maxExtensions = 100000,
  }) sync* {
    if (bytes.length > maxBytes) {
      throw FormatException('Mihon extension list exceeds the configured byte limit.');
    }
    var count = 0;
    for (final field in _ProtoReader(bytes).readFields()) {
      if (field.number != 1) continue;
      if (field.wireType != 2) throw const FormatException('Mihon extension entry has an invalid wire type.');
      if (count >= maxExtensions) throw FormatException('Mihon extension list exceeds $maxExtensions entries.');
      count++;
      yield _parseExtension(field.bytes!);
    }
  }

  /// Convenience parser for callers that intentionally need the full list.
  static List<MihonExtensionRecord> parseExtensionList(
    List<int> bytes, {
    int maxBytes = 16 * 1024 * 1024,
    int maxExtensions = 100000,
  }) => List.unmodifiable(decodeExtensionList(
        bytes,
        maxBytes: maxBytes,
        maxExtensions: maxExtensions,
      ));
}

List<MihonExtensionRecord> _parseExtensionList(List<int> bytes, {required int maxExtensions}) {
  final extensions = <MihonExtensionRecord>[];
  for (final field in _ProtoReader(bytes).readAll()) {
    if (field.number != 1) continue;
    if (field.wireType != 2) throw const FormatException('Mihon extension entry has an invalid wire type.');
    if (extensions.length >= maxExtensions) {
      throw FormatException('Mihon extension list exceeds $maxExtensions entries.');
    }
    extensions.add(_parseExtension(field.bytes!));
  }
  return extensions;
}

MihonExtensionRecord _parseExtension(List<int> bytes) {
  var name = '';
  var packageName = '';
  var resources = const MihonExtensionResources();
  String? extensionLib;
  var versionCode = 0;
  var versionName = '';
  var contentWarning = MihonContentWarning.unspecified;
  final sources = <MihonSourceRecord>[];

  for (final field in _ProtoReader(bytes).readAll()) {
    switch (field.number) {
      case 1:
        name = _stringField(field, 'extension name');
        break;
      case 2:
        packageName = _stringField(field, 'extension package name');
        break;
      case 3:
        resources = _parseResources(_bytesField(field, 'extension resources'));
        break;
      case 4:
        extensionLib = _stringField(field, 'extension library');
        break;
      case 5:
        versionCode = _varintField(field, 'extension version code');
        break;
      case 6:
        versionName = _stringField(field, 'extension version name');
        break;
      case 7:
        final value = _varintField(field, 'content warning');
        contentWarning = switch (value) {
          1 => MihonContentWarning.safe,
          2 => MihonContentWarning.mixed,
          3 => MihonContentWarning.nsfw,
          _ => MihonContentWarning.unspecified,
        };
        break;
      case 8:
        sources.add(_parseSource(_bytesField(field, 'extension source')));
      default:
        break;
    }
  }

  if (name.trim().isEmpty || packageName.trim().isEmpty) {
    throw const FormatException('Mihon extension entry is missing its name or package name.');
  }
  return MihonExtensionRecord(
    name: name,
    packageName: packageName,
    resources: resources,
    extensionLib: extensionLib,
    versionCode: versionCode,
    versionName: versionName,
    contentWarning: contentWarning,
    sources: List.unmodifiable(sources),
  );
}

MihonExtensionResources _parseResources(List<int> bytes) {
  Uri? apkUrl;
  Uri? iconUrl;
  Uri? jarUrl;
  for (final field in _ProtoReader(bytes).readAll()) {
    switch (field.number) {
      case 1:
        apkUrl = _tryUri(_stringField(field, 'APK URL'));
        break;
      case 2:
        iconUrl = _tryUri(_stringField(field, 'icon URL'));
        break;
      case 501:
        jarUrl = _tryUri(_stringField(field, 'JAR URL'));
        break;
      default:
        break;
    }
  }
  return MihonExtensionResources(apkUrl: apkUrl, iconUrl: iconUrl, jarUrl: jarUrl);
}

MihonSourceRecord _parseSource(List<int> bytes) {
  var id = 0;
  var name = '';
  var language = '';
  Uri? homeUrl;
  String? message;
  final mirrors = <Uri>[];
  for (final field in _ProtoReader(bytes).readAll()) {
    switch (field.number) {
      case 1:
        id = _varintField(field, 'source id');
        break;
      case 2:
        name = _stringField(field, 'source name');
        break;
      case 3:
        language = _stringField(field, 'source language');
        break;
      case 4:
        homeUrl = _tryUri(_stringField(field, 'source home URL'));
        break;
      case 5:
        mirrors.addAll(_stringField(field, 'source mirror URL').isEmpty
            ? const []
            : [_tryUri(_stringField(field, 'source mirror URL'))].whereType<Uri>());
      case 7:
        message = _stringField(field, 'source message');
        break;
      default:
        break;
    }
  }
  if (name.trim().isEmpty) throw const FormatException('Mihon source entry is missing its name.');
  return MihonSourceRecord(
    id: id,
    name: name,
    language: language,
    homeUrl: homeUrl,
    mirrorUrls: List.unmodifiable(mirrors),
    message: message,
  );
}

MihonRepositoryContact _parseContact(List<int> bytes) {
  String? website;
  String? discord;
  for (final field in _ProtoReader(bytes).readAll()) {
    switch (field.number) {
      case 1:
        website = _stringField(field, 'contact website');
        break;
      case 2:
        discord = _stringField(field, 'contact Discord');
        break;
      default:
        break;
    }
  }
  return MihonRepositoryContact(website: website, discord: discord);
}

Uri? _tryUri(String value) => value.isEmpty ? null : Uri.tryParse(value);

String _stringField(_ProtoField field, String label) {
  if (field.wireType != 2) throw FormatException('Mihon $label has an invalid wire type.');
  try {
    return utf8.decode(field.bytes!, allowMalformed: false);
  } on FormatException {
    throw FormatException('Mihon $label is not valid UTF-8.');
  }
}

List<int> _bytesField(_ProtoField field, String label) {
  if (field.wireType != 2) throw FormatException('Mihon $label has an invalid wire type.');
  return field.bytes!;
}

int _varintField(_ProtoField field, String label) {
  if (field.wireType != 0) throw FormatException('Mihon $label has an invalid wire type.');
  return field.varint!;
}

class _ProtoField {
  const _ProtoField({required this.number, required this.wireType, this.varint, this.bytes});
  final int number;
  final int wireType;
  final int? varint;
  final List<int>? bytes;
}

class _ProtoReader {
  _ProtoReader(List<int> bytes) : _bytes = bytes;
  final List<int> _bytes;
  int _offset = 0;

  List<_ProtoField> readAll() => readFields().toList(growable: false);

  Iterable<_ProtoField> readFields() sync* {
    while (_offset < _bytes.length) {
      final tag = _readVarint();
      final number = tag >> 3;
      final wireType = tag & 7;
      if (number == 0) throw const FormatException('Invalid protobuf field number zero.');
      switch (wireType) {
        case 0:
          yield _ProtoField(number: number, wireType: wireType, varint: _readVarint());
          break;
        case 1:
          _skip(8);
          break;
        case 2:
          final length = _readVarint();
          if (length > _bytes.length - _offset) throw const FormatException('Truncated protobuf length-delimited field.');
          final value = _bytes.sublist(_offset, _offset + length);
          _offset += length;
          yield _ProtoField(number: number, wireType: wireType, bytes: value);
          break;
        case 5:
          _skip(4);
          break;
        default:
          throw FormatException('Unsupported protobuf wire type $wireType.');
      }
    }
  }

  int _readVarint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 10; i++) {
      if (_offset >= _bytes.length) throw const FormatException('Truncated protobuf varint.');
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const FormatException('Protobuf varint exceeds 10 bytes.');
  }

  void _skip(int length) {
    if (length > _bytes.length - _offset) throw const FormatException('Truncated protobuf field.');
    _offset += length;
  }
}
