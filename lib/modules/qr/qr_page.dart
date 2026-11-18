import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import '../files/files_ui.dart' show showMessage;
import 'qr_content.dart';

const _historyKey = 'qrHistory';

/// Scan, create and review QR codes.
class QrPage extends StatefulWidget {
  const QrPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lecteur QR')),
      // Only the visible tab is built, so the camera runs only when needed.
      body: switch (_tab) {
        0 => const _ScanTab(),
        1 => const _CreateTab(),
        _ => const _HistoryTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_rounded),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2_rounded),
            label: 'Créer',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historique'),
        ],
      ),
    );
  }
}

/// Bottom sheet describing a code, with the actions that fit its content.
/// A link is always shown in full before it can be opened.
Future<void> showQrResult(BuildContext context, String raw) {
  final content = QrContent(raw);
  final text = Theme.of(context).textTheme;
  void copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    showMessage(context, '$what copié');
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content.label, style: text.labelLarge),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: SelectableText(
                  content.display,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (content.kind == QrKind.wifi) ...[
              const SizedBox(height: 6),
              if (content.wifiPassword.isNotEmpty)
                Text('Mot de passe : ${content.wifiPassword}')
              else
                const Text('Réseau ouvert (sans mot de passe)'),
              if (content.wifi['H']?.toLowerCase() == 'true')
                const Text('Réseau masqué'),
            ],
            if (content.kind == QrKind.sms && content.sms.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(content.sms.body),
            ],
            if (content.contact != null) ...[
              const SizedBox(height: 6),
              for (final line in [
                if (content.contact!.organization.isNotEmpty)
                  content.contact!.organization,
                ...content.contact!.phones,
                ...content.contact!.emails,
                if (content.contact!.address.isNotEmpty)
                  content.contact!.address,
                if (content.contact!.url.isNotEmpty) content.contact!.url,
              ])
                Text(line),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (content.kind == QrKind.url ||
                    content.kind == QrKind.email ||
                    content.kind == QrKind.phone)
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(switch (content.kind) {
                      QrKind.email => 'Écrire',
                      QrKind.phone => 'Appeler',
                      _ => 'Ouvrir le lien',
                    }),
                    onPressed: () async {
                      Navigator.pop(sheet);
                      final ok = await launchUrl(
                        Uri.parse(content.raw.trim()),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!ok && context.mounted) {
                        showMessage(
                          context,
                          "Aucune application pour l'ouvrir",
                        );
                      }
                    },
                  ),
                if (content.kind == QrKind.wifi)
                  FilledButton.icon(
                    icon: const Icon(Icons.wifi, size: 18),
                    label: const Text('Se connecter'),
                    onPressed: () async {
                      Navigator.pop(sheet);
                      final type = (content.wifi['T'] ?? 'WPA').toUpperCase();
                      final ok = await MediaChannel.addWifi(
                        ssid: content.wifiName,
                        password: content.wifiPassword,
                        security: type == 'WEP'
                            ? 'wep'
                            : (type == 'NOPASS' || content.wifiPassword.isEmpty)
                            ? 'open'
                            : 'wpa',
                        hidden: content.wifi['H']?.toLowerCase() == 'true',
                      );
                      if (ok || !context.mounted) return;
                      // Older phones (or WEP): the password is copied and the
                      // Wi-Fi settings opened.
                      if (content.wifiPassword.isNotEmpty) {
                        Clipboard.setData(
                          ClipboardData(text: content.wifiPassword),
                        );
                      }
                      showMessage(
                        context,
                        content.wifiPassword.isEmpty
                            ? 'Choisissez le réseau dans les réglages Wi-Fi'
                            : 'Mot de passe copié : collez-le dans les réglages Wi-Fi',
                      );
                      await MediaChannel.openWifiSettings();
                    },
                  ),
                if (content.kind == QrKind.contact && content.contact != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Ajouter aux contacts'),
                    onPressed: () async {
                      Navigator.pop(sheet);
                      final c = content.contact!;
                      final ok = await MediaChannel.addContact(
                        name: c.name,
                        phone: c.phones.firstOrNull,
                        email: c.emails.firstOrNull,
                        company: c.organization,
                        address: c.address,
                      );
                      if (!ok && context.mounted) {
                        showMessage(
                          context,
                          "Impossible d'ouvrir les contacts",
                        );
                      }
                    },
                  ),
                if (content.kind == QrKind.sms)
                  FilledButton.icon(
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: const Text('Écrire le SMS'),
                    onPressed: () async {
                      Navigator.pop(sheet);
                      final m = content.sms;
                      await launchUrl(
                        Uri(
                          scheme: 'sms',
                          path: m.number,
                          queryParameters: m.body.isEmpty
                              ? null
                              : {'body': m.body},
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                if (content.geo != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Voir sur la carte'),
                    onPressed: () async {
                      Navigator.pop(sheet);
                      final ok = await launchUrl(
                        Uri.parse(content.raw.trim()),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!ok && context.mounted) {
                        showMessage(context, "Aucune application de cartes");
                      }
                    },
                  ),
                if (content.kind == QrKind.wifi &&
                    content.wifiPassword.isNotEmpty)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.key, size: 18),
                    label: const Text('Copier le mot de passe'),
                    onPressed: () {
                      Navigator.pop(sheet);
                      copy(content.wifiPassword, 'Mot de passe');
                    },
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copier'),
                  onPressed: () {
                    Navigator.pop(sheet);
                    copy(content.display, 'Contenu');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Partager'),
                  onPressed: () {
                    Navigator.pop(sheet);
                    SharePlus.instance.share(ShareParams(text: content.raw));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ScanTab extends StatefulWidget {
  const _ScanTab();

  @override
  State<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<_ScanTab> {
  final _scanner = MobileScannerController();
  bool _showing = false;
  bool _torch = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  /// Reads a code from a picture instead of the camera.
  Future<void> _fromImage() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile();
    } on Object {
      return;
    }
    final path = picked?.path;
    if (path == null || !mounted) return;
    BarcodeCapture? capture;
    try {
      capture = await _scanner.analyzeImage(path);
    } on Object {
      capture = null;
    }
    if (!mounted) return;
    if (capture == null || capture.barcodes.isEmpty) {
      showMessage(context, 'Aucun code trouvé dans cette image');
      return;
    }
    await _onDetect(capture);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_showing) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;
    _showing = true;
    HapticFeedback.mediumImpact();
    final settings = context.read<AppSettings>();
    settings.setList(
      _historyKey,
      [
        raw,
        ...settings.list(_historyKey).where((v) => v != raw),
      ].take(50).toList(),
    );
    await _scanner.stop();
    if (!mounted) return;
    await showQrResult(context, raw);
    _showing = false;
    if (mounted) await _scanner.start();
  }

  Widget _torchButton() => IconButton.filledTonal(
    tooltip: 'Lampe',
    iconSize: 28,
    icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded),
    onPressed: () async {
      await _scanner.toggleTorch();
      setState(() => _torch = !_torch);
    },
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          errorBuilder: (context, error) => ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? "L'accès à l'appareil photo est nécessaire pour scanner un code."
                          : "L'appareil photo n'est pas disponible.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Viewfinder frame
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 28,
          child: Column(
            children: [
              const Text(
                'Placez le code dans le cadre',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6)],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Lire un code depuis une image',
                    iconSize: 28,
                    icon: const Icon(Icons.image_search_rounded),
                    onPressed: _fromImage,
                  ),
                  const SizedBox(width: 16),
                  _torchButton(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateTab extends StatefulWidget {
  const _CreateTab();

  @override
  State<_CreateTab> createState() => _CreateTabState();
}

enum _Kind { text, wifi, contact }

class _CreateTabState extends State<_CreateTab> {
  _Kind _kind = _Kind.text;
  WifiSecurity _security = WifiSecurity.wpa;
  bool _hidden = false;
  final _text = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _qrKey = GlobalKey();

  @override
  void dispose() {
    for (final c in [_text, _password, _phone, _email, _company]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _data {
    final value = _text.text.trim();
    if (value.isEmpty) return '';
    return switch (_kind) {
      _Kind.text => value,
      _Kind.wifi => wifiCode(
        value,
        _password.text,
        security: _security,
        hidden: _hidden,
      ),
      _Kind.contact => vcardCode(
        QrContact(
          name: value,
          phones: [if (_phone.text.trim().isNotEmpty) _phone.text.trim()],
          emails: [if (_email.text.trim().isNotEmpty) _email.text.trim()],
          organization: _company.text.trim(),
        ),
      ),
    };
  }

  /// Renders the code to a PNG file and opens the share sheet.
  Future<void> _share() async {
    final boundary =
        _qrKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${Directory.systemTemp.path}/code-qr.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Widget _field(
    TextEditingController c,
    String hint, {
    TextInputType? type,
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: c,
      onChanged: (_) => setState(() {}),
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        SegmentedButton<_Kind>(
          segments: const [
            ButtonSegment(
              value: _Kind.text,
              icon: Icon(Icons.link),
              label: Text('Texte'),
            ),
            ButtonSegment(
              value: _Kind.wifi,
              icon: Icon(Icons.wifi),
              label: Text('Wi-Fi'),
            ),
            ButtonSegment(
              value: _Kind.contact,
              icon: Icon(Icons.contact_page_outlined),
              label: Text('Contact'),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          onChanged: (_) => setState(() {}),
          maxLines: _kind == _Kind.text ? 3 : 1,
          minLines: 1,
          decoration: InputDecoration(
            hintText: switch (_kind) {
              _Kind.text => 'Texte, lien, numéro…',
              _Kind.wifi => 'Nom du réseau',
              _Kind.contact => 'Nom complet',
            },
          ),
        ),
        if (_kind == _Kind.wifi) ...[
          _field(_password, 'Mot de passe (vide si réseau ouvert)'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final (label, sec) in const [
                ('WPA / WPA2', WifiSecurity.wpa),
                ('WEP', WifiSecurity.wep),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _security == sec,
                  onSelected: (_) => setState(() => _security = sec),
                ),
              FilterChip(
                label: const Text('Réseau masqué'),
                selected: _hidden,
                onSelected: (v) => setState(() => _hidden = v),
              ),
            ],
          ),
        ],
        if (_kind == _Kind.contact) ...[
          _field(
            _phone,
            'Téléphone',
            type: TextInputType.phone,
            icon: Icons.phone_outlined,
          ),
          _field(
            _email,
            'E-mail',
            type: TextInputType.emailAddress,
            icon: Icons.mail_outline,
          ),
          _field(_company, 'Société', icon: Icons.business_outlined),
        ],
        const SizedBox(height: 24),
        if (data.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Le code apparaîtra ici.')),
          )
        else ...[
          Center(
            child: RepaintBoundary(
              key: _qrKey,
              // Always black on white so any scanner can read it.
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: data,
                  size: 240,
                  errorStateBuilder: (_, _) => const SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(
                      child: Text('Texte trop long pour un code QR'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text("Partager l'image"),
            ),
          ),
        ],
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final history = settings.list(_historyKey);
    if (history.isEmpty) {
      return const Center(child: Text('Les codes scannés apparaîtront ici.'));
    }
    return ListView(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => settings.setList(_historyKey, const []),
            child: const Text("Effacer l'historique"),
          ),
        ),
        for (final raw in history)
          Builder(
            builder: (context) {
              final content = QrContent(raw);
              return ListTile(
                leading: Icon(switch (content.kind) {
                  QrKind.url => Icons.link,
                  QrKind.wifi => Icons.wifi,
                  QrKind.email => Icons.mail_outline,
                  QrKind.phone => Icons.phone_outlined,
                  QrKind.sms => Icons.sms_outlined,
                  QrKind.geo => Icons.place_outlined,
                  QrKind.contact => Icons.contact_page_outlined,
                  QrKind.text => Icons.notes,
                }),
                title: Text(
                  content.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(content.label),
                onTap: () => showQrResult(context, raw),
              );
            },
          ),
      ],
    );
  }
}
