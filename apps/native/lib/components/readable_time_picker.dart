import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';

Future<TimeOfDay?> showReadableTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    cancelText: context.l10n.cancel,
    confirmText: context.l10n.accept,
    builder: (context, child) {
      // Material 3 places the 24-hour values on two rings only 28 logical
      // pixels apart, while its selected marker is 48 pixels wide. The
      // single-ring dial avoids covering the hour on the neighboring ring and
      // also provides a larger 280-pixel clock face.
      final appTheme = Theme.of(context);
      final pickerTheme =
          ThemeData.from(
            colorScheme: appTheme.colorScheme,
            textTheme: appTheme.textTheme,
            useMaterial3: false,
          ).copyWith(
            timePickerTheme: appTheme.timePickerTheme,
            textButtonTheme: appTheme.textButtonTheme,
          );
      return Theme(data: pickerTheme, child: child!);
    },
  );
}
