import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// How the camera picture is shown, to read small print more easily.
enum LoupeMode {
  normal('Normal', null),
  contrast('Contraste', _contrast),
  inverted('Inversé', _inverted),
  mono('Noir et blanc', _mono);

  const LoupeMode(this.label, this.filter);
  final String label;
  final ColorFilter? filter;
}

const _contrast = ColorFilter.matrix(<double>[
  1.8, 0, 0, 0, -100, //
  0, 1.8, 0, 0, -100,
  0, 0, 1.8, 0, -100,
  0, 0, 0, 1, 0,
]);

const _inverted = ColorFilter.matrix(<double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255,
  0, 0, -1, 0, 255,
  0, 0, 0, 1, 0,
]);

const _mono = ColorFilter.matrix(<double>[
  0.9, 0.9, 0.9, 0, -80, //
  0.9, 0.9, 0.9, 0, -80,
  0.9, 0.9, 0.9, 0, -80,
  0, 0, 0, 1, 0,
]);

/// A magnifying glass: the camera picture, zoomed, with the lamp and a
/// few reading filters.
class LoupeView extends StatefulWidget {
  const LoupeView({super.key});

  @override
  State<LoupeView> createState() => _LoupeState();
}

class _LoupeState extends State<LoupeView> {
  final _camera = MobileScannerController(
    // Codes are not wanted here: no detection work.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  double _zoom = 0.3;
  bool _torch = false;
  LoupeMode _mode = LoupeMode.normal;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _setZoom(double z) {
    setState(() => _zoom = z.clamp(0.0, 1.0));
    _camera.setZoomScale(_zoom);
  }

  @override
  void initState() {
    super.initState();
    // Applies the starting zoom once the camera is running.
    _camera.start().then((_) {
      if (mounted) _camera.setZoomScale(_zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ColorFiltered(
            colorFilter:
                _mode.filter ??
                const ColorFilter.mode(Colors.transparent, BlendMode.dst),
            child: MobileScanner(
              controller: _camera,
              errorBuilder: (context, error) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? "L'accès à l'appareil photo est nécessaire pour la loupe."
                          : "L'appareil photo n'est pas disponible.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Réduire le zoom',
                      icon: const Icon(Icons.zoom_out),
                      onPressed: () => _setZoom(_zoom - 0.1),
                    ),
                    Expanded(
                      child: Slider(
                        value: _zoom,
                        label: 'Zoom ${(1 + _zoom * 7).toStringAsFixed(1)}×',
                        onChanged: _setZoom,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Augmenter le zoom',
                      icon: const Icon(Icons.zoom_in),
                      onPressed: () => _setZoom(_zoom + 0.1),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Lampe',
                      icon: Icon(
                        _torch
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                      ),
                      onPressed: () async {
                        await _camera.toggleTorch();
                        setState(() => _torch = !_torch);
                      },
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in LoupeMode.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: m == _mode,
                        onSelected: (_) => setState(() => _mode = m),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
