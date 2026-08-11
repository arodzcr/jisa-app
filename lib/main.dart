import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle, rootBundle, SystemNavigator;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF111111),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const JisaApp());
}

class JisaApp extends StatelessWidget {
  const JisaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculador de Fletes JISA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF111111),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6A00),
          brightness: Brightness.dark,
        ),
      ),
      home: const CalculadorScreen(),
    );
  }
}

class CalculadorScreen extends StatefulWidget {
  const CalculadorScreen({super.key});

  @override
  State<CalculadorScreen> createState() => _CalculadorScreenState();
}

const String _baseUrl = 'https://calculador.jisa.local/';

class _CalculadorScreenState extends State<CalculadorScreen> {
  late final WebViewController _controller;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF111111))
      ..addJavaScriptChannel('JisaBridge', onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _cargando = false);
        },
        onWebResourceError: (e) {
          // Solo interesa el fallo del documento principal.
          if ((e.isForMainFrame ?? true) && mounted) {
            setState(() => _error = e.description);
          }
        },
        onNavigationRequest: (req) {
          // El documento propio se sirve bajo este origen: debe navegar normal.
          if (req.url.startsWith(_baseUrl) || req.url == 'about:blank') {
            return NavigationDecision.navigate;
          }
          if (req.url.startsWith('http')) {
            _abrirExterno(req.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));

    final android = _controller.platform;
    if (android is AndroidWebViewController) {
      android.setMediaPlaybackRequiresUserGesture(false);
      AndroidWebViewController.enableDebugging(false);
    }

    _cargarApp();
  }

  /// Se carga con un origen propio (no file://) para que localStorage
  /// persista de forma confiable entre sesiones.
  Future<void> _cargarApp() async {
    try {
      final html = await rootBundle.loadString('assets/www/index.html');
      await _controller.loadHtmlString(html, baseUrl: _baseUrl);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _abrirExterno(String url) async {
    // Compartir por WhatsApp: se extrae el texto y se abre el selector del sistema.
    final uri = Uri.tryParse(url);
    final texto = uri?.queryParameters['text'];
    await Share.share(texto ?? url);
  }

  /* ---------------- Puente con el HTML ---------------- */

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    int id = 0;
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      id = (msg['id'] as num).toInt();
      final accion = msg['action'] as String;
      final payload = (msg['payload'] ?? {}) as Map<String, dynamic>;

      switch (accion) {
        case 'saveFile':
          await _guardarArchivo(
              payload['name'] as String, payload['base64'] as String);
          _responder(id, true, {'ok': true});
          break;
        case 'pickFile':
          final b64 = await _escogerArchivo();
          _responder(id, true, {'base64': b64});
          break;
        case 'httpPost':
          final r = await _post(payload['url'] as String,
              payload['key'] as String, payload['body'] as String);
          _responder(id, true, r);
          break;
        default:
          _responder(id, false, 'Acción desconocida: $accion');
      }
    } catch (e) {
      if (id != 0) _responder(id, false, e.toString());
    }
  }

  void _responder(int id, bool ok, Object? data) {
    final json = jsonEncode(data);
    _controller.runJavaScript('window.JisaBridgeResolve($id, $ok, $json);');
  }

  Future<void> _guardarArchivo(String nombre, String base64Data) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$nombre');
    await file.writeAsBytes(base64Decode(base64Data));
    await Share.shareXFiles([XFile(file.path)],
        subject: nombre, text: 'Plantilla de fletes JISA');
  }

  Future<String?> _escogerArchivo() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    if (f.bytes != null) return base64Encode(f.bytes!);
    if (f.path != null) return base64Encode(await File(f.path!).readAsBytes());
    return null;
  }

  Future<Map<String, dynamic>> _post(
      String url, String key, String body) async {
    final resp = await http
        .post(
          Uri.parse(url),
          headers: {
            'Authorization': key,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 90));
    return {'status': resp.statusCode, 'body': utf8.decode(resp.bodyBytes)};
  }

  /* ---------------- UI ---------------- */

  Future<bool> _alSalir() async {
    // El botón atrás navega dentro de la app antes de cerrarla.
    final puede = await _controller.canGoBack();
    if (puede) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _alSalir()) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        body: SafeArea(
          child: _error != null
              ? _pantallaError()
              : Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_cargando)
                      const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFFF6A00)),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _pantallaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFE53935), size: 44),
              const SizedBox(height: 16),
              const Text('No se pudo abrir el calculador',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(height: 10),
              Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13)),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6A00),
                    foregroundColor: Colors.black),
                onPressed: () {
                  setState(() {
                    _error = null;
                    _cargando = true;
                  });
                  _cargarApp();
                },
                child: const Text('REINTENTAR'),
              ),
            ],
          ),
        ),
      );
}
