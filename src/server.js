require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const http = require('http');
const app = require('./app');
const { attachSignaling } = require('./signaling');

const PORT = process.env.PORT || 3000;
const server = http.createServer(app);
attachSignaling(server);

server.listen(PORT, () => {
  console.log(`GuDesk API listening on port ${PORT}`);
});
