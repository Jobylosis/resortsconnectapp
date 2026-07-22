@echo off
echo Starting Python OCR Server...
start cmd /k "cd c:\Users\PC\GithubRepo\resortsconnectapp-main\ocr_server && uvicorn main:app --host 0.0.0.0 --port 8000"

echo Starting Ngrok Tunnel...
start cmd /k "cd c:\Users\PC\GithubRepo\resortsconnectapp-main && ngrok http --url walk-versus-peculiar.ngrok-free.dev 8000"

echo Both servers have been started in separate windows!
exit
