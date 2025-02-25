import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:ffmpeg_kit_flutter_full/return_code.dart';
import 'package:filesize/filesize.dart';
import 'package:filesystem_dac/dac.dart';
import 'package:flutter/services.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:path/path.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vup/app.dart';
import 'package:vup/page/settings.dart';
import 'package:vup/utils/ffmpeg/base.dart';
import 'package:vup/utils/ffmpeg_installer.dart';
import 'package:vup/utils/show_portal_dialog.dart';
import 'package:vup/utils/temp_dir.dart';
import 'package:vup/view/setup_sync_dialog.dart';
import 'package:vup/widget/sidebar_shortcut.dart';
import 'package:vup/widget/user.dart';
import 'package:ffmpeg_kit_flutter_full/ffmpeg_kit.dart';
import 'package:vup/widget/vup_logo.dart';
import 'package:xdg_directories/xdg_directories.dart';

class SidebarView extends StatefulWidget {
  final AppLayoutState appLayoutState;
  const SidebarView({required this.appLayoutState, Key? key}) : super(key: key);

  @override
  SidebarViewState createState() => SidebarViewState();
}

class SidebarViewState extends State<SidebarView>
    with SingleTickerProviderStateMixin {
  // String? syncing;
  final _scrollCtrl = ScrollController();

  final shortcutGroupTitleStyle = TextStyle(fontWeight: FontWeight.w600);

  Future<bool> checkForFFmpeg() async {
    if (UniversalPlatform.isLinux || UniversalPlatform.isWindows) {
      try {
        await Process.run(ffmpegPath, []);
        return true;
      } catch (e) {
        return false;
      }
    } else {
      return true;
      try {
        final session = await FFmpegKit.executeWithArgumentsAsync(['-version']);

        final returnCode = await session.getReturnCode();
        print(returnCode);

        if (ReturnCode.isSuccess(returnCode)) {
          return true;
        } else if (ReturnCode.isCancel(returnCode)) {
          return false;
        } else {
          return false;
        }
      } catch (e) {
        return false;
      }
    }
  }

  String get _linuxDesktopFilePath =>
      join(dataHome.path, 'applications', 'vup.desktop');

  Future<void> checkForUpdates() async {
    if (isUpdateAvailable != null) return;
    try {
      final res = await mySky.skynetClient.httpClient.get(
        Uri.parse(
          'https://040d88hlnnklrnsbsu3ptvpqep8970bst7v3ancobqk8h881k3239u8.${mySky.skynetClient.portalHost}',
        ),
        headers: mySky.skynetClient.headers,
      );

      final status = json.decode(res.body);
      final versionData = status['platforms'][Platform.operatingSystem];

      if (Platform.isLinux) {
        final desktopFile = File(_linuxDesktopFilePath);
        if (!desktopFile.existsSync()) {
          isInstallationAvailable = true;
          setState(() {});
          return;
        }
      }

      final int versionCode = versionData['versionCode'];

      if (versionCode > int.parse(packageInfo.buildNumber)) {
        isUpdateAvailable = true;
      } else {
        isUpdateAvailable = false;
      }
      setState(() {});
    } catch (e) {}
  }

  Future<void> downloadAndInstallLatestVersion() async {
    // if (isUpdateAvailable != null) return;

    final res = await mySky.skynetClient.httpClient.get(
      Uri.parse(
        'https://040d88hlnnklrnsbsu3ptvpqep8970bst7v3ancobqk8h881k3239u8.${mySky.skynetClient.portalHost}',
      ),
      headers: mySky.skynetClient.headers,
    );

    final status = json.decode(res.body);
    final versionData = status['platforms'][Platform.operatingSystem];

    final int versionCode = versionData['versionCode'];

    final desktopFile = File(_linuxDesktopFilePath);
    final appDir = join(storageService.dataDirectory, 'app');
    final iconFile = File(join(appDir, 'icon', 'icon.png'));
    // if (!iconFile.existsSync()) {
    final bytes =
        await rootBundle.load('assets/icon/large-vup-logo-single.png');
    iconFile.createSync(recursive: true);
    iconFile.writeAsBytesSync(bytes.buffer.asUint8List());
    // }
    final appImageFile =
        File(join(appDir, 'builds', 'vup-$versionCode.AppImage'));
    await storageService.downloadAndDecryptFile(
      fileData: FileData.fromJson(versionData['file']),
      name: basename(appImageFile.path),
      outFile: appImageFile,
    );

    final appImageGenericLink = Link(join(appDir, 'vup-latest.AppImage'));

    if (appImageGenericLink.existsSync()) {
      await appImageGenericLink.update(appImageFile.path);
    } else {
      await appImageGenericLink.create(appImageFile.path);
    }

    await Process.run('chmod', ['+x', appImageFile.path]);
    final desktopFileContent = '''[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=Vup
Exec=${appImageGenericLink.path} %u
Icon=${iconFile.path}
Categories=FileManager;FileTransfer;Network;Utility;System;FileTools;
StartupWMClass=Vup
X-AppImage-Version=0.7.5
GenericName=Cloud Storage
Comment=Private and decentralized cloud storage
MimeType=x-scheme-handler/vup;
''';
    desktopFile.parent.createSync(recursive: true);
    desktopFile.writeAsStringSync(desktopFileContent);
    setState(() {
      isUpdateAvailable = false;
      isInstallationAvailable = false;
    });
  }

  late final Widget userWidget;

  @override
  void initState() {
    userMenuAnimation = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: 0,
    );
    curvedAnimation = CurvedAnimation(
      parent: userMenuAnimation,
      curve: Curves.easeInOutCubic,
    );
    userWidget = UserWidget(
      mySky.user.id,
      profilePictureOnly: false,
      key: ValueKey('user-${mySky.user.id}'),
    );
    if (isFFmpegInstalled != true) {
      checkForFFmpeg().then((value) {
        setState(() {
          isFFmpegInstalled = value;
        });
      });
    }
    checkForUpdates();
    super.initState();
  }

  late AnimationController userMenuAnimation;
  late Animation curvedAnimation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // userWidget,
        if (Platform.isMacOS)
          SizedBox(
            height: appWindow.titleBarHeight,
            child: MoveWindow(),
          ),
        if (!context.isMobile)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (details) {
                      appWindow.startDragging();
                    },
                    onDoubleTap: () => appWindow.maximizeOrRestore(),
                    child: VupLogo(
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                if (isColumnViewFeatureEnabled)
                  StreamBuilder<Null>(
                    stream: widget.appLayoutState.stream,
                    builder: (context, snapshot) {
                      if (widget.appLayoutState.currentTab.length == 2)
                        return SizedBox();
                      return InkWell(
                        onTap: () {
                          if (widget.appLayoutState.currentTab.length > 1) {
                            widget.appLayoutState.currentTab.removeRange(
                              0,
                              widget.appLayoutState.currentTab.length - 1,
                            );
                            widget.appLayoutState.currentTab.first.state
                                .noPathSelected = false;
                            columnViewActive = false;
                          } else {
                            widget.appLayoutState.currentTab.first.state
                                .columnIndex = 3;

                            final list = List<String>.from(
                                widget.appLayoutState.currentTab[0].state.path);
                            for (int i = 1; i < 4; i++) {
                              widget.appLayoutState.currentTab.insert(
                                0,
                                AppLayoutViewState(
                                  PathNotifierState(
                                    list.sublist(0, max(list.length - i, 0)),
                                    columnIndex: 3 - i,
                                  ),
                                ),
                              );
                            }
                            columnViewActive = true;
                          }

                          widget.appLayoutState.$();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Icon(UniconsLine.grids),
                              SizedBox(width: 4),
                              widget.appLayoutState.currentTab.length == 1
                                  ? Text('Column-View')
                                  : Text('Close'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                StreamBuilder<Null>(
                  stream: widget.appLayoutState.stream,
                  builder: (context, snapshot) {
                    if (widget.appLayoutState.currentTab.length == 4)
                      return SizedBox();
                    return InkWell(
                      onTap: () {
                        if (widget.appLayoutState.currentTab.length > 1) {
                          widget.appLayoutState.currentTab.removeLast();
                        } else {
                          widget.appLayoutState.currentTab.add(
                            AppLayoutViewState(
                              PathNotifierState(
                                ['home'],
                                columnIndex: 1,
                              ),
                            ),
                          );
                        }

                        widget.appLayoutState.$();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Icon(UniconsLine.columns),
                            SizedBox(width: 4),
                            widget.appLayoutState.currentTab.length == 1
                                ? Text('Split')
                                : Text('Close'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        /*  AppBar(
            /*     leading: IconButton(
                onPressed: () {
                  context.beamBack();
                },
                icon: Icon(
                  Icons.arrow_upward,
                ),
              ), */

            title: VupLogo(),
            actions: [
              // TODO Notifications
            ],
          ), */
        Row(
          children: [
            Expanded(
              child: /* PopupMenuButton<String>(
                offset: Offset(0, 50),
                itemBuilder: (context) {
                  return [
                    /*   PopupMenuItem(
                      child: Text(
                        'Switch accounts',
                      ),
                    ), */
                    PopupMenuItem(
                      value: 'logout',
                      child: Text(
                        'Log out',
                      ),
                    ),
                  ];
                },
                onSelected: (value) async {
                  if (value == 'logout') {}
                },
                child:  */
                  InkWell(
                onTap: () {
                  if (userMenuAnimation.value == 0) {
                    userMenuAnimation.animateTo(1);
                  } else {
                    userMenuAnimation.animateTo(0);
                  }
                  // userMenuAnimation.forward();
                },
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 8.0,
                    top: 8,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: userWidget,
                      ),
                      AnimatedBuilder(
                        animation: userMenuAnimation,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: curvedAnimation.value * pi,
                            child: child,
                          );
                        },
                        child: Icon(
                          UniconsLine.angle_down,
                        ),
                      ),
                      SizedBox(
                        width: 8,
                      ),
                    ],
                  ),
                ),
              ),
              /*  ), */
            ),
            IconButton(
              icon: Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                context.push(
                    MaterialPageRoute(builder: (context) => SettingsPage()));
              },
            ),
          ],
        ),
        AnimatedBuilder(
          animation: userMenuAnimation,
          builder: (context, child) {
            return SizedBox(
              height: curvedAnimation.value * 42,
              child: ClipRRect(
                child: child,
              ),
            );
          },
          child: ClipRect(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  child: SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                        ),
                        Icon(UniconsLine.signout),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'Log out',
                          style: TextStyle(
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onTap: () async {
                    final res = await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Do you really want to log out?'),
                        content: Text(
                          'This will delete all local data created by Vup and close the app.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => context.pop(),
                            child: Text(
                              'Cancel',
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.pop(true),
                            child: Text(
                              'Log out',
                            ),
                          ),
                        ],
                      ),
                    );
                    if (res == true) {
                      showLoadingDialog(context, 'Deleting local data...');

                      logger.sink.close();
                      await Hive.close();

                      await Directory(vupTempDir).delete(recursive: true);

                      for (final dir in Directory(vupDataDir).listSync()) {
                        if (basename(dir.path) == 'app') continue;

                        await dir.delete(recursive: true);
                      }

                      await Directory(vupConfigDir).delete(recursive: true);

                      await mySky.secureStorage.deleteAll();

                      exit(0);
                    }
                  },
                )
              ],
            ),
          ),
        ),
        StreamBuilder<Null>(
            stream: quotaService.stream,
            builder: (context, snapshot) {
              if (quotaService.totalBytes == -1) {
                return SizedBox(
                  child: Card(
                    color: Theme.of(context).primaryColor,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'You are currently not logged in to a Skynet portal. Choose a portal and log in to ensure your files stay available.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          SizedBox(
                            height: 8,
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              showPortalDialog(context);
                            },
                            style: ButtonStyle(
                              backgroundColor: MaterialStateProperty.all(
                                Colors.black,
                              ),
                              foregroundColor: MaterialStateProperty.all(
                                Colors.white,
                              ),
                            ),
                            child: Text(
                              'Choose a portal',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              if (quotaService.totalBytes == 0) {
                return SizedBox();
              }

              return Padding(
                padding:
                    const EdgeInsets.only(left: 8, right: 8, top: 0, bottom: 8),
                child: Tooltip(
                  richMessage: TextSpan(
                    text: quotaService.tooltip,
                    style: TextStyle(
                      // color: Colors.black,
                      fontSize: 14,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LinearProgressIndicator(
                          value:
                              quotaService.usedBytes / quotaService.totalBytes,
                          minHeight: 8,
                          backgroundColor: Theme.of(context).dividerColor,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                      text:
                                          '${filesize(quotaService.usedBytes)} ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).primaryColor,
                                      )),
                                  TextSpan(
                                    text:
                                        ' / ${filesize(quotaService.totalBytes)} (${(quotaService.usedBytes / quotaService.totalBytes * 100).toStringAsFixed(2)} %)',
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (quotaService.usedBytes / quotaService.totalBytes >
                              0.2)
                            InkWell(
                              onTap: () {
                                launch(
                                  'https://account.${mySky.skynetClient.portalHost}/payments',
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(0.0),
                                child: Text(
                                  'Upgrade',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                            )
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        Divider(
          height: 1,
        ),
        Expanded(
            child: Scrollbar(
          controller: _scrollCtrl,
          child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(
              left: 8,
              top: 8,
              bottom: 8,
              right: 4,
            ),
            children: [
              Text(
                'Quick Access',
                style: shortcutGroupTitleStyle,
              ),
              SidebarShortcutWidget(
                path: 'home',
                appLayoutState: widget.appLayoutState,
              ),
              StreamBuilder(
                stream: sidebarService.stream,
                builder: (context, snapshot) {
                  return Column(
                    children: [
                      for (final entry
                          in sidebarService.sidebarConfig['locations'] ?? [])
                        Dismissible(
                          key: ValueKey(entry.toString()),
                          direction: DismissDirection.startToEnd,
                          onDismissed: (direction) {
                            sidebarService.unpinDirectory(entry);
                          },
                          child: SidebarShortcutWidget(
                            path: entry['path'],
                            appLayoutState: widget.appLayoutState,
                          ),
                        ),
                    ],
                  );
                },
              ),
              SidebarShortcutWidget(
                path: storageService.trashPath,
                appLayoutState: widget.appLayoutState,
                title: 'Trash',
                icon: 'template',
              ),

              SizedBox(
                height: 16,
              ),
              /* Text(
                'By type',
                style: shortcutGroupTitleStyle,
              ),
              SidebarShortcutWidget(
                title: 'All images',
                path: 'fs-dac.hns/index/by-type/image',
                appLayoutState: widget.appLayoutState,
              ),
              SidebarShortcutWidget(
                title: 'All music and audio',
                path: 'fs-dac.hns/index/by-type/audio',
                appLayoutState: widget.appLayoutState,
              ),
              SidebarShortcutWidget(
                title: 'All videos',
                path: 'fs-dac.hns/index/by-type/video',
                appLayoutState: widget.appLayoutState,
              ),
             */
              Text(
                'Shared',
                style: shortcutGroupTitleStyle,
              ),
              SidebarShortcutWidget(
                path: 'vup.hns/.internal/shared-with-me',
                appLayoutState: widget.appLayoutState,
                title: 'Shared with me',
                icon: 'folder-shared',
              ),

              if (storageService.dac.customRemotes.isNotEmpty) ...[
                SizedBox(
                  height: 16,
                ),
                Text(
                  'Remotes',
                  style: shortcutGroupTitleStyle,
                ),
                for (final remoteId in storageService.dac.customRemotes.keys)
                  SidebarShortcutWidget(
                    path: 'skyfs://$remoteId@remote',
                    appLayoutState: widget.appLayoutState,
                  ),
              ],

              if ((dataBox.get('jellyfin_server_collections') ?? [])
                  .isNotEmpty) ...[
                SizedBox(
                  height: 16,
                ),
                Text(
                  'Media',
                  style: shortcutGroupTitleStyle,
                ),
                for (final collection
                    in dataBox.get('jellyfin_server_collections') ?? [])
                  SidebarShortcutWidget(
                    path: collection['uri'],
                    appLayoutState: widget.appLayoutState,
                    title: collection['name'],
                    icon: {
                      'music': 'audio',
                      'tvshows': 'video',
                      'movies': 'video',
                      'books': 'storybook',
                    }[collection['type']],
                    // icon: 'folder-shared', //
                  ),
              ],

              if (devModeEnabled) ...[
                SizedBox(
                  height: 16,
                ),
                Text(
                  'Internal (Debug)',
                  style: shortcutGroupTitleStyle,
                ),
                SidebarShortcutWidget(
                  path: 'vup.hns/.internal/active-files',
                  appLayoutState: widget.appLayoutState,
                  title: 'Active files',
                ),
                SidebarShortcutWidget(
                  path: 'vup.hns/.internal/shared-static-directories',
                  appLayoutState: widget.appLayoutState,
                ),
                SidebarShortcutWidget(
                  path: 'vup.hns/.internal/shared-directories',
                  appLayoutState: widget.appLayoutState,
                ),
              ],
              // TODO Recent

              // Text(
              //     'Recently used'), // TODO Maybe also "often used" (auto-algorithm by recently and how often)

              /*   ChangeNotifierBuilder(
                stateNotifier: widget.pathNotifier,
                builder: (context, snapshot) {},
              ) */
            ],
          ),
        )),
        if (isFFmpegInstalled == false)
          Container(
            decoration: BoxDecoration(
              color: SkyColors.warning,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Warning: ffmpeg cannot be found. This results in no thumbnail generation and metadata extraction for media files. Please install it as soon as possible.',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (Platform.isLinux || Platform.isWindows) ...[
                  SizedBox(
                    height: 8,
                  ),
                  ElevatedButton(
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all(
                        Colors.black,
                      ),
                      foregroundColor: MaterialStateProperty.all(
                        Colors.white,
                      ),
                    ),
                    onPressed: () async {
                      showLoadingDialog(
                        context,
                        'Downloading and installing latest FFmpeg...',
                      );
                      try {
                        await downloadAndInstallFFmpeg();
                        context.pop();
                        checkForFFmpeg().then((value) {
                          setState(() {
                            isFFmpegInstalled = value;
                          });
                        });
                      } catch (e, st) {
                        context.pop();
                        showErrorDialog(context, e, st);
                      }
                    },
                    child: Text(
                      'Download and install',
                    ),
                  ),
                ]
              ],
            ),
          ),
        if (isInstallationAvailable && !isRunningAsFlatpak)
          Container(
            decoration: BoxDecoration(
              color: SkyColors.warning,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Install Vup\nVup can be installed on your local system',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(
                  height: 8,
                ),
                ElevatedButton(
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.all(
                      Colors.black,
                    ),
                    foregroundColor: MaterialStateProperty.all(
                      Colors.white,
                    ),
                  ),
                  onPressed: () async {
                    showLoadingDialog(
                      context,
                      'Downloading and installing Vup...',
                    );
                    try {
                      await downloadAndInstallLatestVersion();
                      context.pop();
                    } catch (e, st) {
                      context.pop();
                      showErrorDialog(context, e, st);
                    }
                  },
                  child: Text(
                    'Download and install now',
                  ),
                ),
              ],
            ),
          ),
        if (isUpdateAvailable == true)
          Container(
            decoration: BoxDecoration(
              color: SkyColors.warning,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.all(8),
            child: Platform.isLinux
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'An update is available\nVup will be closed after the update and you will have to open it again.',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        height: 8,
                      ),
                      ElevatedButton(
                        style: ButtonStyle(
                          backgroundColor: MaterialStateProperty.all(
                            Colors.black,
                          ),
                          foregroundColor: MaterialStateProperty.all(
                            Colors.white,
                          ),
                        ),
                        onPressed: () async {
                          showLoadingDialog(
                            context,
                            'Downloading and installing Vup...',
                          );
                          try {
                            await downloadAndInstallLatestVersion();
                            exit(0);
                          } catch (e, st) {
                            context.pop();
                            showErrorDialog(context, e, st);
                          }
                        },
                        child: Text(
                          'Download and install now',
                        ),
                      ),
                    ],
                  )
                : Text(
                    'An update is available\nCheck the Discord Server for more details and the changelog',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ValueListenableBuilder(
          valueListenable: syncTasks.listenable(),
          builder: (context, box, widget) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (syncTasks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Text(
                      'Sync directories',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                for (final String syncKey in syncTasks.keys)
                  StateNotifierBuilder<FileState>(
                      stateNotifier:
                          storageService.dac.getFileStateChangeNotifier(
                        syncTasks.get(syncKey)!.remotePath,
                      ),
                      builder: (context, state, _) {
                        final task = syncTasks.get(syncKey)!;
                        return ListTile(
                          onTap: state.type != FileStateType.idle
                              ? null
                              : () async {
                                  await showDialog(
                                    context: context,
                                    builder: (context) => SetupSyncDialog(
                                      initialTask: task,
                                      path: task.remotePath,
                                    ),
                                  );
                                  /* setState(() {
                                    
                                  }); */
                                },
                          leading: state.type != FileStateType.idle
                              ? Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: SizedBox(
                                    child: CircularProgressIndicator(
                                      value: state.progress,
                                      backgroundColor:
                                          Theme.of(context).dividerColor,
                                    ),
                                    width: 24,
                                    height: 24,
                                  ),
                                )
                              : ((task.watch)
                                  ? IconButton(
                                      tooltip: 'Watching for changes',
                                      onPressed: () {}, // TODO Show debug info
                                      icon: Icon(
                                        UniconsLine.eye,
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: 'Sync now',
                                      onPressed: () async {
                                        //  return;
                                        /* setState(() {
                                              syncing = syncKey;
                                            }); */
                                        try {
                                          if (storageService.isSyncTaskLocked(
                                              syncKey)) return;
                                          await storageService.syncDirectory(
                                            Directory(
                                              task.localPath!,
                                            ),
                                            task.remotePath,
                                            task.mode,
                                            syncKey: syncKey,
                                          );
                                        } catch (e, st) {
                                          showErrorDialog(context, e, st);
                                        }

                                        // syncing = null;
                                        // if (mounted) setState(() {});
                                      },
                                      icon: Icon(
                                        UniconsLine.sync_icon,
                                      ),
                                    )),
                          title: Padding(
                            padding: const EdgeInsets.only(bottom: 2.0),
                            child: Text(task.remotePath),
                          ),
                          /*   subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(state.type.toString()),
                          ), */
                        );
                      }),
              ],
            );
          },
        ),
      ],
    );
  }
}
