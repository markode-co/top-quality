import 'package:flutter/material.dart';

class PreferenceOption<T> {
  const PreferenceOption({
    required this.value,
    required this.label,
    required this.icon,
    this.description,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? description;
}

class PreferenceChoiceGroup<T> extends StatelessWidget {
  const PreferenceChoiceGroup({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final T value;
  final List<PreferenceOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    PreferenceOption<T>? selectedOption;
    for (final option in options) {
      if (option.value == value) {
        selectedOption = option;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in options)
              ChoiceChip(
                selected: option.value == value,
                showCheckmark: false,
                avatar: Icon(
                  option.icon,
                  size: 18,
                  color: option.value == value
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                label: Text(option.label),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: option.value == value
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
                backgroundColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                selectedColor: scheme.primaryContainer.withValues(alpha: 0.75),
                side: BorderSide(
                  color: option.value == value
                      ? scheme.primary.withValues(alpha: 0.3)
                      : scheme.outlineVariant.withValues(alpha: 0.65),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                onSelected: (_) => onChanged(option.value),
              ),
          ],
        ),
        if ((selectedOption?.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            selectedOption!.description!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
