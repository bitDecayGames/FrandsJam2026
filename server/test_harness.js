// Headless test harness for Colyseus server
// Uses raw HTTP matchmaking + WebSocket
const WebSocket = require('ws');

const SERVER = 'http://localhost:2567';
const WS_SERVER = 'ws://localhost:2567';

class TestClient {
    constructor(name) {
        this.name = name;
        this.sessionId = null;
        this.roomId = null;
        this.ws = null;
        this.messages = [];
    }

    async joinOrCreate(roomName) {
        const res = await fetch(`${SERVER}/matchmake/joinOrCreate/${roomName}`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({})
        });
        const data = await res.json();
        this.sessionId = data.sessionId;
        this.roomId = data.roomId;
        return this._connect(data);
    }

    async joinById(roomId) {
        const res = await fetch(`${SERVER}/matchmake/joinById/${roomId}`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({})
        });
        const data = await res.json();
        this.sessionId = data.sessionId;
        this.roomId = data.roomId;
        return this._connect(data);
    }

    _connect(data) {
        return new Promise((resolve, reject) => {
            const url = `${WS_SERVER}/${data.processId}/${data.roomId}?sessionId=${data.sessionId}`;
            this.ws = new WebSocket(url);

            this.ws.on('open', () => {
                console.log(`[${this.name}] Connected as ${this.sessionId}`);
                resolve(this);
            });

            this.ws.on('message', (raw) => {
                const bytes = Buffer.from(raw);
                this.messages.push(bytes);
            });

            this.ws.on('error', reject);
        });
    }

    leave() {
        if (this.ws) { this.ws.close(); this.ws = null; }
    }
}

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function runTests() {
    console.log('=== Headless Colyseus Test Harness ===\n');
    let passed = 0, failed = 0;

    function assert(condition, msg) {
        if (condition) { console.log(`  PASS: ${msg}`); passed++; }
        else { console.log(`  FAIL: ${msg}`); failed++; }
    }

    // Test 1: Two clients can join the same room
    console.log('Test 1: Room joining');
    const c1 = new TestClient('player');
    const c2 = new TestClient('bot');

    await c1.joinOrCreate('game_room');
    assert(c1.sessionId !== null, 'Client1 got sessionId');
    assert(c1.roomId !== null, 'Client1 got roomId');

    await c2.joinById(c1.roomId);
    assert(c2.sessionId !== null, 'Client2 got sessionId');
    assert(c1.roomId === c2.roomId, 'Both in same room');
    assert(c1.sessionId !== c2.sessionId, 'Different sessionIds');

    await sleep(500);

    // Test 2: Both clients receive state messages
    console.log('\nTest 2: State sync');
    assert(c1.messages.length > 0, 'Client1 received state messages');
    assert(c2.messages.length > 0, 'Client2 received state messages');

    // Test 3: Server logs show both players joined
    console.log('\nTest 3: Connection integrity');
    assert(c1.ws.readyState === WebSocket.OPEN, 'Client1 WS is open');
    assert(c2.ws.readyState === WebSocket.OPEN, 'Client2 WS is open');

    c1.leave();
    c2.leave();

    console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
    process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => { console.error('FATAL:', e); process.exit(1); });
