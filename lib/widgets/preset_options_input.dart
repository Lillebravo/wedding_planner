import 'package:flutter/material.dart';

class PresetOptionsInput extends StatefulWidget {
  final String labelText;
  final String hintText;
  final List<String> options;
  final List<String> selectedValues;
  final ValueChanged<List<String>> onChanged;
  final bool multiSelect;
  final bool allowCustom;

  const PresetOptionsInput({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.multiSelect = true,
    this.allowCustom = true,
  });

  @override
  State<PresetOptionsInput> createState() => _PresetOptionsInputState();
}

class _PresetOptionsInputState extends State<PresetOptionsInput> {
  static const double _optionTileHeight = 48;

  TextEditingController? _inputController;
  final ScrollController _optionsScrollController = ScrollController();
  int _lastHighlightedIndex = -1;
  List<String> _lastVisibleOptions = const <String>[];

  bool _containsValue(List<String> values, String candidate) {
    final normalizedCandidate = candidate.trim().toLowerCase();
    return values.any((value) => value.trim().toLowerCase() == normalizedCandidate);
  }

  void _addValue(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return;
    }

    final selected = List<String>.from(widget.selectedValues);
    if (_containsValue(selected, value)) {
      _inputController?.clear();
      return;
    }

    if (widget.multiSelect) {
      selected.add(value);
    } else {
      selected
        ..clear()
        ..add(value);
    }

    widget.onChanged(selected);
    _inputController?.clear();
  }

  void _removeValue(String value) {
    final selected = List<String>.from(widget.selectedValues)
      ..removeWhere((item) => item.trim().toLowerCase() == value.trim().toLowerCase());
    widget.onChanged(selected);
  }

  void _submitFromKeyboard(String rawValue) {
    final highlightedIndex = _lastHighlightedIndex;
    if (highlightedIndex >= 0 && highlightedIndex < _lastVisibleOptions.length) {
      _addValue(_lastVisibleOptions[highlightedIndex]);
      return;
    }

    final value = rawValue.trim();
    if (value.isEmpty) {
      return;
    }

    if (!widget.allowCustom && !_containsValue(widget.options, value)) {
      return;
    }

    _addValue(value);
  }

  void _ensureHighlightedOptionVisible(int index) {
    if (!_optionsScrollController.hasClients) {
      return;
    }

    final position = _optionsScrollController.position;
    final itemTop = index * _optionTileHeight;
    final itemBottom = itemTop + _optionTileHeight;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;

    double? targetOffset;
    if (itemTop < viewportTop) {
      targetOffset = itemTop;
    } else if (itemBottom > viewportBottom) {
      targetOffset = itemBottom - position.viewportDimension;
    }

    if (targetOffset == null) {
      return;
    }

    final clampedOffset = targetOffset.clamp(0.0, position.maxScrollExtent);
    _optionsScrollController.jumpTo(clampedOffset);
  }

  @override
  void dispose() {
    _optionsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selectedValues.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedValues
                .map(
                  (value) => InputChip(
                    label: Text(value),
                    onDeleted: () => _removeValue(value),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        Autocomplete<String>(
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            return widget.options.where((option) {
              if (_containsValue(widget.selectedValues, option)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              return option.toLowerCase().contains(query);
            });
          },
          displayStringForOption: (option) => option,
          onSelected: _addValue,
          fieldViewBuilder:
              (context, controller, focusNode, onFieldSubmitted) {
                _inputController = controller;

                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: widget.labelText,
                    hintText: widget.hintText,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        if (!widget.allowCustom &&
                            !_containsValue(widget.options, controller.text)) {
                          return;
                        }
                        _addValue(controller.text);
                      },
                    ),
                  ),
                      onSubmitted: _submitFromKeyboard,
                );
              },
          optionsViewBuilder: (context, onSelected, options) {
            final visibleOptions = options.toList();
            if (visibleOptions.isEmpty) {
              _lastHighlightedIndex = -1;
                  _lastVisibleOptions = const <String>[];
              return const SizedBox.shrink();
            }

                _lastVisibleOptions = visibleOptions;
            final highlightedIndex = AutocompleteHighlightedOption.of(context);
            if (highlightedIndex != _lastHighlightedIndex) {
              _lastHighlightedIndex = highlightedIndex;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                _ensureHighlightedOptionVisible(highlightedIndex);
              });
            }

            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, minWidth: 220),
                  child: ListView.builder(
                    controller: _optionsScrollController,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: visibleOptions.length,
                    itemBuilder: (context, index) {
                      final option = visibleOptions[index];
                      final isHighlighted = highlightedIndex == index;

                      return ListTile(
                        dense: true,
                        selected: isHighlighted,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12),
                        title: Text(option),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
