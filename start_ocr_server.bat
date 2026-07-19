@echo off
echo Starting Python OCR Server...
start cmd /k ".venv\Scripts\activate && cd ocr_server && uvicorn main:app --host 0.0.0.0 --port 8000"

echo Starting Ngrok Internet Tunnel...
start cmd /k "ngrok http --url=walk-versus-peculiar.ngrok-free.dev 8000"

echo =========================================================
echo Both servers are starting up in separate windows!
echo Keep those two black windows open while your app is being tested.
echo You can minimize them, but do not close them.
echo =========================================================
pause
