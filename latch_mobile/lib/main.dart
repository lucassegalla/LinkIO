
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

void main() => runApp(const LatchApp());

class LatchApp extends StatelessWidget {
  const LatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF3355FF);

    return MaterialApp(
      title: 'Latch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: azul),
        scaffoldBackgroundColor: const Color(0xFFF4F5F8),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE2E5EC)),
          ),
        ),
      ),
      home: const DevicesPage(),
    );
  }
}

class LatchDevice {
  LatchDevice({
    required this.name,
    required this.host,
    required this.port,
    this.isOn = false,
    this.brightness = 70,
    this.online = true,
  });

  String name;
  String host;
  int port;
  bool isOn;
  int brightness;
  bool online;

  String get baseUrl => 'http://$host:$port';

  factory LatchDevice.fromJson(
    Map<String, dynamic> json,
    String host,
    int port,
  ) {
    return LatchDevice(
      name: (json['name'] ?? 'LED').toString(),
      host: host,
      port: port,
      isOn: json['light'] == true || json['on'] == true,
      brightness:
          ((json['brightness'] as num?)?.round().clamp(0, 100).toInt()) ??
              70,
      online: true,
    );
  }

  void updateFromJson(Map<String, dynamic> json) {
    isOn = json['light'] == true || json['on'] == true;
    brightness =
        ((json['brightness'] as num?)?.round().clamp(0, 100).toInt()) ??
            brightness;
    name = (json['name'] ?? name).toString();
    online = true;
  }
}

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final List<LatchDevice> _devices = [];

  bool _scanning = false;
  String _status = '';

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
  }

  Future<void> _scan() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _status = 'Procurando...';
    });

    final found = <String, LatchDevice>{};
    final mdns = MDnsClient();

    try {
      await mdns.start();

      await for (final ptr in mdns
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('_http._tcp.local'),
          )
          .timeout(
            const Duration(seconds: 4),
            onTimeout: (sink) => sink.close(),
          )) {
        final instance = ptr.domainName;

        if (!instance.toLowerCase().startsWith('latch')) continue;

        await for (final srv in mdns
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(instance),
            )
            .timeout(
              const Duration(seconds: 2),
              onTimeout: (sink) => sink.close(),
            )) {
          await for (final ip in mdns
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )
              .timeout(
                const Duration(seconds: 2),
                onTimeout: (sink) => sink.close(),
              )) {
            final host = ip.address.address;

            try {
              final response = await http
                  .get(Uri.parse('http://$host:${srv.port}/api/status'))
                  .timeout(const Duration(seconds: 2));

              if (response.statusCode == 200) {
                final data =
                    jsonDecode(response.body) as Map<String, dynamic>;

                found[host] = LatchDevice.fromJson(
                  data,
                  host,
                  srv.port,
                );
              }
            } catch (_) {
              // Ignore devices that do not implement the Latch API.
            }
          }
        }
      }
    } catch (_) {
      // Manual IP connection remains available if discovery fails.
    } finally {
      mdns.stop();
    }

    if (!mounted) return;

    setState(() {
      for (final device in found.values) {
        final index =
            _devices.indexWhere((item) => item.host == device.host);

        if (index >= 0) {
          _devices[index]
            ..name = device.name
            ..port = device.port
            ..isOn = device.isOn
            ..brightness = device.brightness
            ..online = true;
        } else {
          _devices.add(device);
        }
      }

      _scanning = false;
      _status = found.isEmpty
          ? 'Nenhum dispositivo encontrado'
          : '${found.length} encontrado(s)';
    });
  }

  Future<void> _addByIp() async {
    final controller = TextEditingController();
    String? ip;

    try {
      ip = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Adicionar dispositivo'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '192.168.100.170',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: const Text('Conectar'),
            ),
          ],
        ),
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 250),
      );
    } finally {
      controller.dispose();
    }

    if (ip == null || ip.isEmpty || !mounted) return;

    await _connectHost(ip);
  }

  Future<void> _connectHost(String host) async {
    final normalizedHost = host
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/+$'), '');

    if (normalizedHost.isEmpty) return;

    try {
      final response = await http
          .get(Uri.parse('http://$normalizedHost:80/api/status'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data =
          jsonDecode(response.body) as Map<String, dynamic>;

      final device = LatchDevice.fromJson(
        data,
        normalizedHost,
        80,
      );

      if (!mounted) return;

      setState(() {
        final index = _devices.indexWhere(
          (item) => item.host == normalizedHost,
        );

        if (index >= 0) {
          _devices[index]
            ..name = device.name
            ..port = device.port
            ..isOn = device.isOn
            ..brightness = device.brightness
            ..online = true;
        } else {
          _devices.add(device);
        }

        _status = '';
      });
    } catch (_) {
      _setStatus(
        'Falha ao conectar. Confira o IP e a rede Wi-Fi.',
      );
    }
  }

  Future<void> _toggle(
    LatchDevice device,
    bool desired,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${device.baseUrl}/api/light'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'on': desired}),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final body =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;

      setState(() {
        device.updateFromJson(body);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => device.online = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao enviar comando'),
        ),
      );
    }
  }

  Future<void> _setBrightness(
    LatchDevice device,
    int brightness,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${device.baseUrl}/api/brightness'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'brightness': brightness}),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final body =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;

      setState(() {
        device.updateFromJson(body);
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao ajustar brilho'),
        ),
      );
    }
  }

  Future<void> _refresh(LatchDevice device) async {
    try {
      final response = await http
          .get(Uri.parse('${device.baseUrl}/api/status'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;

      setState(() {
        device.updateFromJson(data);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => device.online = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo sem resposta'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Latch',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 25,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar dispositivos',
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.wifi_find_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (_status.isNotEmpty) ...[
            Text(
              _status,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
          ],
          if (_devices.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 100),
              child: Center(
                child: Icon(
                  Icons.lightbulb_outline,
                  size: 64,
                  color: Color(0xFF3355FF),
                ),
              ),
            )
          else
            ..._devices.map(_deviceCard),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addByIp,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
    );
  }

  Widget _deviceCard(LatchDevice device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  device.isOn
                      ? Icons.lightbulb
                      : Icons.lightbulb_outline,
                  color: device.isOn
                      ? const Color(0xFF3355FF)
                      : Colors.black45,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        '${device.host}:${device.port}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: device.isOn,
                  onChanged: device.online
                      ? (value) => _toggle(device, value)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text('Brilho'),
                Text(
                  '${device.isOn ? device.brightness : 0}%',
                ),
              ],
            ),
            Slider(
              value: device.brightness
                  .toDouble()
                  .clamp(0, 100)
                  .toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: device.online
                  ? (value) {
                      setState(() {
                        device.brightness = value.round();
                        device.isOn = value.round() > 0;
                      });
                    }
                  : null,
              onChangeEnd: device.online
                  ? (value) =>
                      _setBrightness(device, value.round())
                  : null,
            ),
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  device.online ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: device.online
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: () => _refresh(device),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
