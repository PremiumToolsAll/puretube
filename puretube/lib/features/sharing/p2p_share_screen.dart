import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';

/// P2P offline sharing via Nearby Connections (Wi-Fi Direct).
class P2pShareScreen extends StatefulWidget {
  final String filePath;

  const P2pShareScreen(
      {super.key, required this.filePath});

  @override
  State<P2pShareScreen> createState() =>
      _P2pShareScreenState();
}

class _P2pShareScreenState
    extends State<P2pShareScreen> {
  final _nearby = Nearby();
  bool _advertising = false;
  bool _discovering = false;
  final List<String> _devices = [];
  final Map<String, String> _names = {};
  String _status = 'Choose a mode';

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _stop() async {
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _advertising = false;
        _discovering = false;
      });
    }
  }

  Future<void> _startAdvertising() async {
    await _stop();
    setState(() {
      _status = 'Waiting for receiver…';
      _advertising = true;
    });
    try {
      await _nearby.startAdvertising(
        'PureTube',
        Strategy.P2P_CLUSTER,
        onConnectionInitiated:
            (id, info) async {
          await _nearby.acceptConnection(
            id,
            onPayLoadRecieved:
                (endpointId, payload) {},
          );
          if (mounted) {
            setState(() => _status =
                'Connected to ${info.endpointName} — sending…');
          }
          // Send the file.
          try {
            final payloadId =
                await _nearby.sendFilePayload(
                    id, widget.filePath);
            if (mounted) {
              setState(() => _status =
                  'Sending… (payload $payloadId)');
            }
          } catch (e) {
            if (mounted) {
              setState(() => _status =
                  'Send failed: $e');
            }
          }
        },
        onConnectionResult:
            (id, status) {
          if (mounted) {
            setState(() => _status =
                status == Status.CONNECTED
                    ? 'Connected!'
                    : 'Connection: $status');
          }
        },
        onDisconnected: (id) {
          if (mounted) {
            setState(
                () => _status = 'Disconnected');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _status =
            'Advertising failed: $e');
      }
    }
  }

  Future<void> _startDiscovery() async {
    await _stop();
    setState(() {
      _status = 'Searching for senders…';
      _discovering = true;
      _devices.clear();
    });
    try {
      await _nearby.startDiscovery(
        'PureTube',
        Strategy.P2P_CLUSTER,
        onEndpointFound:
            (id, name, serviceId) {
          if (mounted) {
            setState(() {
              if (!_devices.contains(id)) {
                _devices.add(id);
                _names[id] = name;
              }
              _status =
                  'Found ${_devices.length} device(s)';
            });
          }
        },
        onEndpointLost: (id) {
          if (mounted) {
            setState(() {
              _devices.remove(id);
              _names.remove(id);
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() =>
            _status = 'Discovery failed: $e');
      }
    }
  }

  Future<void> _connect(String id) async {
    setState(
        () => _status = 'Connecting…');
    try {
      await _nearby.requestConnection(
        'PureTube',
        id,
        onConnectionInitiated:
            (eid, info) async {
          await _nearby.acceptConnection(
            eid,
            onPayLoadRecieved:
                (endpointId, payload) async {
              if (payload.type ==
                  PayloadType.FILE) {
                final filePath =
                    payload.uri;
                if (filePath != null &&
                    mounted) {
                  setState(() => _status =
                      'Received: $filePath');
                  await Share.shareXFiles(
                      [XFile(filePath)],
                      text:
                          'Received via PureTube P2P');
                }
              }
            },
          );
        },
        onConnectionResult:
            (eid, status) {
          if (mounted) {
            setState(() => _status =
                status == Status.CONNECTED
                    ? 'Connected! Waiting for file…'
                    : 'Connection: $status');
          }
        },
        onDisconnected: (eid) {
          if (mounted) {
            setState(
                () => _status = 'Disconnected');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(
            () => _status = 'Failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        FileUtils.basename(widget.filePath);
    return Scaffold(
      backgroundColor:
          AppTheme.background,
      appBar: AppBar(
        backgroundColor:
            AppTheme.background,
        title:
            const Text('Share offline'),
      ),
      body: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Card(
              color: AppTheme.card,
              child: Padding(
                padding:
                    const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                        Icons
                            .insert_drive_file_outlined,
                        color:
                            AppTheme.primary),
                    const SizedBox(
                        width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(name,
                              maxLines: 2,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                              style: AppTheme
                                  .body),
                          Text(
                              'No internet needed — Wi-Fi Direct',
                              style: AppTheme
                                  .caption
                                  .copyWith(
                                      color: AppTheme
                                          .textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(
                        Icons.upload),
                    label:
                        const Text('Send'),
                    style: ElevatedButton
                        .styleFrom(
                            backgroundColor:
                                AppTheme
                                    .primary),
                    onPressed:
                        _advertising
                            ? _stop
                            : _startAdvertising,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(
                        Icons.download),
                    label: const Text(
                        'Receive'),
                    style: ElevatedButton
                        .styleFrom(
                            backgroundColor:
                                AppTheme.card),
                    onPressed:
                        _discovering
                            ? _stop
                            : _startDiscovery,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(_status,
                textAlign:
                    TextAlign.center,
                style:
                    AppTheme.body.copyWith(
                        color: AppTheme
                            .textSecondary)),
            const SizedBox(height: 12),
            if (_discovering &&
                _devices.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount:
                      _devices.length,
                  itemBuilder: (_, i) {
                    final id =
                        _devices[i];
                    return Card(
                      color: AppTheme.card,
                      child: ListTile(
                        leading: const Icon(
                            Icons
                                .phone_android_outlined,
                            color: AppTheme
                                .primary),
                        title: Text(
                            _names[id] ??
                                'Unknown device',
                            style:
                                AppTheme.body),
                        trailing: TextButton(
                          onPressed: () =>
                              _connect(id),
                          child: const Text(
                              'Connect',
                              style: TextStyle(
                                  color: AppTheme
                                      .primary)),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
