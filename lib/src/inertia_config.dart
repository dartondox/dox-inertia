import 'inertia_ssr.dart';

/// The settings of `dox_inertia`. Paths are from the folder where the
/// app runs (the project root).
/// ```
/// InertiaConfig inertiaConfig = InertiaConfig(
///   entryPoints: <String>['resources/js/app.tsx'],
///   reactRefresh: true,
/// );
/// ```
class InertiaConfig {
  const InertiaConfig({
    this.rootView = 'resources/views/app.html',
    this.entryPoints = const <String>['resources/js/app.js'],
    this.publicPath = 'public',
    this.buildDirectory = 'build',
    this.devServerUrl,
    this.reactRefresh = false,
    this.version,
    this.encryptHistory = false,
    this.ssr,
  });

  /// The HTML page of the first visit. Dox puts the page data in place of
  /// `@inertia`, and the script and style tags in place of `@vite`.
  /// One request can use another file with `Inertia.setRootView`.
  final String rootView;

  /// The Vite entry files, as in the `input` of `vite.config.js`.
  final List<String> entryPoints;

  /// The folder of public files. Vite writes the `hot` file and the
  /// `build` folder here.
  final String publicPath;

  /// The folder in [publicPath] where `vite build` writes its files.
  /// The browser loads them from `/<buildDirectory>/...`.
  final String buildDirectory;

  /// The url of the Vite dev server, like `http://localhost:5173`.
  /// When it is set, Dox loads the scripts from the dev server.
  /// When it is null, Dox reads the url from the `<publicPath>/hot` file,
  /// which `laravel-vite-plugin` writes while `vite` runs. With no hot
  /// file, Dox uses the built files.
  final String? devServerUrl;

  /// Add the React Fast Refresh code in dev mode. Turn it on when you use
  /// `@vitejs/plugin-react`.
  final bool reactRefresh;

  /// The asset version. When it changes, the browser loads the whole page
  /// again. Default: a hash of the Vite manifest file.
  final String? version;

  /// Encrypt the browser history of every page. One request can change
  /// it with `Inertia.encryptHistory(req, false)`.
  final bool encryptHistory;

  /// Server side rendering. Null (the default) turns it off. See
  /// [InertiaSsr].
  final InertiaSsr? ssr;
}
