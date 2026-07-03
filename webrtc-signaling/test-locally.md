# Local Testing Guide for WebRTC Signaling Server

## Prerequisites

1. **Node.js** (v14+)
2. **Vercel CLI** 
3. **Your Qt app** with WebRTC integration

## Step 1: Setup Vercel CLI

```bash
# Install Vercel CLI globally
npm install -g vercel

# Login to Vercel (only needed once)
vercel login
```

## Step 2: Test Server Locally

Navigate to the signaling server directory:

```bash
cd g:\Coding\S3rpent_Media\webrtc-signaling
```

### Option A: Vercel Dev Server (Recommended)

```bash
# Start local development server
vercel dev

# You'll see output like:
# > Vercel CLI 28.4.8
# > Ready! Available at http://localhost:3000
```

Your signaling server will be available at: `http://localhost:3000/api/signal`

### Option B: Simple Node.js Server (Alternative)

If you prefer a simple Node server for testing:

```bash
# Install dependencies
npm install express cors

# Create test server
node test-server.js
```

## Step 3: Update Qt App for Local Testing

In `src/cpp/webrtclistentogethermanager.cpp`, update the server URL:

```cpp
// Change this line:
QString m_signalingServerUrl = "https://your-vercel-app.vercel.app";

// To this for local testing:
QString m_signalingServerUrl = "http://localhost:3000";
```

## Step 4: Test the API

### Test Create Session

```bash
curl -X POST http://localhost:3000/api/signal \
  -H "Content-Type: application/json" \
  -d '{"type": "create_session", "sessionId": "test123"}'
```

Expected response:
```json
{"success": true, "sessionId": "test123"}
```

### Test Join Session

```bash
curl -X POST http://localhost:3000/api/signal \
  -H "Content-Type: application/json" \
  -d '{"type": "join_session", "sessionId": "test123"}'
```

Expected response:
```json
{"success": true, "messages": []}
```

## Step 5: Test with Qt App

1. **Build your Qt app** with WebRTC enabled
2. **Start the signaling server** (`vercel dev`)
3. **Run two instances** of your Qt app
4. **In first instance**: Click "Create Session"
5. **In second instance**: Click "Join Session" and enter the code
6. **Test sync**: Play/pause/seek in one app - should sync to the other

## Troubleshooting

### CORS Issues
If you get CORS errors, the server should handle them. If not, add this to `api/signal.js`:

```javascript
res.setHeader('Access-Control-Allow-Origin', '*');
res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
```

### Connection Issues
- **Check firewall**: Port 3000 must be accessible
- **Check WebRTC**: STUN server (stun:stun.l.google.com:19302) must be reachable
- **Check logs**: Both Qt apps should show WebRTC connection logs

### Vercel Dev Issues
```bash
# Clear Vercel cache
vercel dev --force

# Or try different port
vercel dev --port 3001
```

## Step 6: Deploy to Production

Once local testing works:

```bash
# Deploy to Vercel
vercel --prod

# Update Qt app with production URL
# In webrtclistentogethermanager.cpp:
QString m_signalingServerUrl = "https://your-app-name.vercel.app";
```

## Testing Checklist

- [ ] Vercel dev server starts on localhost:3000
- [ ] API endpoints respond to curl requests
- [ ] Qt app can create sessions
- [ ] Qt app can join sessions  
- [ ] Play/pause syncs between apps
- [ ] Seek syncs between apps
- [ ] Track changes sync between apps
- [ ] Connection status shows correctly
- [ ] Session links are generated and shareable
