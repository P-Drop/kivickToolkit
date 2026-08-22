set /p name=  Please insert the account name....
timeout /t 5 /nobreak >nul
cls
set /p passw= Please insert the password for the account....
timeout /t 6 /nobreak >nul
cls
net user  %name%  %passw% /add 
echo Reboot the system  for apply the changes