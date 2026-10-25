import 'dart:convert';
import 'dart:io';

import 'inertia_config.dart';

/// Makes the script and style tags for `@vite` in the root view.
class Vite {
  const Vite(this.config);

  final InertiaConfig config;

  /// The path of the manifest that `vite build` writes.
  String get manifestPath {
    return '${config.publicPath}/${config.buildDirectory}/.vite/manifest.json';
  }

  /// The tags for the entry points: from the dev server when it runs,
  /// else from the manifest of the build.
  Future<String> tags() async {
    String? dev = await devUrl();
    if (dev != null) return devTags(dev);
    File file = File(manifestPath);
    if (!await file.exists()) {
      throw StateError(
        'No Vite manifest at $manifestPath. Run `vite build`, or run '
        '`vite` (dev server) with a `${config.publicPath}/hot` file or '
        '`InertiaConfig.devServerUrl`.',
      );
    }
    Object? manifest = jsonDecode(await file.readAsString());
    return buildTags((manifest as Map<String, dynamic>));
  }

  /// The url of the dev server, or null when it does not run.
  Future<String?> devUrl() async {
    String? url = config.devServerUrl;
    if (url == null) {
      File hot = File('${config.publicPath}/hot');
      if (!await hot.exists()) return null;
      url = (await hot.readAsString()).trim();
    }
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Tags that load the entry points from the dev server at [url].
  String devTags(String url) {
    StringBuffer out = StringBuffer();
    if (config.reactRefresh) {
      out.writeln('<script type="module">');
      out.writeln("import RefreshRuntime from '$url/@react-refresh'");
      out.writeln('RefreshRuntime.injectIntoGlobalHook(window)');
      out.writeln(r'window.$RefreshReg$ = () => {}');
      out.writeln(r'window.$RefreshSig$ = () => (type) => type');
      out.writeln('window.__vite_plugin_react_preamble_installed__ = true');
      out.writeln('</script>');
    }
    out.writeln('<script type="module" src="$url/@vite/client"></script>');
    for (String entry in config.entryPoints) {
      out.writeln('<script type="module" src="$url/$entry"></script>');
    }
    return out.toString().trimRight();
  }

  /// Tags for the built files in [manifest]: the css of each entry and of
  /// the chunks it imports, then the script of each entry.
  String buildTags(Map<String, dynamic> manifest) {
    Set<String> styles = <String>{};
    List<String> scripts = <String>[];
    for (String entry in config.entryPoints) {
      Map<String, dynamic> chunk = _chunk(manifest, entry);
      String file = chunk['file'] as String;
      if (file.endsWith('.css')) {
        styles.add(file);
      } else {
        scripts.add(file);
      }
      _addCss(manifest, entry, styles, <String>{});
    }
    StringBuffer out = StringBuffer();
    for (String file in styles) {
      out.writeln('<link rel="stylesheet" href="${_url(file)}">');
    }
    for (String file in scripts) {
      out.writeln('<script type="module" src="${_url(file)}"></script>');
    }
    return out.toString().trimRight();
  }

  /// A hash of the manifest file, or null when there is none.
  String? manifestHash() {
    File file = File(manifestPath);
    if (!file.existsSync()) return null;
    // FNV-1a, 32 bit: the same bytes give the same hash on every server
    int hash = 0x811c9dc5;
    for (int byte in file.readAsBytesSync()) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// the css of the chunk [key] and of every chunk it imports
  void _addCss(
    Map<String, dynamic> manifest,
    String key,
    Set<String> styles,
    Set<String> seen,
  ) {
    if (!seen.add(key)) return;
    Map<String, dynamic> chunk = _chunk(manifest, key);
    for (Object? css in (chunk['css'] as List<dynamic>?) ?? <dynamic>[]) {
      styles.add(css as String);
    }
    for (Object? child in (chunk['imports'] as List<dynamic>?) ?? <dynamic>[]) {
      _addCss(manifest, child as String, styles, seen);
    }
  }

  Map<String, dynamic> _chunk(Map<String, dynamic> manifest, String key) {
    Object? chunk = manifest[key];
    if (chunk is Map<String, dynamic>) return chunk;
    throw StateError('"$key" is not in the Vite manifest $manifestPath.');
  }

  String _url(String file) => '/${config.buildDirectory}/$file';
}
