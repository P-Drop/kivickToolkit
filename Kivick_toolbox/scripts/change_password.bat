
set  /p password= set the new password
timeout /t 2 /nobreak >nul
cls
net user %USERNAME%  %password%