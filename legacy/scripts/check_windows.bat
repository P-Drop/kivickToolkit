echo  Starting to resolve the operating system errors; please don't move your mouse and don't power off your laptop/PC during the operation. 
timeout /t 5 /nobreak >nul
cls
DISM /Online /Cleanup-Image /RestoreHealth

