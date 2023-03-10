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
      "Info: BepInHecks only works with the Steam/Epic versions of the games, and the launch button only works with Steam\nPut mod DLL files in: [game folder]/BepInEx/plugins";

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

  bool validateInstallLoc(String path) {
    String exe1 = p.join(path, "SpiderHeckApp.exe");
    return File(exe1).existsSync();
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
        installLoc = "invalid";
        addLog("Install invalid!");
      }
    }
    changeText();
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
    addLog("Asset download: $releaseAssetUrl");

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
    String pluginsDir = "$installLoc/BepInEx/plugins";
    Directory plugins = Directory(pluginsDir);
    Directory backup = Directory("plugins_backup");

    await copyPath(plugins.path, backup.path);
  }

  Future<bool> isBepinexPresent() {
    String bepinexDir;
    if (Platform.isWindows) {
      bepinexDir = "$installLoc\\BepInEx";
    } else {
      bepinexDir = "$installLoc/BepInEx";
    }

    return Directory(bepinexDir).exists();
  }

  Future<void> uninstallBepinex() async {
    if (Platform.isWindows) {
      await Process.run("$installLoc\\Uninstall_Bepinhecks.bat", [],
          workingDirectory: installLoc);
    } else {
      await Process.run("sh", ["$installLoc/UninstallBepinhecks.sh"],
          workingDirectory: installLoc);
    }
  }

  Future<void> restorePlugins() async {
    addLog("Restoring plugins");
    String pluginsDir = "$installLoc/BepInEx/plugins";
    Directory plugins = Directory(pluginsDir);
    Directory backup = Directory("plugins_backup");

    await copyPath(backup.path, plugins.path);
  }

  Future<void> clearGeneratedFolders(String dlDir, String pluginbacDir) async {
    Directory downloadDir = Directory(dlDir);
    Directory plbacDir = Directory(pluginbacDir);
    if (downloadDir.existsSync()) {
      downloadDir.deleteSync(recursive: true);
    }
    if (plbacDir.existsSync()) {
      plbacDir.deleteSync(recursive: true);
    }
  }

  void startInstall() async {
    clearLog();
    addLog("Starting BepInHecks Install");
    await clearGeneratedFolders("bepinhecks_zip", "plugins_backup");
    await pullLatestReleaseGH("cobwebsh/BepInHecks", "bepinhecks_zip");
    bool bepinexInstalled = await isBepinexPresent();
    if (bepinexInstalled) {
      addLog("BepInEx detected! Backing up plugins folder");
      await backupPlugins();
      addLog("Uninstalling old version of bepinex");
      await uninstallBepinex();
    }
    await copyPath("bepinhecks_zip", installLoc);
    if (bepinexInstalled) {
      await restorePlugins();
    }
    addLog("Finished install!");
    addLog("Click the button to launch the game");
  }

  void changeText() {
    setState(() {
      dirText = "SpiderHeck install: $installLoc";
    });
  }

  void addLog(String log) {
    setState(() {
      logText = "$logText\n$log";
    });
  }
  void clearLog() {
    setState(() {
      logText = "";
    });
  }

  Future<void> openGameFolder() async {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text("\n\n"),
            Text(psaText, textAlign: TextAlign.center,),
            const Divider(thickness: 2, height: 50,),
            Text(
              dirText, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20.0),
            ),
            const Divider(thickness: 2, height: 50,),
            

            Column(children: [
                OutlinedButton(
                  onPressed: openFilePicker,
                  child: const Text(
                    "Locate...",
                    style: TextStyle(fontSize: 20.0),
                  ),
                ),
                const Text(""),
                OutlinedButton(
                  onPressed: startInstall,
                  child: const Text(
                    "Install",
                    style: TextStyle(fontSize: 20.0),
                  ),
                ),
                const Text(""),
                OutlinedButton(
                  onPressed: uninstallBepinex,
                  child: const Text(
                    "Uninstall",
                    style: TextStyle(fontSize: 20.0),
                  ),
                ),
                const Text(""),
                OutlinedButton(
                  onPressed: openGameFolder,
                  child: const Text(
                    "Open",
                    style: TextStyle(fontSize: 20.0),
                  ),
                ),
              ],),
              const Divider(thickness: 2, height: 50,),
            Text(logText, textAlign: TextAlign.center,),
          ],
        ),
      ),
    );
  }
}
