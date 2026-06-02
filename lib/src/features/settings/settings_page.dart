import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../content/data/content_repository.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../source/domain/source_catalog.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _proxyController;
  late final TextEditingController _domainController;
  late final TextEditingController _cookieController;
  String _domainSourceId = '';

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsControllerProvider);
    _proxyController = TextEditingController(text: settings.proxy);
    _domainSourceId = settings.sourceId;
    _domainController = TextEditingController(
      text: settings.userDomains[settings.sourceId] ?? '',
    );
    _cookieController = TextEditingController(
      text: settings.sourceCookies[settings.sourceId] ?? '',
    );
  }

  @override
  void dispose() {
    _proxyController.dispose();
    _domainController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final source = sourceById(settings.sourceId);
    if (_domainSourceId != source.id) {
      _domainSourceId = source.id;
      _domainController.text = settings.userDomains[source.id] ?? '';
      _cookieController.text = settings.sourceCookies[source.id] ?? '';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('网络'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _proxyController,
                    decoration: const InputDecoration(
                      labelText: '代理地址',
                      hintText: '例如 socks5://user:pass@host:port',
                      prefixIcon: Icon(Icons.route_rounded),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          _proxyController.clear();
                          await ref
                              .read(settingsControllerProvider.notifier)
                              .setProxy('');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('代理已清空')),
                            );
                          }
                        },
                        icon: const Icon(Icons.clear_rounded),
                        label: const Text('清空'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          await ref
                              .read(settingsControllerProvider.notifier)
                              .setProxy(_proxyController.text);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('代理配置已保存')),
                            );
                          }
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('保存'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '留空则不使用应用内代理；如设置了 MOVIESBOX_PROXY 环境变量，会作为运行时代理使用。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SectionTitle('播放器'),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_outline_rounded),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SegmentedButton<PlayerLaunchMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: PlayerLaunchMode.builtIn,
                              label: Text('内置'),
                              icon: Icon(Icons.smart_display_rounded),
                            ),
                            ButtonSegment(
                              value: PlayerLaunchMode.external,
                              label: Text('外置'),
                              icon: Icon(Icons.open_in_new_rounded),
                            ),
                          ],
                          selected: {settings.playerLaunchMode},
                          onSelectionChanged: (selected) {
                            ref
                                .read(settingsControllerProvider.notifier)
                                .setPlayerLaunchMode(selected.single);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: const Text('内置播放内核'),
                  subtitle: const Text('MediaKit'),
                  trailing: const Icon(Icons.check_rounded),
                ),
                SwitchListTile(
                  title: const Text('自动播放下一集'),
                  value: settings.autoPlayNext,
                  onChanged: (value) {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setAutoPlayNext(value);
                  },
                ),
              ],
            ),
          ),
          _SectionTitle('当前站点'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: Text(source.name),
                  subtitle: Text('${source.defaultDomain}\n${source.info}'),
                  isThreeLine: true,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: TextField(
                    controller: _domainController,
                    decoration: const InputDecoration(
                      labelText: '自定义站点域名',
                      hintText: '站点仅更换域名时填写；留空恢复默认',
                      prefixIcon: Icon(Icons.http_rounded),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: TextField(
                    controller: _cookieController,
                    decoration: const InputDecoration(
                      labelText: '当前站点 Cookie（覆盖用）',
                      hintText: '留空时使用默认站点 Cookie；需要自定义时再填写',
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                    obscureText: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: source.hasReleasePage
                              ? () => launchUrlString(source.releasePage)
                              : null,
                          icon: const Icon(Icons.open_in_browser_rounded),
                          label: const Text('发布页'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final controller =
                                ref.read(settingsControllerProvider.notifier);
                            await controller.setSourceDomain(
                                source.id, _domainController.text);
                            await controller.setSourceCookie(
                                source.id, _cookieController.text);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('站点配置已保存')),
                              );
                            }
                          },
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('保存站点设置'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _SectionTitle('体验'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('本地缓存'),
                  subtitle: const Text('缓存页面源码，降低重复请求'),
                  value: settings.cacheEnabled,
                  onChanged: (value) {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setCacheEnabled(value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('主题'),
                  trailing: DropdownButton<ThemeMode>(
                    value: settings.themeMode,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .setThemeMode(value);
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('跟随系统'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('明亮'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('暗色'),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清理本地缓存'),
                  onTap: () async {
                    await ref.read(contentRepositoryProvider).clearCache();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('缓存已清理')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          _SectionTitle('声明'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '所有数据来自公开网络页面，仅供学习交流。Flutter 版不提供 VIP 解析、登录绕过、DRM 绕过、Cloudflare 绕过或视频嗅探绕过功能。',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
