import 'package:flutter/material.dart';

import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../platform/alarm_channel.dart';
import '../../services/controller.dart';
import 'common.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  AlarmPermissionStatus? status;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    try {
      final value = await AlarmChannel.getPermissionStatus();
      if (mounted) setState(() => status = value);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> request(String which) async {
    try {
      await AlarmChannel.requestPermission(which);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const PushedHeader(title: 'Permissions'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                ShowdSpace.gutter,
                ShowdSpace.s4,
                ShowdSpace.gutter,
                ShowdSpace.s8,
              ),
              children: [
                Text('Make alarms reliable.', style: ShowdType.titleXL),
                const SizedBox(height: ShowdSpace.s2),
                Text(
                  'Each one has one job. Change any of them later in Android settings.',
                  style: ShowdType.bodyM,
                ),
                const SizedBox(height: ShowdSpace.s6),
                if (error != null) ShowdNotice(error!),
                _row(
                  'Notifications',
                  'So reminders and live progress can show.',
                  'notifications',
                  status?.notifications,
                ),
                _row(
                  'Exact alarms',
                  'So Android rings on time instead of late.',
                  'exactAlarm',
                  status?.exactAlarm,
                ),
                _row(
                  'Precise location',
                  'Only for Gym, places and GPS walks. Only while tracking runs.',
                  'location',
                  status?.location,
                ),
                _row(
                  'Battery',
                  'Allow unrestricted use so tracking keeps going.',
                  'battery',
                  status == null ? null : !status!.batteryOptimised,
                ),
                _row(
                  'Full-screen alarms',
                  'Optional. A notification still rings without it.',
                  'fullScreenIntent',
                  status?.fullScreenIntent,
                ),
                _row(
                  'Autostart',
                  'Xiaomi, Redmi, Realme, Oppo and Vivo phones need this for alarms after a restart.',
                  'autostart',
                  null,
                  action: 'Open',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _row(
    String title,
    String body,
    String which,
    bool? granted, {
    String? action,
  }) => ShowdRow(
    onTap: () => request(which),
    leading: ShowdIcon(
      granted == true ? ShowdIcons.check : ShowdIcons.bell,
      color: granted == true ? ShowdColors.accent : ShowdColors.stone,
    ),
    title: title,
    subtitle: body,
    trailing: Text(
      action ?? (granted == true ? 'On' : 'Allow'),
      style: ShowdType.bodyM.copyWith(
        color: granted == true ? ShowdColors.stone : ShowdColors.accent,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
