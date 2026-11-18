import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/util.dart';
import 'units.dart';

class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  UnitCategory _category = unitCategories.first;
  late Unit _from = _category.units[0];
  late Unit _to = _category.units[1];
  final _input = TextEditingController(text: '1');

  double? get _value => double.tryParse(_input.text.replaceAll(',', '.'));

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _selectCategory(UnitCategory c) => setState(() {
    _category = c;
    _from = c.units[0];
    _to = c.units[1];
  });

  void _swap() {
    final value = _value;
    setState(() {
      if (value != null) {
        _input.text = formatNumber(convert(value, _from, _to))
            .replaceAll(' ', '');
      }
      final previous = _from;
      _from = _to;
      _to = previous;
    });
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('$text copié'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final value = _value;
    final result = value == null
        ? '—'
        : formatNumber(convert(value, _from, _to));

    return Scaffold(
      appBar: AppBar(title: const Text('Convertisseur')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: unitCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = unitCategories[i];
                return ChoiceChip(
                  avatar: Icon(c.icon, size: 18),
                  showCheckmark: false,
                  label: Text(c.name),
                  selected: c == _category,
                  onSelected: (_) => _selectCategory(c),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _UnitPicker(
                      units: _category.units,
                      value: _from,
                      onChanged: (u) => setState(() => _from = u),
                    ),
                    TextField(
                      controller: _input,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                      ],
                      style: text.displaySmall,
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        hintText: '0',
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        IconButton.filledTonal(
                          tooltip: 'Inverser',
                          onPressed: _swap,
                          icon: const Icon(Icons.swap_vert),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    _UnitPicker(
                      units: _category.units,
                      value: _to,
                      onChanged: (u) => setState(() => _to = u),
                    ),
                    InkWell(
                      onTap: value == null ? null : () => _copy(result),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: double.infinity,
                          minHeight: 48,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            result,
                            style: text.displaySmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'Toutes les unités',
              style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final unit in _category.units)
            if (unit != _from)
              ListTile(
                dense: true,
                title: Text(unit.name),
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.48,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      value == null
                          ? '—'
                          : '${formatNumber(convert(value, _from, unit))} ${unit.symbol}',
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                onTap: () => setState(() => _to = unit),
              ),
        ],
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({
    required this.units,
    required this.value,
    required this.onChanged,
  });

  final List<Unit> units;
  final Unit value;
  final ValueChanged<Unit> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final u in units)
                ListTile(
                  title: Text(u.name),
                  trailing: Text(u.symbol),
                  selected: u == value,
                  onTap: () {
                    Navigator.pop(sheet);
                    onChanged(u);
                  },
                ),
            ],
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '${value.name} (${value.symbol})',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
