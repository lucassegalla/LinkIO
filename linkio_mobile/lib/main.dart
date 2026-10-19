import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const LinkIOApp());

const azul = Color(0xFF3355FF);

class _AdicionarDispositivoDialog extends StatefulWidget {
  const _AdicionarDispositivoDialog();

  @override
  State<_AdicionarDispositivoDialog> createState() =>
      _AdicionarDispositivoDialogState();
}

class _AdicionarDispositivoDialogState
    extends State<_AdicionarDispositivoDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _conectar() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar dispositivo'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.url,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '192.168.100.170',
          labelText: 'Endereço IP',
        ),
        onSubmitted: (_) => _conectar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _conectar,
          child: const Text('Conectar'),
        ),
      ],
    );
  }
}

class LinkIOApp extends StatelessWidget {
  const LinkIOApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkIO',
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

class LinkIODevice {
  LinkIODevice({
    required this.name,
    required this.host,
    required this.port,
    this.motorRunning = false,
    this.motorDirection = 1,
    this.color = 'off',
    this.lightOn = false,
    this.red = 0,
    this.green = 0,
    this.blue = 0,
    this.brightness = 100,
    this.online = true,
  });

  String name;
  String host;
  int port;

  bool motorRunning;
  int motorDirection;

  String color;
  bool lightOn;
  int red;
  int green;
  int blue;
  int brightness;
  bool online;

  String get baseUrl => 'http://$host:$port';

  factory LinkIODevice.fromJson(
    Map<String, dynamic> json,
    String host,
    int port,
  ) {
    return LinkIODevice(
      name: (json['name'] ?? 'LinkIO').toString(),
      host: host,
      port: port,
      motorRunning: json['motorRunning'] == true,
      motorDirection: (json['motorDirection'] as num?)?.toInt() ?? 1,
      color: (json['color'] ?? 'off').toString(),
      lightOn: json['light'] == true,
      red: (json['red'] as num?)?.toInt() ?? 0,
      green: (json['green'] as num?)?.toInt() ?? 0,
      blue: (json['blue'] as num?)?.toInt() ?? 0,
      brightness: (json['brightness'] as num?)?.toInt() ?? 100,
    );
  }

  void updateFromJson(Map<String, dynamic> json) {
    motorRunning = json['motorRunning'] == true;
    motorDirection =
        (json['motorDirection'] as num?)?.toInt() ?? motorDirection;
    color = (json['color'] ?? color).toString();
    lightOn = json['light'] == true;
    red = (json['red'] as num?)?.toInt() ?? red;
    green = (json['green'] as num?)?.toInt() ?? green;
    blue = (json['blue'] as num?)?.toInt() ?? blue;
    brightness = (json['brightness'] as num?)?.toInt() ?? brightness;
    online = true;
  }
}

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final List<LinkIODevice> _devices = [];
  final List<LinkIODevice> _foundDevices = [];

  // Each device has its own expanded/collapsed state.
  final Set<String> _expandedHosts = {};

  bool _scanning = false;
  bool _usarRgbManual = false;
  String _status = '';

