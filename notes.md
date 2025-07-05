









@echo off
setlocal EnableDelayedExpansion

cls
echo ===============================================================================
echo                              DWEMER DYNAMICS                               
echo                           CHIM DISTRO INSTALLER                           
echo ===============================================================================
echo.
echo  IMPORTANT: Make sure Virtual Machine Platform, Windows Subsystem 
echo    for Linux and Windows Hypervisor Platform are enabled in Windows features!
echo.
echo  You can enable them in:
echo    Control Panel - Programs and Features - Turn Windows features on or off
echo. 
echo  Press any key to begin the installation process...
pause > nul

cls
echo ===============================================================================
echo                              DWEMER DYNAMICS                               
echo                           CHIM DISTRO INSTALLER                           
echo ===============================================================================
echo.

echo [*] STEP 1: Installing WSL2...
echo.
echo     - Updating WSL components...
wsl --update
echo     + WSL2 installation complete
echo.
echo  Press any key to continue...
pause > nul

echo.
echo [*] STEP 2: Importing DwemerAI4Skyrim3...
echo.
echo     - Importing distro files (this may take a few minutes)...
wsl --import DwemerAI4Skyrim3 . DwemerAI4Skyrim3.tar
echo     + DwemerAI4Skyrim3 distro imported successfully
echo.


echo [*] STEP 3: Updating CHIM server...
echo.
echo     - Configuring server components...
wsl -d DwemerAI4Skyrim3 -u dwemer -- /usr/local/bin/update_gws
echo     + Server updated successfully
echo.

echo ===============================================================================
echo                       INSTALLATION PROCESS COMPLETE!                        
echo ===============================================================================
echo.
echo  You can now delete the DwemerAI4Skyrim3.tar and DwemerAISkyrim3.7z files.
echo.
echo  Installation location (You must uninstall the Distro before moving it): %CD%
echo.
echo. Next Steps:
echo. 1. Download AIAgent here: https://www.nexusmods.com/skyrimspecialedition/mods/126330?tab=files
echo. 2. Install it with your Mod Manager of choice.
echo. 3. Open the AIAgent mod folder, create a shortcut of CHIM.exe and place it on your desktop.
echo. 4. Run CHIM.exe, install any components you want, then start the server.
echo.
echo  Press any key to exit...
pause > nul










echo [*] STEP 1: Updating CHIM distro...
echo.
echo     - Running git operations and update script...
wsl -d DwemerAI4Skyrim3 -u dwemer -- bash -c "cd /home/dwemer/dwemerdistro && git fetch origin && git reset --hard origin/main && chmod +x update.sh && echo 'dwemer' | sudo -S ./update.sh"
echo     + CHIM distro update complete

echo.
echo [*] STEP 2: Updating CHIM server...
echo.
echo     - Executing server update...
wsl -d DwemerAI4Skyrim3 -u dwemer -- /usr/local/bin/update_gws
echo     + Server update complete
