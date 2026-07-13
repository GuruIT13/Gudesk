require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { Pool } = require('pg');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function seed() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // ============================================
    // ORGANIZATIONS
    // ============================================
    const { rows: orgs } = await client.query(`
      INSERT INTO organizations (name, slug) VALUES
        ('Org A - Alpha Corp',  'alpha-corp'),
        ('Org B - Beta Systems', 'beta-systems')
      RETURNING id, name
    `);
    const orgA = orgs[0];
    const orgB = orgs[1];
    console.log('Created orgs:', orgs.map(o => o.name));

    // ============================================
    // USERS (2 per org = 4 total, shared pool)
    // ============================================
    const { rows: users } = await client.query(`
      INSERT INTO users (email, password_hash, display_name) VALUES
        ('alice@alpha.com',   '$argon2id$v=19$m=65536,t=3,p=4$oDBGB/QP7xz94NNp5FuEXw$Y6WeolimxHBL8fyhwxgC2dB6STEPaGVT/gL9AgcLxic', 'Org A - Alice'),
        ('bob@alpha.com',     '$argon2id$v=19$m=65536,t=3,p=4$YEi2CW5A518CsDGw7QRSUg$VGjBepmQ2pQWk51c/BCnLTf4fJzZ9kTCBKijnKLXdZ0', 'Org A - Bob'),
        ('carol@beta.com',    '$argon2id$v=19$m=65536,t=3,p=4$uyits5fww4Bc92oXwaEgqA$hmmpCE0xGg6p98+5FAVVxshbNSjjAWv47xVyoBxlYYc', 'Org B - Carol'),
        ('dave@beta.com',     '$argon2id$v=19$m=65536,t=3,p=4$sK4G4zuPJPAUbaoe7OXuLA$o+R8ykXt+TTNPXwND6WgwySaM2zlCGUdwlsrgTTOSI8', 'Org B - Dave')
      RETURNING id, display_name
    `);
    const [alice, bob, carol, dave] = users;
    console.log('Created users:', users.map(u => u.display_name));

    // ============================================
    // MEMBERSHIPS
    // ============================================
    await client.query(`
      INSERT INTO memberships (org_id, user_id, role) VALUES
        ($1, $2, 'owner'),
        ($1, $3, 'member'),
        ($4, $5, 'owner'),
        ($4, $6, 'member')
    `, [orgA.id, alice.id, bob.id, orgB.id, carol.id, dave.id]);
    console.log('Created memberships');

    // ============================================
    // DIRECTORIES (1-2 per org)
    // ============================================
    const { rows: dirs } = await client.query(`
      INSERT INTO directories (org_id, parent_id, name, created_by) VALUES
        ($1, NULL, 'Org A - Root', $2),
        ($1, NULL, 'Org A - Bangkok Office', $2),
        ($3, NULL, 'Org B - Root', $4)
      RETURNING id, name
    `, [orgA.id, alice.id, orgB.id, carol.id]);
    const [dirARoot, dirABkk, dirBRoot] = dirs;
    console.log('Created directories:', dirs.map(d => d.name));

    // ============================================
    // DEVICES (2-3 per org)
    // ============================================
    const { rows: devices } = await client.query(`
      INSERT INTO devices (org_id, directory_id, device_uid, public_key, hostname, os_type, os_version, status, registered_by) VALUES
        ($1, $2, 'ORG-A-DEV-UID-001', 'pk_orgA_dev1_fakepublickey', 'Org A - Device 1', 'windows', '11 Pro', 'online',  $3),
        ($1, $2, 'ORG-A-DEV-UID-002', 'pk_orgA_dev2_fakepublickey', 'Org A - Device 2', 'windows', '10 Pro', 'offline', $3),
        ($1, $4, 'ORG-A-DEV-UID-003', 'pk_orgA_dev3_fakepublickey', 'Org A - Device 3 (BKK)', 'macos',   '14',     'online',  $3),
        ($5, $6, 'ORG-B-DEV-UID-001', 'pk_orgB_dev1_fakepublickey', 'Org B - Device 1', 'windows', '11 Pro', 'online',  $7),
        ($5, $6, 'ORG-B-DEV-UID-002', 'pk_orgB_dev2_fakepublickey', 'Org B - Device 2', 'windows', '11 Pro', 'offline', $7)
      RETURNING id, hostname
    `, [orgA.id, dirARoot.id, alice.id, dirABkk.id, orgB.id, dirBRoot.id, carol.id]);
    const [devA1, devA2, devA3, devB1, devB2] = devices;
    console.log('Created devices:', devices.map(d => d.hostname));

    // ============================================
    // REMOTE_SESSIONS (1 active on Org A - Device 1)
    // ============================================
    await client.query(`
      INSERT INTO remote_sessions (org_id, device_id, controller_id, connection_mode, started_at, ended_at) VALUES
        ($1, $2, $3, 'p2p', now() - interval '1 hour', now() - interval '30 minutes'),
        ($1, $4, $3, 'relay', now() - interval '10 minutes', null)
    `, [orgA.id, devA1.id, alice.id, devA1.id]);
    console.log('Created remote_sessions (1 past, 1 active on Org A - Device 1)');

    // ============================================
    // AUDIT_LOGS
    // ============================================
    await client.query(`
      INSERT INTO audit_logs (org_id, actor_id, action, target_type, target_id, metadata) VALUES
        ($1, $2, 'device.enroll',   'device', $3, '{"hostname": "Org A - Device 1"}'::jsonb),
        ($1, $2, 'session.start',   'device', $3, '{"connection_mode": "p2p"}'::jsonb),
        ($4, $5, 'device.enroll',   'device', $6, '{"hostname": "Org B - Device 1"}'::jsonb)
    `, [orgA.id, alice.id, devA1.id, orgB.id, carol.id, devB1.id]);
    console.log('Created audit_logs');

    await client.query('COMMIT');
    console.log('\nSeed completed successfully.');

    return { orgA, orgB, devA1, devA2, devA3, devB1, devB2, alice, bob, carol, dave };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

seed()
  .then(() => pool.end())
  .catch((err) => {
    console.error('Seed failed:', err.message);
    pool.end();
    process.exit(1);
  });
