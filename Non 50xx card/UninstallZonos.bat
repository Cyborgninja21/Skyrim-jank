@echo off
echo.
echo ================================================
echo    DELETE ZONOS FROM CHIM
echo ================================================
echo.
echo WARNING: This will completely remove Zonos from your system!
echo You will need to reinstall it to use Zonos again.
echo.
echo This will delete: /home/dwemer/Zonos
echo.
set /p confirm="Are you sure you want to delete Zonos? (Y/N): "

if /i "%confirm%" NEQ "Y" (
    echo.
    echo Deletion cancelled.
    pause
    exit /b
)

echo.
echo Deleting Zonos folder...
wsl -d DwemerAI4Skyrim3 -- rm -rf /home/dwemer/Zonos

echo.
echo ================================================
echo Zonos has been deleted from CHIM!
echo.
echo To reinstall:
echo 1. Run SelectGPU.bat (choose your GPU)
echo 2. Run InstallZonos.bat
echo ================================================
echo.
pause