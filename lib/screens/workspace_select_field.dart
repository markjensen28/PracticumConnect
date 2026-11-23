import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class WorkspaceSelectField extends FormField<String> {
  WorkspaceSelectField({
    super.key,
    required String label,
    required List<String> options,
    String? initialValue,
    String hint = 'Select an option',
    ValueChanged<String>? onChanged,
    super.onSaved,
    super.validator,
    super.enabled = true,
  }) : super(
         initialValue: options.contains(initialValue) ? initialValue : null,
         autovalidateMode: AutovalidateMode.onUserInteraction,
         builder: (field) => LayoutBuilder(
           builder: (context, constraints) => MenuAnchor(
             crossAxisUnconstrained: false,
             alignmentOffset: const Offset(0, 6),
             style: MenuStyle(
               backgroundColor: const WidgetStatePropertyAll(AppTheme.surface),
               surfaceTintColor: const WidgetStatePropertyAll(
                 Colors.transparent,
               ),
               elevation: const WidgetStatePropertyAll(5),
               padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
               minimumSize: WidgetStatePropertyAll(
                 Size(constraints.maxWidth, 0),
               ),
               maximumSize: WidgetStatePropertyAll(
                 Size(constraints.maxWidth, 320),
               ),
               shape: WidgetStatePropertyAll(
                 RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                   side: const BorderSide(color: AppTheme.border),
                 ),
               ),
             ),
             menuChildren: [
               for (final option in options)
                 MenuItemButton(
                   style: MenuItemButton.styleFrom(
                     alignment: AlignmentDirectional.centerStart,
                     minimumSize: const Size(0, 46),
                     padding: const EdgeInsets.symmetric(
                       horizontal: 12,
                       vertical: 8,
                     ),
                     backgroundColor: field.value == option
                         ? AppTheme.surfaceBlue
                         : null,
                     foregroundColor: field.value == option
                         ? AppTheme.deepBlue
                         : AppTheme.text,
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(
                         AppTheme.controlRadius,
                       ),
                     ),
                   ),
                   onPressed: enabled
                       ? () {
                           field.didChange(option);
                           onChanged?.call(option);
                         }
                       : null,
                   child: Semantics(
                     selected: field.value == option,
                     child: Row(
                       spacing: 12,
                       children: [
                         Expanded(child: Text(option)),
                         Icon(
                           field.value == option
                               ? Icons.radio_button_checked_rounded
                               : Icons.radio_button_unchecked_rounded,
                           size: 19,
                           color: field.value == option
                               ? AppTheme.blue
                               : AppTheme.subtle,
                         ),
                       ],
                     ),
                   ),
                 ),
             ],
             builder: (context, controller, _) => Column(
               crossAxisAlignment: CrossAxisAlignment.stretch,
               mainAxisSize: MainAxisSize.min,
               children: [
                 Semantics(
                   expanded: controller.isOpen,
                   child: OutlinedButton(
                     onPressed: enabled
                         ? () => controller.isOpen
                               ? controller.close()
                               : controller.open()
                         : null,
                     style:
                         OutlinedButton.styleFrom(
                           minimumSize: const Size(0, 54),
                           alignment: AlignmentDirectional.centerStart,
                           padding: const EdgeInsets.symmetric(
                             horizontal: 14,
                             vertical: 9,
                           ),
                         ).copyWith(
                           side: WidgetStateProperty.resolveWith(
                             (states) => BorderSide(
                               color: field.hasError
                                   ? AppTheme.danger
                                   : controller.isOpen ||
                                         states.contains(WidgetState.focused)
                                   ? AppTheme.blue
                                   : AppTheme.border,
                               width:
                                   controller.isOpen ||
                                       states.contains(WidgetState.focused)
                                   ? 1.5
                                   : 1,
                             ),
                           ),
                         ),
                     child: Row(
                       spacing: 12,
                       children: [
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               Text(
                                 label,
                                 style: Theme.of(context).textTheme.bodySmall,
                               ),
                               const SizedBox(height: 2),
                               Text(
                                 field.value ?? hint,
                                 style: TextStyle(
                                   color: !enabled || field.value == null
                                       ? AppTheme.muted
                                       : AppTheme.navy,
                                 ),
                               ),
                             ],
                           ),
                         ),
                         Icon(
                           controller.isOpen
                               ? Icons.keyboard_arrow_up_rounded
                               : Icons.keyboard_arrow_down_rounded,
                           color: AppTheme.blue,
                           size: 21,
                         ),
                       ],
                     ),
                   ),
                 ),
                 if (field.errorText case final error?)
                   Padding(
                     padding: const EdgeInsets.fromLTRB(14, 5, 14, 0),
                     child: Semantics(
                       liveRegion: true,
                       child: Text(
                         error,
                         style: const TextStyle(
                           color: AppTheme.danger,
                           fontSize: AppTheme.fontCaption,
                         ),
                       ),
                     ),
                   ),
               ],
             ),
           ),
         ),
       );
}
