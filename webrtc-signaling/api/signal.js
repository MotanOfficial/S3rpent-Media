// Vercel serverless function for WebRTC signaling
// Deploy to: https://your-vercel-app.vercel.app/api/signal

const sessions = new Map();

export default function handler(req, res) {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    let { type, sessionId, sdp, candidate, isHost } = req.body;

    // Ensure sessionId is lowercase for case-insensitive matching
    if (sessionId) {
      sessionId = sessionId.toLowerCase();
    }

    switch (type) {
      case 'create_session':
        if (!sessions.has(sessionId)) {
          sessions.set(sessionId, {
            host: null,
            clients: [],
            messages: [],
            nextMessageId: 1
          });
        }
        return res.status(200).json({ success: true, sessionId });

      case 'join_session':
        if (!sessions.has(sessionId)) {
          return res.status(404).json({ error: 'Session not found' });
        }

        const session = sessions.get(sessionId);
        return res.status(200).json({ 
          success: true, 
          messages: session.messages 
        });

      case 'leave_session':
        if (sessions.has(sessionId)) {
          sessions.delete(sessionId);
        }
        return res.status(200).json({ success: true });

      case 'poll':
        if (!sessions.has(sessionId)) {
          return res.status(200).json({ success: false, error: 'Session not found' });
        }
        const currentSession = sessions.get(sessionId);
        return res.status(200).json({ 
          success: true, 
          messages: currentSession.messages 
        });

      case 'description':
      case 'candidate':
        if (!sessions.has(sessionId)) {
          return res.status(404).json({ error: 'Session not found' });
        }

        const targetSession = sessions.get(sessionId);
        const message = { 
          ...req.body, 
          sessionId, 
          id: targetSession.nextMessageId++, 
          timestamp: Date.now() 
        };
        
        // Store message for late joiners
        targetSession.messages.push(message);
        
        // Keep only last 10 messages to prevent memory bloat
        if (targetSession.messages.length > 10) {
          targetSession.messages = targetSession.messages.slice(-10);
        }

        // In a real implementation, you'd use WebSockets or SSE
        // For now, clients will poll for messages
        return res.status(200).json({ success: true, stored: true });

      default:
        return res.status(400).json({ error: 'Invalid message type' });
    }

  } catch (error) {
    console.error('Signaling error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
