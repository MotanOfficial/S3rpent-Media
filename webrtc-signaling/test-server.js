// Simple Node.js test server for local WebRTC signaling
// Alternative to Vercel dev for easier local testing

const express = require('express');
const cors = require('cors');
const os = require('os');

const app = express();
// Port 3000 is often blocked on Windows (Hyper-V reserves 2928–3027). Override: PORT=8787 node test-server.js
const DEFAULT_PORT = 3847;
const PORT = Number(process.env.PORT) || DEFAULT_PORT;

function getLanIp() {
    const interfaces = os.networkInterfaces();
    const skipNames = ['vmware', 'virtualbox', 'vEthernet', 'hyper-v', 'wsl', 'tailscale', 'zerotier', 'vpn', 'loopback'];
    let best = null;
    for (const name of Object.keys(interfaces)) {
        const lower = name.toLowerCase();
        const isVirtual = skipNames.some(n => lower.includes(n));
        for (const iface of interfaces[name]) {
            const isV4 = (iface.family === 'IPv4' || iface.family === 4);
            if (isV4 && !iface.internal && !isVirtual) {
                return iface.address;
            }
            if (isV4 && !iface.internal && !best) {
                best = iface.address;
            }
        }
    }
    return best;
}

function getAllIps() {
    const interfaces = os.networkInterfaces();
    const ips = [];
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if ((iface.family === 'IPv4' || iface.family === 4) && !iface.internal) {
                ips.push({ name, address: iface.address });
            }
        }
    }
    return ips;
}

// Store sessions in memory (for testing only)
const sessions = new Map();

/** Keep only the latest host offer + latest client answer; cap ICE candidates. */
function trimSessionMessages(messages) {
    const descriptions = messages.filter((m) => m.type === 'description');
    const candidates = messages.filter((m) => m.type === 'candidate');

    const hostOffers = descriptions.filter((m) => m.isHost === true);
    const clientAnswers = descriptions.filter((m) => m.isHost === false);
    const kept = [];
    if (hostOffers.length > 0)
        kept.push(hostOffers[hostOffers.length - 1]);
    if (clientAnswers.length > 0)
        kept.push(clientAnswers[clientAnswers.length - 1]);

    const minKeptId = kept.length > 0 ? Math.min(...kept.map((m) => m.id)) : 0;
    const trimmedCandidates = candidates.filter((m) => m.id >= minKeptId).slice(-24);
    return [...kept, ...trimmedCandidates].sort((a, b) => a.id - b.id);
}

// Middleware
app.use(cors());
app.use(express.json());

// Signaling endpoint
app.post('/api/signal', (req, res) => {
    try {
        let { type, sessionId, sdp, candidate, isHost } = req.body;
        
        // Ensure sessionId is lowercase for case-insensitive matching
        if (sessionId) {
            sessionId = sessionId.toLowerCase();
        }
        
        console.log(`[${new Date().toISOString()}] ${type} for session: ${sessionId}`);
        
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
                    // Only the host tears down the room; clients disconnecting must not delete it.
                    if (req.body.isHost) {
                        sessions.delete(sessionId);
                        console.log(`Host left — deleted session ${sessionId}`);
                    } else {
                        const session = sessions.get(sessionId);
                        session.messages = [];
                        console.log(`Client left — cleared signaling for session ${sessionId}`);
                    }
                }
                return res.status(200).json({ success: true });

            case 'clear_signaling':
                if (sessions.has(sessionId)) {
                    sessions.get(sessionId).messages = [];
                    console.log(`Cleared signaling for session ${sessionId}`);
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
            case 'candidate': {
                if (!sessions.has(sessionId)) {
                    sessions.set(sessionId, {
                        host: null,
                        clients: [],
                        messages: [],
                        nextMessageId: 1
                    });
                    console.log(`Auto-created session ${sessionId} for ${type}`);
                }

                const targetSession = sessions.get(sessionId);
                const message = { 
                    ...req.body, 
                    sessionId, 
                    id: targetSession.nextMessageId++, 
                    timestamp: Date.now() 
                };
                
                // Store message for late joiners (always retain SDP; cap candidates only)
                targetSession.messages.push(message);
                targetSession.messages = trimSessionMessages(targetSession.messages);

                console.log(`Stored ${type} for session ${sessionId} (${targetSession.messages.length} msgs, ${targetSession.messages.filter(m => m.type === 'description').length} sdp)`);
                return res.status(200).json({ success: true, stored: true });
            }

            default:
                return res.status(400).json({ error: 'Invalid message type' });
        }
        
    } catch (error) {
        console.error('Signaling error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'ok', sessions: sessions.size });
});

// List active sessions (for debugging)
app.get('/sessions', (req, res) => {
    const sessionList = Array.from(sessions.keys());
    res.json({ sessions: sessionList });
});

app.listen(PORT, '0.0.0.0', () => {
    const lanIp = getLanIp();
    const allIps = getAllIps();
    console.log(`\n🚀 WebRTC Signaling Server running on:`);
    console.log(`   Local:    http://localhost:${PORT}`);
    if (lanIp) {
        console.log(`   Network:  http://${lanIp}:${PORT}  ← Use this for LAN friends`);
    }
    if (allIps.length > 1) {
        console.log(`   All detected interfaces:`);
        for (const { name, address } of allIps) {
            const mark = (address === lanIp) ? '✓' : ' ';
            console.log(`     [${mark}] ${name}: http://${address}:${PORT}`);
        }
    }
    console.log(`📡 API endpoint: /api/signal`);
    console.log(`🔍 Health check: /health`);
    console.log(`📋 Active sessions: /sessions`);
    console.log(`\n📝 In the app, set Connection settings to: localhost:${PORT}`);
    console.log(`\n🎧 Ready for WebRTC P2P connections!\n`);
}).on('error', (err) => {
    if (err.code === 'EACCES' || err.code === 'EADDRINUSE') {
        console.error(`\n❌ Cannot bind to port ${PORT} (${err.code}).`);
        if (err.code === 'EACCES') {
            console.error('   Windows may reserve this port (Hyper-V/WSL). Try another port:');
            console.error(`   set PORT=8787 && node test-server.js`);
        } else {
            console.error('   Port already in use. Try another port or stop the other process.');
        }
        process.exit(1);
    }
    throw err;
});
