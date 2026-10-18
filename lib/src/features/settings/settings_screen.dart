import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../common/widgets.dart';
import '../../data/auth.dart';
import '../../data/repositories.dart';
import '../../data/sync/sync_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final household = ref.watch(householdProvider).value;
    final members = ref.watch(membersProvider).value ?? const [];
    final sync = ref.watch(syncStatusProvider);
    final theme = Theme.of(context);

    final lastSync = sync.lastSync == null
        ? 'noch nie'
        : DateFormat('d.M. HH:mm', 'de').format(sync.lastSync!);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          _Section('Haushalt'),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(household?.name ?? '…'),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(
              household?.inviteCode ?? '…',
              style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 2),
            ),
            subtitle: const Text('Einladungscode – zum Kopieren tippen'),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Neuen Code erzeugen',
              onPressed: () => _regenerateCode(context, ref),
            ),
            onTap: household == null
                ? null
                : () {
                    Clipboard.setData(
                      ClipboardData(text: household.inviteCode),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Einladungscode kopiert')),
                    );
                  },
          ),
          _Section('Mitglieder'),
          for (final m in members)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                members.nameOf(m.id) + (m.id == auth.userId ? ' (ich)' : ''),
              ),
              subtitle: Text(m.email),
            ),
          _Section('Synchronisation'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(auth.serverUrl),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Jetzt synchronisieren'),
            subtitle: Text(switch (sync.phase) {
              SyncPhase.syncing => 'Läuft …',
              SyncPhase.offline => 'Offline · zuletzt $lastSync',
              SyncPhase.error => sync.message ?? 'Fehler',
              SyncPhase.idle => 'Zuletzt $lastSync',
            }),
            onTap: () => ref.read(syncServiceProvider)?.syncNow(),
          ),
          _Section('Konto'),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(auth.user?.get<String>('name', '') ?? ''),
            subtitle: Text(auth.user?.get<String>('email', '') ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Haushalt verlassen'),
            onTap: () => _leave(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Abmelden'),
            onTap: () => ref.read(authProvider.notifier).logout(),
          ),
          const AboutSection(),
        ],
      ),
    );
  }

  Future<void> _regenerateCode(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Neuen Code erzeugen?',
      message: 'Der bisherige Einladungscode funktioniert danach nicht mehr.',
      confirm: 'Erzeugen',
    );
    if (!ok) return;
    try {
      await ref
          .read(authProvider)
          .pb
          .send('/api/casa/invite-code', method: 'POST');
      await ref.read(syncServiceProvider)?.syncNow();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Haushalt verlassen?',
      message:
          'Du siehst die gemeinsamen Listen danach nicht mehr. '
          'Mit dem Einladungscode kannst du wieder beitreten.',
      confirm: 'Verlassen',
    );
    if (!ok) return;
    try {
      await ref.read(authProvider.notifier).leaveHousehold();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }
}

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

const sourceCodeUrl = 'https://github.com/elrosch/casa-pazza';

/// App name, version, licenses and source code link.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(packageInfoProvider).value;
    final version = info == null
        ? '…'
        : '${info.version} (Build ${info.buildNumber})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section('Über'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Casa Pazza'),
          subtitle: Text('Version $version'),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('Quellcode'),
          subtitle: const Text('$sourceCodeUrl – zum Kopieren tippen'),
          onTap: () {
            Clipboard.setData(const ClipboardData(text: sourceCodeUrl));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Link kopiert')));
          },
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Lizenzen'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Casa Pazza',
            applicationVersion: version,
            applicationLegalese:
                'Freie Software unter der GNU General Public License '
                'Version 3 (GPL-3.0).\n$sourceCodeUrl',
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