  String _nameKey(String host) => 'nome_$host';

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
  }

  Future<String> _savedName(String host, String fallback) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_nameKey(host));

    return saved != null && saved.trim().isNotEmpty ? saved : fallback;
  }

  Future<Map<String, dynamic>> _getStatus(String host, int port) async {
    final response = await http
        .get(Uri.parse('http://$host:$port/api/status'))
        .timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _scan() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _status = 'Procurando dispositivos...';
    });

    final found = <String, LinkIODevice>{};
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

        if (!instance.toLowerCase().startsWith('linkio')) {
          continue;
        }

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
              final data = await _getStatus(host, srv.port);
              final device = LinkIODevice.fromJson(data, host, srv.port);

              device.name = await _savedName(host, device.name);
              found[host] = device;
            } catch (_) {
              // Ignore devices without the LinkIO API.
            }
          }
        }
      }
    } catch (_) {
      // Manual IP connection remains available.
    } finally {
      mdns.stop();
    }

    if (!mounted) return;

    final available = found.values
        .where(
          (candidate) => !_devices.any(
            (connected) => connected.host == candidate.host,
          ),
        )
        .toList();

    setState(() {
      _scanning = false;
      _foundDevices
        ..clear()
        ..addAll(available);
      _status = available.isEmpty ? 'Nenhum dispositivo novo encontrado' : '';
    });

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 24,
              ),
              title: const Text(
                'Selecionar dispositivo',
                maxLines: 1,
                softWrap: false,
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: _foundDevices.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Nenhum dispositivo novo encontrado.',
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _foundDevices.length,
                        separatorBuilder: (_, __) => const Divider(height: 20),
                        itemBuilder: (context, index) {
                          final device = _foundDevices[index];

                          return Row(
                            children: [
                              const Icon(
                                Icons.memory_rounded,
                                color: azul,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      device.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${device.host}:${device.port}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: () async {
                                  await _connectHost(
                                    '${device.host}:${device.port}',
                                  );

                                  if (!mounted || !dialogContext.mounted) {
                                    return;
                                  }

                                  final connected = _devices.any(
                                    (item) => item.host == device.host,
                                  );

                                  if (connected) {
                                    setState(() {
                                      _foundDevices.removeWhere(
                                        (item) => item.host == device.host,
                                      );
                                    });

                                    Navigator.of(dialogContext).pop();
                                  } else {
                                    setDialogState(() {});
                                  }
                                },
                                child: const Text('Conectar'),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

Future<void> _addByIp() async {
  final ip = await showDialog<String>(
    context: context,
    builder: (dialogContext) => const _AdicionarDispositivoDialog(),
  );

  if (ip == null || ip.isEmpty || !mounted) return;

  await _connectHost(ip);
}

  Future<void> _connectHost(String host) async {
    final normalizedInput = host
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/+$'), '');

    if (normalizedInput.isEmpty) return;

    final separator = normalizedInput.lastIndexOf(':');
    final hasPort = separator > 0 &&
        int.tryParse(normalizedInput.substring(separator + 1)) != null;

    final normalizedHost =
        hasPort ? normalizedInput.substring(0, separator) : normalizedInput;
    final port =
        hasPort ? int.parse(normalizedInput.substring(separator + 1)) : 80;

    try {
      final data = await _getStatus(normalizedHost, port);
      final device = LinkIODevice.fromJson(data, normalizedHost, port);

      device.name = await _savedName(normalizedHost, device.name);

      if (!mounted) return;

      setState(() {
        final index = _devices.indexWhere(
          (item) => item.host == normalizedHost,
        );

        if (index >= 0) {
          final existing = _devices[index];

          existing
            ..port = device.port
            ..motorRunning = device.motorRunning
            ..motorDirection = device.motorDirection
            ..color = device.color
            ..lightOn = device.lightOn
            ..red = device.red
            ..green = device.green
            ..blue = device.blue
            ..brightness = device.brightness
            ..online = true;

          if (existing.name.trim().isEmpty) {
            existing.name = device.name;
          }
        } else {
          _devices.add(device);
        }

        _expandedHosts.add(normalizedHost);

        _status = '';
      });
    } catch (e) {
      _setStatus('Falha ao conectar: $e');
    }
  }

  Future<void> _renameDevice(LinkIODevice device) async {
    final controller = TextEditingController(text: device.name);

    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Renomear dispositivo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome do dispositivo',
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      );

      if (!mounted || name == null || name.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey(device.host), name);

      if (!mounted) return;
      setState(() => device.name = name);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _disconnectDevice(LinkIODevice device) async {
    // Tenta parar o motor de todos os dispositivos conectados.
    final devicesToStop = List<LinkIODevice>.from(_devices);

    final results = await Future.wait(
      devicesToStop.map((item) async {
        try {
          final response = await http
              .post(
                Uri.parse('${item.baseUrl}/api/motor'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'running': false,
                  'direction': item.motorDirection,
                }),
              )
              .timeout(const Duration(seconds: 4));

          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}');
          }

          final data = jsonDecode(response.body) as Map<String, dynamic>;
          item.updateFromJson(data);
          return true;
        } catch (_) {
          item.online = false;
          return false;
        }
      }),
    );

    if (!mounted) return;

    final failed = results.where((success) => !success).length;

    setState(() {
      _devices.remove(device);
      _expandedHosts.remove(device.host);

      _status = failed == 0
          ? 'Parada solicitada. Dispositivo desconectado.'
          : 'Dispositivo desconectado. '
              '$failed dispositivo(s) não responderam ao comando de parada.';
    });
  }

  Future<void> _sendCommand(
    LinkIODevice device, {
    required String route,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${device.baseUrl}$route'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() => device.updateFromJson(data));
    } catch (_) {
      if (!mounted) return;

      setState(() => device.online = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao enviar comando ao LinkIO'),
        ),
      );
    }
  }

  Future<void> _setLight(LinkIODevice device, bool on) async {
    await _sendCommand(
      device,
      route: '/api/light',
      body: {'on': on},
    );
  }

  Future<void> _toggleMotor(LinkIODevice device, bool running) async {
    await _sendCommand(
      device,
      route: '/api/motor',
      body: {
        'running': running,
        'direction': device.motorDirection,
      },
    );
  }

  Future<void> _setDirection(LinkIODevice device, int direction) async {
    await _sendCommand(
      device,
      route: '/api/motor',
      body: {
        'running': device.motorRunning,
        'direction': direction,
      },
    );
  }

  Future<void> _setColor(LinkIODevice device, String color) async {
    await _sendCommand(
      device,
      route: '/api/rgb',
      body: {'color': color},
    );
  }

  Future<void> _setRgb(LinkIODevice device) async {
    await _sendCommand(
      device,
      route: '/api/rgb',
      body: {
        'red': device.red,
        'green': device.green,
        'blue': device.blue,
      },
    );
  }

  Future<void> _setBrightness(
    LinkIODevice device,
    int brightness,
  ) async {
    await _sendCommand(
      device,
      route: '/api/brightness',
      body: {'brightness': brightness},
    );
  }

  Future<void> _refresh(LinkIODevice device) async {
    try {
      final data = await _getStatus(device.host, device.port);

      if (!mounted) return;
      setState(() => device.updateFromJson(data));
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
          'LinkIO',
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
                child: Column(
                  children: [
                    Icon(
                      Icons.memory_rounded,
                      size: 64,
                      color: azul,
                    ),
                    SizedBox(height: 12),
                    Text('Nenhum dispositivo conectado'),
                    SizedBox(height: 4),
                    Text(
                      'Busque na rede ou adicione pelo IP.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
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

  Widget _deviceCard(LinkIODevice device) {
    final expanded = _expandedHosts.contains(device.host);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho sempre visível.
            Row(
              children: [
                const Icon(
                  Icons.memory_rounded,
                  color: azul,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                IconButton(
                  tooltip: expanded
                      ? 'Recolher dispositivo'
                      : 'Expandir dispositivo',
                  onPressed: () {
                    setState(() {
                      if (expanded) {
                        _expandedHosts.remove(device.host);
                      } else {
                        _expandedHosts.add(device.host);
                      }
                    });
                  },
                  icon: Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opções do dispositivo',
                  onSelected: (value) {
                    if (value == 'rename') {
                      _renameDevice(device);
                    } else if (value == 'disconnect') {
                      _disconnectDevice(device);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('Renomear'),
                    ),
                    PopupMenuItem(
                      value: 'disconnect',
                      child: Text('Desconectar'),
                    ),
                  ],
                ),
              ],
            ),

            // Os controles só aparecem quando o cartão está expandido.
            if (expanded) ...[
              const SizedBox(height: 16),
              _sectionTitle(
                'Motor de passo',
                Icons.settings_rounded,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          device.motorRunning
                              ? Icons.rotate_right_rounded
                              : Icons.stop_circle_outlined,
                          size: 30,
                          color: device.motorRunning
                              ? Colors.green
                              : Colors.black54,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            device.motorRunning
                                ? 'Motor em funcionamento'
                                : 'Motor parado',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: device.motorRunning,
                          onChanged: device.online
                              ? (value) => _toggleMotor(device, value)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: device.online
                                ? () => _setDirection(device, -1)
                                : null,
                            icon: const Icon(
                              Icons.rotate_left_rounded,
                            ),
                            label: const Text('Anti-horário'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: device.motorDirection == -1
                                  ? const Color(0xFFE8ECFF)
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: device.online
                                ? () => _setDirection(device, 1)
                                : null,
                            icon: const Icon(
                              Icons.rotate_right_rounded,
                            ),
                            label: const Text('Horário'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: device.motorDirection == 1
                                  ? const Color(0xFFE8ECFF)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'O sentido selecionado será usado ao ligar o motor.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: device.lightOn ? Colors.amber : azul,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Iluminação',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch(
                    value: device.lightOn,
                    onChanged: device.online
                        ? (value) => _setLight(device, value)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Cores'),
                    icon: Icon(Icons.palette_outlined),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('RGB manual'),
                    icon: Icon(Icons.tune),
                  ),
                ],
                selected: {_usarRgbManual},
                onSelectionChanged: (selection) {
                  setState(() {
                    _usarRgbManual = selection.first;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (!_usarRgbManual)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _colorButton(
                      device,
                      'red',
                      'Vermelho',
                      Colors.red,
                    ),
                    _colorButton(
                      device,
                      'green',
                      'Verde',
                      Colors.green,
                    ),
                    _colorButton(
                      device,
                      'blue',
                      'Azul',
                      Colors.blue,
                    ),
                    _colorButton(
                      device,
                      'white',
                      'Branco',
                      Colors.white,
                    ),
                    _colorButton(
                      device,
                      'yellow',
                      'Amarelo',
                      Colors.yellow,
                    ),
                    _colorButton(
                      device,
                      'cyan',
                      'Ciano',
                      Colors.cyan,
                    ),
                    _colorButton(
                      device,
                      'magenta',
                      'Magenta',
                      Colors.purple,
                    ),
                  ],
                )
              else ...[
                _rgbSlider(
                  device: device,
                  label: 'Vermelho',
                  value: device.red,
                  color: Colors.red,
                  onChanged: (value) {
                    setState(() {
                      device.red = value;
                      device.color = 'custom';
                    });
                  },
                  onChangeEnd: (_) => _setRgb(device),
                ),
                _rgbSlider(
                  device: device,
                  label: 'Verde',
                  value: device.green,
                  color: Colors.green,
                  onChanged: (value) {
                    setState(() {
                      device.green = value;
                      device.color = 'custom';
                    });
                  },
                  onChangeEnd: (_) => _setRgb(device),
                ),
                _rgbSlider(
                  device: device,
                  label: 'Azul',
                  value: device.blue,
                  color: Colors.blue,
                  onChanged: (value) {
                    setState(() {
                      device.blue = value;
                      device.color = 'custom';
                    });
                  },
                  onChangeEnd: (_) => _setRgb(device),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.fromARGB(
                          255,
                          device.red,
                          device.green,
                          device.blue,
                        ),
                        border: Border.all(
                          color: const Color(0xFFE2E5EC),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'RGB(${device.red}, ${device.green}, ${device.blue})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: device.online
                          ? () {
                              setState(() {
                                device.red = 0;
                                device.green = 0;
                                device.blue = 0;
                                device.color = 'custom';
                              });
                              _setRgb(device);
                            }
                          : null,
                      child: const Text('Zerar RGB'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _sliderLabel(
                'Brilho geral',
                '${device.brightness}%',
              ),
              Slider(
                value: device.brightness.toDouble().clamp(0.0, 100.0),
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: azul,
                onChanged: device.online
                    ? (value) {
                        setState(() {
                          device.brightness = value.round();
                        });
                      }
                    : null,
                onChangeEnd: device.online
                    ? (value) => _setBrightness(
                          device,
                          value.round(),
                        )
                    : null,
              ),
              Row(
                children: [
                  Icon(
                    device.online ? Icons.wifi : Icons.wifi_off,
                    size: 18,
                    color: device.online ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      device.online ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: device.online ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _refresh(device),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Atualizar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rgbSlider({
    required LinkIODevice device,
    required String label,
    required int value,
    required Color color,
    required ValueChanged<int> onChanged,
    required ValueChanged<int> onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sliderLabel(label, '$value'),
        Slider(
          value: value.toDouble().clamp(0.0, 255.0),
          min: 0,
          max: 255,
          divisions: 255,
          activeColor: color,
          onChanged: device.online ? (value) => onChanged(value.round()) : null,
          onChangeEnd:
              device.online ? (value) => onChangeEnd(value.round()) : null,
        ),
      ],
    );
  }

  Widget _sliderLabel(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: azul),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _colorButton(
    LinkIODevice device,
    String color,
    String label,
    Color swatch,
  ) {
    final selected = device.color == color;
    final isWhite = color == 'white';

    return OutlinedButton(
      onPressed: device.online ? () => _setColor(device, color) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        backgroundColor: selected ? const Color(0xFFE8ECFF) : Colors.white,
        side: BorderSide(
          color: selected ? azul : const Color(0xFFE2E5EC),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: swatch,
              shape: BoxShape.circle,
              border: Border.all(
                color: isWhite ? const Color(0xFFB8BDC8) : Colors.transparent,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(label),
          if (selected) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check, size: 15),
          ],
        ],
      ),
    );
  }
}
