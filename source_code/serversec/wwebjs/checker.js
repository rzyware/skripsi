const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const dotenv = require('dotenv');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

dotenv.config();

const whatsappPhones = process.env.WHATSAPP_PHONE.split(',').map(num => num.trim());
const serviceLogDir = process.env.SERVICE_LOGDIR;
const badhostPath = path.join(serviceLogDir, 'badhost.txt');
const fastLogPath = path.join(serviceLogDir, 'fast.log');

const client = new Client({
    webVersionCache: {
        type: "remote",
        remotePath: "https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/2.2412.54.html",
    },
    authStrategy: new LocalAuth(),
    puppeteer: {
        headless: true,
        timeout: 300000,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--no-first-run',
            '--no-zygote',
            '--disable-gpu'
        ]
    }
});

client.on('qr', (qr) => {
    qrcode.generate(qr, { small: true }, (qrcodeText) => {
        fs.writeFile('auth', qrcodeText, (err) => {
            if (err) {
                console.error('Failed to save QR code to file:', err);
            } else {
                console.info('Please login your WhatsApp with QR on auth');
            }
        });
    });
});

client.on('ready', () => {
    console.info('wweb-js is ready');
    exip_rsync();
    fs.unlink('auth', (err) => {
        if (err) {
            console.error('Already logged in');
        }
    });
    // Maintain presence on WhatsApp
    let delayVerify = 20000;
    setInterval(() => {
        if (Math.random() < 0.8) {
            try {
                client.sendPresenceAvailable();
            } catch (e) {
                console.error("Error: sendPresenceAvailable", e);
            }
        } else {
            try {
                client.sendPresenceUnavailable();
            } catch (e) {
                console.error("Error: sendPresenceUnavailable", e);
            }
        }
    }, delayVerify);
    startChecker();
});

client.on('message', message => {
    fs.readFile(badhostPath, 'utf8', (err, data) => {
        if (err) {
            console.error('Error reading badhost file:', err);
            client.sendMessage(message.from, 'Error.');
            return;
        }
        let blacklists = data.split('\n').filter(line => line.trim() !== '');
        if (whatsappPhones.includes(message.from.replace('@c.us', ''))) {
            console.info(`Processing command: ${message.body}`);
            if (message.body === '.help') {
                client.sendMessage(message.from, 'Commands:\n.blacklists - list blacklist\n.addip <ip> - add IP to blacklist\n.delip <ip> - remove IP from blacklist');
            } else if (message.body === '.blacklists') {
                if (blacklists.length === 0) {
                    client.sendMessage(message.from, 'No blacklisted hosts found.');
                } else {
                    const blacklistMessage = blacklists.join('\n');
                    client.sendMessage(message.from, `Blacklisted Hosts:\n${blacklistMessage}`);
                }
            } else if (message.body.startsWith('.addip')) {
                const ip = message.body.split(' ')[1];
                if (ip) {
                    blacklists.push(ip);
                    fs.writeFile(badhostPath, blacklists.join('\n') + '\n', 'utf8', (err) => {
                        if (err) {
                            console.error('Error writing to badhost file:', err);
                            client.sendMessage(message.from, 'Error adding IP.');
                            return;
                        }
                        client.sendMessage(message.from, `IP ${ip} added to blacklist.`);
                    });
                } else {
                    client.sendMessage(message.from, 'Invalid command. Usage: .addip <ip>');
                }
            } else if (message.body.startsWith('.delip')) {
                const ip = message.body.split(' ')[1];
                if (ip) {
                    const index = blacklists.indexOf(ip);
                    if (index !== -1) {
                        blacklists.splice(index, 1);
                        const updatedData = blacklists.length > 0 ? blacklists.join('\n') + '\n' : '';
                        fs.writeFile(badhostPath, updatedData, 'utf8', (err) => {
                            if (err) {
                                console.error('Error writing to badhost file:', err);
                                client.sendMessage(message.from, 'Error removing IP.');
                                return;
                            }
                            client.sendMessage(message.from, `IP ${ip} removed from blacklist.`);
                        });
                    } else {
                        client.sendMessage(message.from, `IP ${ip} not found in blacklist.`);
                    }
                } else {
                    client.sendMessage(message.from, 'Invalid command. Usage: .delip <ip>');
                }
            }
        }
    });
});

client.initialize();

function exip_rsync() {
    execFile(process.env.BASH_PATH, [process.env.BASH_SCRIPT_PATH], (error, stdout, stderr) => {
        if (error) {
            exip_rsync();
            return;
        }
        if (stdout) {
            console.debug(`stdout: ${stdout}`);
        }
        if (stderr) {
            console.error(`stderr: ${stderr}`);
        }
    });
}

function startChecker() {
    console.info("Starting checker");
    let cachedStamp = 0;
    async function checkLogFile() {
        const logFile = fastLogPath;
        try {
            const stats = fs.statSync(logFile);
            if (stats.mtimeMs !== cachedStamp) {
                cachedStamp = stats.mtimeMs;
                const lines = fs.readFileSync(logFile, 'utf-8').split('\n');
                const lastEvent = lines[lines.length - 2];
                if (lastEvent) {
                    const formattedMessage = formatMessage(lastEvent);
                    if (formattedMessage) {
                        for (const phone of whatsappPhones) {
                            try {
                                await client.sendMessage(`${phone}@c.us`, formattedMessage);
                            } catch (error) {
                                console.error(`Failed to send message to ${phone}: ${error}`);
                            }
                        }
                    }
                }
            }
        } catch (error) {
            console.warn('fast.log not found');
        }
    }
    setInterval(checkLogFile, 10);
}

function formatMessage(event) {
    const alertRegex = /(.*)\s+\[(.*?)\]\s+\[(.*?)\]\s+(.*?)\s+\[\*\*\]\s+\[Classification:\s+(.*?)\]\s+\[Priority:\s+(\d)\]\s+{(\w+)}\s+([0-9.]+):(\d+)\s+->\s+([0-9.]+):(\d+)/;
    const parsed = event.match(alertRegex);
    if (parsed) {
        return `⚠ ${parsed[1]}\n*Alert:* ${parsed[4]}\n*Sid:* ${parsed[3]}\n*Type:* ${parsed[5]} ${parsed[6]}\n*Proto:* ${parsed[7]}\n*Source:* ${parsed[8]}:${parsed[9]}\n*Destination:* ${parsed[10]}:${parsed[11]}\n*VT*: \nhttps://www.virustotal.com/gui/ip-address/${parsed[8]}/detection\nhttps://www.virustotal.com/gui/ip-address/${parsed[10]}/detection`;
    }
    return null;
}
