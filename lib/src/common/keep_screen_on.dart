import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _channel = MethodChannel('casa_pazza/screen');

Future<void> _setKeepScreenOn(bool on) async {
  if (kIsWeb) return;
  try {
    await _channel.invokeMethod<void>('keepOn', on);
  } on MissingPluginException {
    // Tests and platforms without the channel: nothing to do.
  } on PlatformException catch (e) {
    debugPrint('keep screen on failed: $e');
  }
}

/// Keeps the device screen on while [active] and this widget is visible
/// (not in an inactive tab).
class KeepScreenOn extends StatefulWidget {
  const KeepScreenOn({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends State<KeepScreenOn> {
  bool? _applied;

  void _apply() {
    // Inactive tabs of the bottom navigation have tickers disabled.
    final on = widget.active && TickerMode.valuesOf(context).enabled;
    if (on == _applied) return;
    _applied = on;
    _setKeepScreenOn(on);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  @override
  void didUpdateWidget(KeepScreenOn oldWidget) {
    super.didUpdateWidget(oldWidget);
    _apply();
  }

  @override
  void dispose() {
    if (_applied == true) _setKeepScreenOn(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
