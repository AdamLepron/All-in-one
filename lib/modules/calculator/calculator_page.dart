import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import 'evaluator.dart';

const _standardKeys = [
  ['AC', '( )', '%', '÷'],
  ['7', '8', '9', '×'],
  ['4', '5', '6', '−'],
  ['1', '2', '3', '+'],
  ['0', ',', '⌫', '='],
];

const _scientificKeys = [
  'sin',
  'cos',
  'tan',
  'ln',
  'log',
  '√',
  '^',
  'π',
  'e',
  '!',
];
const _operators = ['÷', '×', '−', '+', '^'];

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  String _expr = '';
  bool _scientific = false;
  bool _degrees = true;

  /// True right after "=", so the next digit starts a new calculation.
  bool _justEvaluated = false;

  String? get _preview {
    if (_expr.isEmpty || double.tryParse(_expr.replaceAll(',', '.')) != null) {
      return null;
    }
    try {
      final v = evaluate(_expr, degrees: _degrees);
      return v.isNaN ? null : formatNumber(v);
    } on FormatException {
      return null;
    }
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (key) {
        case 'AC':
          _expr = '';
        case '⌫':
          if (_expr.isNotEmpty) {
            final fn = [
              'sin(',
              'cos(',
              'tan(',
              'log(',
              'ln(',
            ].where(_expr.endsWith);
            _expr = _expr.substring(
              0,
              _expr.length - (fn.isEmpty ? 1 : fn.first.length),
            );
          }
        case '=':
          _evaluate();
          return;
        case '( )':
          _expr += _nextParenthesis();
        case 'sin' || 'cos' || 'tan' || 'ln' || 'log':
          _startFresh();
          _expr += '$key(';
        default:
          if (_operators.contains(key)) {
            if (_expr.isEmpty) {
              if (key != '−') return;
            } else if (_operators.contains(_expr[_expr.length - 1])) {
              _expr = _expr.substring(0, _expr.length - 1);
            }
          } else if (key != '%' && key != '!') {
            _startFresh();
          }
          _expr += key;
      }
      _justEvaluated = false;
    });
  }

  void _startFresh() {
    if (_justEvaluated) _expr = '';
  }

  String _nextParenthesis() {
    final open = '('.allMatches(_expr).length - ')'.allMatches(_expr).length;
    if (_expr.isEmpty) return '(';
    final last = _expr[_expr.length - 1];
    final afterValue = RegExp(r'[0-9)πe%!]').hasMatch(last);
    return open > 0 && afterValue ? ')' : '(';
  }

  void _evaluate() {
    if (_expr.isEmpty) return;
    try {
      final v = evaluate(_expr, degrees: _degrees);
      final result = formatNumber(v);
      if (!v.isNaN) {
        context.read<AppSettings>().addCalcHistory('$_expr = $result');
      }
      _expr = v.isNaN ? '' : result.replaceAll(' ', '').replaceAll('-', '−');
      _justEvaluated = true;
      if (v.isNaN) _showError();
    } on FormatException {
      _showError();
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Expression incorrecte'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final scheme = Theme.of(context).colorScheme;
    final display = _Display(expression: _expr, preview: _preview);
    final standard = _KeyGrid(
      rows: _standardKeys,
      onPressed: _press,
      onLongPressBackspace: () => _press('AC'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculatrice'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _degrees = !_degrees),
            child: Text(_degrees ? 'DEG' : 'RAD'),
          ),
          if (!landscape)
            IconButton(
              tooltip: 'Mode scientifique',
              isSelected: _scientific,
              icon: const Icon(Icons.functions),
              selectedIcon: Icon(Icons.functions, color: scheme.primary),
              onPressed: () => setState(() => _scientific = !_scientific),
            ),
          IconButton(
            tooltip: 'Historique',
            icon: const Icon(Icons.history),
            onPressed: _showHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: landscape
              ? Row(
                  children: [
                    Expanded(flex: 4, child: display),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _KeyGrid(
                        rows: [
                          for (var i = 0; i < 5; i++)
                            _scientificKeys.sublist(i * 2, i * 2 + 2),
                        ],
                        onPressed: _press,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 6, child: standard),
                  ],
                )
              : Column(
                  children: [
                    Expanded(flex: 3, child: display),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _scientific
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SizedBox(
                                height: 96,
                                child: _KeyGrid(
                                  rows: [
                                    _scientificKeys.sublist(0, 5),
                                    _scientificKeys.sublist(5),
                                  ],
                                  onPressed: _press,
                                  compact: true,
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    Expanded(flex: 7, child: standard),
                  ],
                ),
        ),
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => Consumer<AppSettings>(
        builder: (context, settings, _) {
          final history = settings.calcHistory;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    'Historique',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  trailing: history.isEmpty
                      ? null
                      : TextButton(
                          onPressed: settings.clearCalcHistory,
                          child: const Text('Effacer'),
                        ),
                ),
                if (history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Vos calculs apparaîtront ici'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: history.length,
                      itemBuilder: (_, i) {
                        final parts = history[i].split(' = ');
                        return ListTile(
                          title: Text(
                            parts.last,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(parts.first),
                          onTap: () {
                            Navigator.pop(sheet);
                            setState(() {
                              _expr = parts.last
                                  .replaceAll(' ', '')
                                  .replaceAll('-', '−');
                              _justEvaluated = true;
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Display extends StatelessWidget {
  const _Display({required this.expression, required this.preview});
  final String expression;
  final String? preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.bottomRight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                expression.isEmpty ? '0' : expression,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w300,
                  color: expression.isEmpty ? scheme.outline : scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                preview == null ? '' : '= $preview',
                style: TextStyle(fontSize: 26, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyGrid extends StatelessWidget {
  const _KeyGrid({
    required this.rows,
    required this.onPressed,
    this.onLongPressBackspace,
    this.compact = false,
  });

  final List<List<String>> rows;
  final ValueChanged<String> onPressed;
  final VoidCallback? onLongPressBackspace;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 3 : 5),
                      child: _Key(
                        label: key,
                        compact: compact,
                        colors: _colorsFor(key, scheme),
                        onPressed: () => onPressed(key),
                        onLongPress: key == '⌫' ? onLongPressBackspace : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  (Color, Color) _colorsFor(String key, ColorScheme s) {
    if (key == '=') return (s.primary, s.onPrimary);
    if (_operators.contains(key)) {
      return (s.primaryContainer, s.onPrimaryContainer);
    }
    if (compact || const ['AC', '( )', '%', '⌫'].contains(key)) {
      return (s.surfaceContainerHighest, s.onSurface);
    }
    return (s.surfaceContainer, s.onSurface);
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.colors,
    required this.onPressed,
    this.onLongPress,
    this.compact = false,
  });

  final String label;
  final (Color, Color) colors;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.$1,
      borderRadius: BorderRadius.circular(compact ? 16 : 28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        child: Center(
          child: label == '⌫'
              ? Icon(Icons.backspace_outlined, color: colors.$2)
              : FittedBox(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: compact ? 18 : 28,
                      fontWeight: FontWeight.w500,
                      color: colors.$2,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
