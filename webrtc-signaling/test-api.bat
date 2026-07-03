@echo off
echo Testing WebRTC Signaling Server API
echo.

echo 1. Testing server health...
curl -s http://localhost:3000/health
echo.

echo 2. Creating session "test123"...
curl -s -X POST http://localhost:3000/api/signal ^
  -H "Content-Type: application/json" ^
  -d "{\"type\": \"create_session\", \"sessionId\": \"test123\"}"
echo.

echo 3. Joining session "test123"...
curl -s -X POST http://localhost:3000/api/signal ^
  -H "Content-Type: application/json" ^
  -d "{\"type\": \"join_session\", \"sessionId\": \"test123\"}"
echo.

echo 4. Sending SDP offer...
curl -s -X POST http://localhost:3000/api/signal ^
  -H "Content-Type: application/json" ^
  -d "{\"type\": \"description\", \"sessionId\": \"test123\", \"sdp\": \"v=0\\r\\no=-...\", \"isHost\": true}"
echo.

echo 5. Checking active sessions...
curl -s http://localhost:3000/sessions
echo.

echo.
echo API tests completed! Check responses above.
echo If all responses look good, your server is ready for Qt app testing.
pause
