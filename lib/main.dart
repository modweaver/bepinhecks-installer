import 'dart:collection';
import 'dart:convert';
import 'dart:io';
// ignore: library_prefixes
import 'package:archive/archive.dart';
// ignore: library_prefixes
import 'package:http/http.dart' as Http;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
// ignore: library_prefixes
import "package:win32/win32.dart" as Win32;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:desktop_drop/desktop_drop.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BepInHecks Installer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.amber,
      ),
      home: const MyHomePage(title: 'BepInHecks Installer'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String installLoc = "unselected";
  String dirText = "Please locate your SpiderHeck installation folder";
  String logText = "";
  String targetVersion = "latest";
  String psaText =
      "Info: BepInHecks only works with the Steam/Epic versions of the games, and the launch button only works with Steam\nPut mod DLL files in: [game folder]/BepInHecks/plugins";

  Future<void> copyPath(String from, String to) async {
    await Directory(to).create(recursive: true);
    await for (final file in Directory(from).list(recursive: true)) {
      final copyTo = p.join(to, p.relative(file.path, from: from));
      if (file is Directory) {
        await Directory(copyTo).create(recursive: true);
      } else if (file is File) {
        await File(file.path).copy(copyTo);
      } else if (file is Link) {
        await Link(copyTo).create(await file.target(), recursive: true);
      }
    }
  }

  String getTempSubfolder(String name) {
    String tempPath = Directory.systemTemp.path;
    return p.join(tempPath, "bih_installer", name);
  }

  bool validateInstallLoc(String path) {
    String exe1 = p.join(path, "SpiderHeckApp.exe");
    return File(exe1).existsSync();
  }

  String? tryAutoDetectGamePath() {
    if(!Platform.isWindows) {
      addLog("Steam auto-detect is only supported on windows!");
      return null;
    }

    final subKeyName = "SOFTWARE\\Valve\\Steam".toNativeUtf16();
    final valueName = "SteamPath".toNativeUtf16();
    final dataPointer = Win32.wsalloc(Win32.MAX_PATH);
    final sizePointer = malloc<Win32.UINT32>();

    final keyGetValueStatus = Win32.RegGetValue(Win32.HKEY_CURRENT_USER, subKeyName, valueName, Win32.RRF_RT_REG_SZ, nullptr, dataPointer, sizePointer);

    if(keyGetValueStatus != 0) {
      addLog("Steam auto-detect failed with registry error $keyGetValueStatus!");
      return null;
    }

    final steamInstallPath = dataPointer.toDartString();
    
    malloc.free(subKeyName);
    malloc.free(valueName);
    malloc.free(dataPointer);
    malloc.free(sizePointer);

    final gameInstallPath = p.join(steamInstallPath, "steamapps", "common", "SpiderHeck");
    return gameInstallPath;
  }

  void openFilePicker() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) {
      installLoc = "unselected";
    } else {
      addLog("Validating install: $selectedDirectory");
      if (validateInstallLoc(selectedDirectory)) {
        installLoc = selectedDirectory;
        addLog("Install valid!");
      } else {
        installLoc = "unselected";
        addLog("Install invalid! Please try again.");
      }
    }
    updateInstallLocText();
  }

  Future<void> pullLatestReleaseGH(String repo, String outDir,
      {String version = "latest"}) async {
    String apiQuery = "";
    if (version == "latest") {
      apiQuery = "https://api.github.com/repos/$repo/releases/latest";
    } else {
      apiQuery = "https://api.github.com/repos/$repo/releases/tags/$version";
    }
    Map<String, String> headers = HashMap();
    headers.putIfAbsent('Accept', () => 'application/json');

    Http.Response response =
        await Http.get(Uri.parse(apiQuery), headers: headers);
    String jsonText = response.body;
    final json = jsonDecode(jsonText);
    String releaseAssetUrl = json["assets"][0]["browser_download_url"];
    addLog("Downloading asset from github");

    Http.Response assetRaw = await Http.get(Uri.parse(releaseAssetUrl));
    final dlBytes = assetRaw.bodyBytes;
    final archive = ZipDecoder().decodeBytes(dlBytes);
    String zipOutDir = outDir;

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('$zipOutDir/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory('$zipOutDir/$filename').create(recursive: true);
      }
    }
    addLog("Extracted archive");
  }

  Future<void> backupPlugins() async {
    String pluginsDir = "$installLoc/BepInHecks/plugins";
    String backupPath = getTempSubfolder("PluginsBackup");
    await copyPath(pluginsDir, backupPath);
  }

  Future<bool> isBepinexPresent() {
    String proxyPath = p.join(installLoc, "winhttp.dll");
    return File(proxyPath).exists();
  }

  Future<void> uninstallBepinex() async {
    if (Platform.isWindows) {
      await Process.run("$installLoc\\Uninstall_Bepinhecks.bat", [],
          workingDirectory: installLoc);
    } else {
      await Process.run("sh", ["$installLoc/UninstallBepinhecks.sh"],
          workingDirectory: installLoc);
    }
    addLog("Successfully uninstalled BepInHecks");
  }

  Future<void> restorePlugins() async {
    String pluginsDir = "$installLoc/BepInHecks/plugins";
    String backupPath = getTempSubfolder("PluginsBackup");
    await copyPath(backupPath, pluginsDir);
    addLog("Restored plugins folder");
  }

  void startInstall() async {
    if(installLoc == "unselected") {
      addLog("You need to select the game install path! Click the locate button above");
      return;
    }

    addLog("Starting BepInHecks Install");
    await pullLatestReleaseGH("cobwebsh/BepInHecks", getTempSubfolder("ZipDownload"));
    bool bepinexInstalled = await isBepinexPresent();
    if (bepinexInstalled) {
      addLog("Pre-existing BepInHecks detected! Backing up plugins folder");
      await backupPlugins();
      addLog("Uninstalling old version");
      await uninstallBepinex();
    }
    await copyPath(getTempSubfolder("ZipDownload"), installLoc);
    if (bepinexInstalled) {
      await restorePlugins();
    }
    addLog("Finished install!");
    addLog("Click the button to launch the game");
  }

  void updateInstallLocText() {
    setState(() {
      dirText = "SpiderHeck install: $installLoc";
    });
  }

  void addLog(String log) {
    int logNum = logText.characters.where((c) => c == '\n').length + 1;
    setState(() {
      logText = "$logText\n$logNum|  $log";
    });
  }
  void clearLog() {
    setState(() {
      logText = "";
    });
  }

  Future<void> launchGameViaSteam() async {
    addLog("Starting game...");
    final Uri steamUri = Uri.parse("steam://rungameid/1329500");
    if (!await launchUrl(steamUri)) {
      addLog("Error launching SpiderHeck through steam");
    }
  }

  void setTargetVersion(String version) {
    targetVersion = version != "" ? version : "latest";
  }

  @override
  void initState() {
    super.initState();

    var detectedGamePath = tryAutoDetectGamePath();
    if(detectedGamePath != null) {
      installLoc = detectedGamePath;
      updateInstallLocText();
      addLog("Game install path was auto-detected!");
    }
  }

  Future<void> handleFileDrop(DropDoneDetails details) async {
    if(installLoc == "unselected") {
      addLog("Can't drag and drop without selecting a path!");
      return;
    }

    if(! await isBepinexPresent()) {
      addLog("Can't drag and drop plugins without having BepInHecks installed!");
      return;
    }

    for (var xfile in details.files) {
      if(!xfile.path.endsWith(".dll") && !xfile.path.endsWith(".zip")) {
        addLog("Only .zip and .dll files can be drag and dropped!");
        return;
      }

      if(xfile.path.endsWith(".zip")) {
        final archive = ZipDecoder().decodeBytes(await xfile.readAsBytes());
        final outDir = p.join(installLoc, "BepInHecks", "plugins", xfile.name);

        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            File('$outDir/$filename')
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            Directory('$outDir/$filename').create(recursive: true);
          }
        }

        addLog("Added zipped mod to plugins folder");
      } else { // must be a dll, so we can just copy
        final fileName = p.basename(xfile.path);
        final outPath = p.join(installLoc, "BepInHecks", "plugins",fileName);
        await xfile.saveTo(outPath);
        addLog("Added mod DLL to plugins folder");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const buttonPadding = MaterialStatePropertyAll(EdgeInsets.all(10));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, textAlign: TextAlign.center,),
        actions: [
          IconButton(
            onPressed: () => {
              launchUrlString("https://github.com/cobwebsh/bepinhecks-installer/blob/main/README.md#how-to-use")
            },
            tooltip: "View the README",
            icon: const Icon(Icons.help_outline)
          ),
          IconButton(
            onPressed: () => {
              launchUrlString("https://github.com/cobwebsh/bepinhecks-installer")
            }, 
            tooltip: "View the source code for this",
            icon: const Icon(Icons.code)
          ),
          IconButton(
            onPressed: () => {
              launchUrlString("https://github.com/cobwebsh/BepInHecks")
            }, 
            tooltip: "Goto the BepInHecks project page",
            icon: const Icon(Icons.open_in_browser)
          ),
          const Text("  "),
        ],
      ),
      body: DropTarget(
        onDragDone: handleFileDrop,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Text("\n\n"),
              Text(psaText, textAlign: TextAlign.center,),
              const Text("\n\n"),
              Text(
                dirText, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20.0),
              ),
              const Divider(thickness: 2, height: 50,),
              
      
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: openFilePicker,
                    icon: const Icon(Icons.folder),
                    label: const Text(
                      "Locate...",
                      style: TextStyle(fontSize: 20.0),
                    ),
                    style: const ButtonStyle(padding: buttonPadding),
                  ),
                  const Text("    "),
                  OutlinedButton.icon(
                    onPressed: startInstall,
                    icon: const Icon(Icons.download),
                    label: const Text(
                      "Install",
                      style: TextStyle(fontSize: 20.0),
                    ),
                    style: const ButtonStyle(padding: buttonPadding),
                  ),
                  const Text("    "),
                  OutlinedButton.icon(
                    onPressed: uninstallBepinex,
                    icon: const Icon(Icons.delete),
                    label: const Text(
                      "Uninstall",
                      style: TextStyle(fontSize: 20.0),
                    ),
                    style: const ButtonStyle(padding: buttonPadding),
                  ),
                  const Text("    "),
                  OutlinedButton.icon(
                    onPressed: launchGameViaSteam,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text(
                      "Launch",
                      style: TextStyle(fontSize: 20.0),
                    ),
                    style: const ButtonStyle(padding: buttonPadding),
                  ),
                ],),
                const Divider(thickness: 2, height: 50,),
      
              Text(
                logText, 
                textAlign: TextAlign.left, 
                style: const TextStyle(
                  // fontFamily: "Consolas",
                  fontSize: 16,
                ),
              ),
              const Text(""),
              OutlinedButton.icon(
                onPressed: clearLog, 
                icon: const Icon(Icons.clear), 
                label: const Text("Clear log")
              ),
            ],
          ),
        ),
      ),
    );
  }
}
