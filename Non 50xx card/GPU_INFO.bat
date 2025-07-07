@echo off
echo.
echo ================================================
echo           WHICH GPU SHOULD I USE?
echo ================================================
echo.
echo Your GPUs are:
echo.

nvidia-smi --query-gpu=index,name --format=csv,noheader,nounits

echo.
echo ================================================
echo.
echo Use the NUMBER on the left (0, 1, 2, etc.)
echo.
echo ================================================
echo.
pause
echo.
echo ================================================
echo           HOW TO CHANGE GPU
echo ================================================
echo.
echo 1. Pick your GPU number from above
echo.
echo 2. Edit these 3 files with Notepad or Notepad ++:
echo    - start_zonos
echo    - zonos_download_models  
echo    - download_models.py
echo.
echo 3. In each file, find this line:
echo    CUDA_VISIBLE_DEVICES=1
echo.
echo 4. Change the 1 to your GPU number you picked above
echo 
echo.
echo 5. Save all files and run InstallZonos.bat
echo.
echo ================================================
pause