require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const argon2 = require('argon2');

async function main() {
  const passwords = {
    'alice@alpha.com': 'plaintext_alice',
    'bob@alpha.com': 'plaintext_bob',
    'carol@beta.com': 'plaintext_carol',
    'dave@beta.com': 'plaintext_dave',
  };
  for (const [email, pw] of Object.entries(passwords)) {
    const hash = await argon2.hash(pw, { type: argon2.argon2id });
    console.log(`${email}|||${hash}`);
  }
}
main();
