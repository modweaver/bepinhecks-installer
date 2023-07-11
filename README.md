# BepInHecks Installer
### Automatically downloads and installs the latest (or specified) version of BepInHecks

### PSA: Modding only works with the Steam, and Epic versions of the game. Xbox Game Pass & Windows Store versions are unsupported.

## How to use:

1. Download the installer from the [releases page](https://github.com/cobwebsh/bepinhecks-installer/releases/latest), and extract the zip file. **This doesn't have to be in the game folder.**

2. Run `bepinhecks_installer.exe`

3. Select the game path
    -  If you have the steam version of the game, and are on windows, the path should automatically be detected and shown in the window. 
    - Otherwise, click on the locate button and browse to it. If it is correct, it should say `Install valid` at the bottom. If it says invalid, check you have the right path and try again.

4. Click the `Install` button to download and install it. If it already detects mods installed, it will back up all of the plugins before updating BepInHecks.

5. If installation succeeded, you will see `Finished install!` appear in the window.

6. You can use the `Launch` button to start the game, if you have it on Steam. Otherwise, launch it as normal

7. Install mods
    - Manually: add DLLs to the `<game folder>/BepInHecks/plugins` directory. If the mod comes as a .zip file, you will have to extract it first, then add it to the plugins folder. 
    - Drag-and-drop: drag mod DLLs or ZIPs onto the installer window, and as long as the path is selected it will add the mod, extracting if necessary.

8. If you want to remove all mods and BepInHecks, click the `Uninstall` button at the bottom.