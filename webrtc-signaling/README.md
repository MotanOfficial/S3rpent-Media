# WebRTC Signaling Server for s3rpent Media

This is a simple serverless signaling server for the "Listen Together" P2P feature in s3rpent Media.

## Deployment

### Option 1: Vercel (Recommended)

1. **Install Vercel CLI**
   ```bash
   npm i -g vercel
   ```

2. **Deploy to Vercel**
   ```bash
   cd webrtc-signaling
   vercel --prod
   ```

3. **Update your Qt app**
   In `webrtclistentogethermanager.cpp`, update:
   ```cpp
   QString m_signalingServerUrl = "https://your-vercel-app.vercel.app";
   ```

### Option 2: Netlify

1. **Install Netlify CLI**
   ```bash
   npm i -g netlify-cli
   ```

2. **Deploy to Netlify**
   ```bash
   cd webrtc-signaling
   netlify deploy --prod --dir=. 
   ```

### Option 3: Railway (Node.js)

1. **Create `package.json`** (already included)
2. **Deploy to Railway**
   ```bash
   railway login
   railway link
   railway up
   ```

## API Endpoints

### POST /api/signal

Handles WebRTC signaling messages:

**Create Session:**
```json
{
  "type": "create_session",
  "sessionId": "abc12345"
}
```

**Join Session:**
```json
{
  "type": "join_session", 
  "sessionId": "abc12345"
}
```

**SDP Exchange:**
```json
{
  "type": "description",
  "sessionId": "abc12345",
  "sdp": "v=0\r\no=-...",
  "isHost": true
}
```

**ICE Candidate:**
```json
{
  "type": "candidate",
  "sessionId": "abc12345", 
  "candidate": "candidate:...",
  "mid": "0"
}
```

**Leave Session:**
```json
{
  "type": "leave_session",
  "sessionId": "abc12345"
}
```

## How It Works

1. **Host creates session** → Server stores session ID
2. **Friend joins session** → Server stores both peers
3. **Peers exchange SDP/ICE** → Server relays messages
4. **P2P connection established** → Direct sync, no server needed
5. **Real-time sync** → Play/pause/seek/track changes

## Security Notes

- Session IDs are 8-character random strings
- No authentication required (for simplicity)
- Messages are not encrypted end-to-end (WebRTC handles this)
- Consider rate limiting for production use

## Limitations

- Serverless functions have execution timeouts
- No persistent storage (sessions reset on restart)
- Limited concurrent sessions (depends on platform limits)
- No room management beyond simple session IDs

For production use, consider WebSocket-based signaling with Redis for state management.
