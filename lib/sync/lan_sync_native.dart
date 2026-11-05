import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/pantry_database.dart';
import 'sync_auth.dart';
import 'sync_journal.dart';

class LanSync extends ChangeNotifier {
  static final instance = LanSync();
  final PantryDatabase _db;
  final int port;
  final bool discovery;
  LanSync({PantryDatabase? database, this.port = 45874, this.discovery = true})
      : _db = database ?? PantryDatabase.instance;
  bool get supported => true;
  bool enabled = false;
  bool busy = false;
  String code = '';
  String manualPeer = '';
  List<String> addresses = [];
  String status = 'Compartilhamento desativado';
  DateTime? lastSync;
  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _timer;
  Future<void>? _initializing;
  final _device = randomSyncId();
  final _peers = <String, DateTime>{};
  final _nonces = <String, DateTime>{};
  final _clients = <HttpClient>{};
  final _peerDigests = <String, String>{};
  int _generation = 0;
  int _activeRequests = 0;
  int get boundPort => _server?.port ?? port;

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    code = prefs.getString('lan_house_code') ?? randomSyncId();
    manualPeer = prefs.getString('lan_manual_peer') ?? '';
    enabled = prefs.getBool('lan_enabled') ?? false;
    if (enabled) await _start();
    notifyListeners();
  }

  static Uri peerUri(String peer) {
    final uri = Uri.tryParse('http://$peer');
    if (uri == null ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        InternetAddress.tryParse(uri.host)?.type != InternetAddressType.IPv4 ||
        uri.port < 1 ||
        uri.port > 65535)
      throw ArgumentError(
          'Informe um IPv4 e porta, por exemplo 192.168.1.10:45874');
    final parts = uri.host.split('.').map(int.parse).toList();
    if (!(parts[0] == 10 ||
        parts[0] == 127 ||
        (parts[0] == 192 && parts[1] == 168) ||
        (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
        (parts[0] == 169 && parts[1] == 254))) {
      throw ArgumentError('Use o endereço da rede local do outro aparelho.');
    }
    return uri.replace(path: '/sync');
  }

  Future<void> configure(
      {required bool enabled,
      required String code,
      required String peer}) async {
    final cleanCode = code.trim();
    if (enabled && (cleanCode.length < 16 || cleanCode.length > 128))
      throw ArgumentError('Use um código da casa com 16 a 128 caracteres.');
    if (peer.trim().isNotEmpty) peerUri(peer.trim());
    await stop();
    this.enabled = enabled;
    this.code = cleanCode;
    manualPeer = peer.trim();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('lan_house_code', cleanCode) ||
        !await prefs.setString('lan_manual_peer', manualPeer) ||
        !await prefs.setBool('lan_enabled', enabled))
      throw StateError('Não foi possível salvar a configuração');
    if (enabled) await _start();
    notifyListeners();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      if (!enabled || generation != _generation) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((request) => _handle(request, generation),
          onError: (Object _) {
        status =
            'Falha no servidor local. Desative e ative para tentar novamente.';
        notifyListeners();
      });
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      addresses = interfaces
          .expand((i) => i.addresses)
          .where((a) => !a.isLoopback)
          .map((a) => '${a.address}:${server.port}')
          .toList();
      if (discovery) {
        try {
          _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45873,
              reuseAddress: true);
          _udp!.broadcastEnabled = true;
          _udp!.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? packet;
            while ((packet = _udp?.receive()) != null) {
              try {
                if (packet!.data.length > 1024) continue;
                final data = jsonDecode(utf8.decode(packet.data)) as Map;
                if (data['v'] != 1 ||
                    data['group'] != SyncAuth(code).group ||
                    data['device'] == _device) continue;
                final peerPort = data['port'];
                if (peerPort is int &&
                    peerPort > 0 &&
                    peerPort <= 65535 &&
                    _peers.length < 32)
                  _peers['${packet.address.address}:$peerPort'] =
                      DateTime.now();
              } catch (_) {/* Pacotes de outros serviços não são nossos. */}
            }
          }, onError: (Object _) {});
        } catch (_) {/* Conexão por endereço funciona sem descoberta UDP. */}
      }
      status = 'Aguardando outros aparelhos com o mesmo código da casa';
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => syncNow());
      await syncNow();
    } catch (error) {
      await stop();
      status = 'Não foi possível iniciar na rede: $error';
    }
    notifyListeners();
  }

  void _announce() {
    try {
      _udp?.send(
          utf8.encode(jsonEncode({
            'v': 1,
            'group': SyncAuth(code).group,
            'device': _device,
            'port': boundPort
          })),
          InternetAddress('255.255.255.255'),
          45873);
    } catch (_) {/* O endereço manual continua disponível. */}
  }

  Future<String> _read(Stream<List<int>> stream) async {
    final bytes = <int>[];
    final deadline = Stopwatch()..start();
    await for (final chunk in stream.timeout(const Duration(seconds: 8))) {
      if (deadline.elapsed > const Duration(seconds: 10))
        throw TimeoutException("Tempo limite de leitura");
      if (bytes.length + chunk.length > 4 * 1024 * 1024)
        throw const FormatException('Mensagem muito grande');
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<void> _handle(HttpRequest request, int generation) async {
    if (_activeRequests >= 4) {
      request.response.statusCode = 503;
      await request.response.close();
      return;
    }
    _activeRequests++;
    try {
      if (request.method != 'POST' || request.uri.path != '/sync') {
        request.response.statusCode = 404;
        return;
      }
      final body = await _read(request);
      final auth = SyncAuth(code);
      if (!enabled ||
          generation != _generation ||
          !auth.verify(body, request.headers.value('x-pantry-signature'))) {
        request.response.statusCode = 403;
        return;
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final nonce = data['nonce'];
      final sent = data['sent'];
      _nonces.removeWhere((_, date) =>
          DateTime.now().difference(date) > const Duration(minutes: 5));
      if (data['v'] != 1 ||
          nonce is! String ||
          nonce.length > 100 ||
          sent is! int ||
          (DateTime.now().millisecondsSinceEpoch - sent).abs() > 300000 ||
          _nonces.containsKey(nonce) ||
          _nonces.length > 512) {
        request.response.statusCode = 400;
        return;
      }
      _nonces[nonce] = DateTime.now();
      await _db.mergeChanges(data['events'] as List);
      final events = await _db.exportChanges();
      final digest = SyncAuth('pantry-history-v1').sign(jsonEncode(events
        ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String))));
      final response = jsonEncode({
        'v': 1,
        'nonce': nonce,
        'digest': digest,
        'events': data['digest'] == digest ? <dynamic>[] : events
      });
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('x-pantry-signature', auth.sign(response));
      request.response.write(response);
      lastSync = DateTime.now();
      status = 'Dados atualizados pela rede local';
      notifyListeners();
    } catch (_) {
      request.response.statusCode = 400;
    } finally {
      _activeRequests--;
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> syncNow() async {
    if (!enabled || _server == null || busy) return;
    busy = true;
    final generation = _generation;
    notifyListeners();
    try {
      _announce();
      _peers.removeWhere((_, seen) =>
          DateTime.now().difference(seen) > const Duration(seconds: 30));
      final peers = {if (manualPeer.isNotEmpty) manualPeer, ..._peers.keys}
          .take(8)
          .toList();
      var successes = 0;
      _peerDigests.removeWhere((peer, _) => !peers.contains(peer));
      final events = await _db.exportChanges();
      events.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      final digest = SyncAuth('pantry-history-v1').sign(jsonEncode(events));
      for (final peer in peers) {
        if (generation != _generation || !enabled) break;
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 3);
        _clients.add(client);
        try {
          final nonce = randomSyncId();
          final auth = SyncAuth(code);
          final body = jsonEncode({
            'v': 1,
            'nonce': nonce,
            'sent': DateTime.now().millisecondsSinceEpoch,
            'digest': digest,
            'events': _peerDigests[peer] == digest ? <dynamic>[] : events
          });
          final request = await client
              .postUrl(peerUri(peer))
              .timeout(const Duration(seconds: 4));
          request.headers.contentType = ContentType.json;
          request.headers.set('x-pantry-signature', auth.sign(body));
          request.write(body);
          final response =
              await request.close().timeout(const Duration(seconds: 8));
          if (response.statusCode != 200)
            throw const FormatException(
                'Aparelho recusou a conexão. Confira o código da casa.');
          final received = await _read(response);
          if (!auth.verify(
              received, response.headers.value('x-pantry-signature')))
            throw const FormatException('Código da casa diferente');
          final data = jsonDecode(received) as Map;
          if (data['v'] != 1 || data['nonce'] != nonce)
            throw const FormatException('Resposta inválida');
          if (generation != _generation || !enabled) break;
          await _db.mergeChanges(data['events'] as List);
          if (data['digest'] is String)
            _peerDigests[peer] = data['digest'] as String;
          successes++;
        } catch (_) {
          /* Nova tentativa automática no próximo ciclo. */
        } finally {
          _clients.remove(client);
          client.close(force: true);
        }
      }
      if (generation == _generation) {
        if (successes > 0) {
          lastSync = DateTime.now();
          status = 'Sincronizado com $successes aparelho(s)';
        } else if (peers.isNotEmpty) {
          status =
              'Sem conexão. Confira rede, endereço, código da casa e permissão no firewall.';
        }
      }
    } catch (_) {
      if (generation == _generation)
        status =
            'Não foi possível sincronizar. Nova tentativa em alguns segundos.';
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _udp?.close();
    _udp = null;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
    final server = _server;
    _server = null;
    await server?.close(force: true);
    busy = false;
    _peerDigests.clear();
    _peers.clear();
    _nonces.clear();
    addresses = [];
    status = 'Compartilhamento desativado';
    notifyListeners();
  }
}
