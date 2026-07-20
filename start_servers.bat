@echo off
echo Starting Python OCR Server...
start cmd /k "cd c:\Users\PC\GithubRepo\resortsconnectapp\ocr_server && uvicorn main:app --host 0.0.0.0 --port 8000"

echo Starting Ngrok Tunnel...
start cmd /k "cd c:\Users\PC\GithubRepo\resortsconnectapp && ngrok http --url walk-versus-peculiar.ngrok-free.dev 8000"

echo Starting React Web Application...
start cmd /k "cd c:\Users\PC\GithubRepo\resortsconnectapp\website && npm start"

echo All 3 servers have been started in separate windows!
exit
