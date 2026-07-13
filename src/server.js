require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const http = require('http');
const app = require('./app');
const { attachSignaling } = require('./signaling');

const PORT = process.env.PORT || 3000;
const server = http.createServer(app);
attachSignaling(server);

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use`);
  } else {
    console.error(`Server failed to start: ${err.message}`);
  }
  process.exit(1);
});

server.listen(PORT, () => {
  console.log(`GuDesk API listening on port ${PORT}`);
});
