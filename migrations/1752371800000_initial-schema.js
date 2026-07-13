/**
 * @param {import('node-pg-migrate').MigrationBuilder} pgm
 */
exports.up = (pgm) => {
  // ============================================
  // ORGANIZATIONS
  // ============================================
  pgm.createTable('organizations', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    name: { type: 'varchar(255)', notNull: true },
    slug: { type: 'varchar(100)', notNull: true, unique: true },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  // ============================================
  // USERS
  // ============================================
  pgm.createTable('users', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    email: { type: 'varchar(255)', notNull: true, unique: true },
    password_hash: { type: 'varchar(255)', notNull: true },
    display_name: { type: 'varchar(255)' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  // ============================================
  // MEMBERSHIPS
  // ============================================
  pgm.createTable('memberships', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    org_id: {
      type: 'uuid',
      notNull: true,
      references: '"organizations"',
      onDelete: 'CASCADE',
    },
    user_id: {
      type: 'uuid',
      notNull: true,
      references: '"users"',
      onDelete: 'CASCADE',
    },
    role: {
      type: 'varchar(20)',
      notNull: true,
      default: 'member',
      check: "role IN ('owner', 'admin', 'member', 'viewer')",
    },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.addConstraint('memberships', 'memberships_org_user_unique', 'UNIQUE (org_id, user_id)');
  pgm.createIndex('memberships', ['user_id'], { name: 'idx_memberships_user' });
  pgm.createIndex('memberships', ['org_id'], { name: 'idx_memberships_org' });

  // ============================================
  // DIRECTORIES
  // ============================================
  pgm.createTable('directories', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    org_id: {
      type: 'uuid',
      notNull: true,
      references: '"organizations"',
      onDelete: 'CASCADE',
    },
    parent_id: {
      type: 'uuid',
      references: '"directories"',
      onDelete: 'CASCADE',
    },
    name: { type: 'varchar(255)', notNull: true },
    created_by: {
      type: 'uuid',
      notNull: true,
      references: '"users"',
    },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('directories', ['org_id'], { name: 'idx_directories_org' });
  pgm.createIndex('directories', ['parent_id'], { name: 'idx_directories_parent' });

  // ============================================
  // DEVICES
  // ============================================
  pgm.createTable('devices', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    org_id: {
      type: 'uuid',
      notNull: true,
      references: '"organizations"',
      onDelete: 'CASCADE',
    },
    directory_id: {
      type: 'uuid',
      references: '"directories"',
      onDelete: 'SET NULL',
    },
    device_uid: { type: 'varchar(64)', notNull: true, unique: true },
    public_key: { type: 'text', notNull: true },
    hostname: { type: 'varchar(255)' },
    os_type: { type: 'varchar(50)' },
    os_version: { type: 'varchar(100)' },
    status: {
      type: 'varchar(20)',
      notNull: true,
      default: 'offline',
      check: "status IN ('online', 'offline', 'busy')",
    },
    last_seen_at: { type: 'timestamptz' },
    last_ip: { type: 'inet' },
    registered_by: {
      type: 'uuid',
      references: '"users"',
    },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('devices', ['org_id'], { name: 'idx_devices_org' });
  pgm.createIndex('devices', ['directory_id'], { name: 'idx_devices_directory' });
  pgm.createIndex('devices', ['org_id', 'status'], { name: 'idx_devices_status' });

  // ============================================
  // REMOTE_SESSIONS
  // ============================================
  pgm.createTable('remote_sessions', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    org_id: {
      type: 'uuid',
      notNull: true,
      references: '"organizations"',
      onDelete: 'CASCADE',
    },
    device_id: {
      type: 'uuid',
      notNull: true,
      references: '"devices"',
      onDelete: 'CASCADE',
    },
    controller_id: {
      type: 'uuid',
      notNull: true,
      references: '"users"',
    },
    connection_mode: {
      type: 'varchar(20)',
      notNull: true,
      default: 'p2p',
      check: "connection_mode IN ('p2p', 'relay')",
    },
    relay_server_id: { type: 'varchar(64)' },
    started_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    ended_at: { type: 'timestamptz' },
    end_reason: { type: 'varchar(50)' },
  });

  // partial unique index — core business rule: 1 active session per device
  pgm.sql(`
    CREATE UNIQUE INDEX idx_one_active_session_per_device
      ON remote_sessions(device_id)
      WHERE ended_at IS NULL;
  `);

  pgm.createIndex('remote_sessions', ['org_id'], { name: 'idx_sessions_org' });
  pgm.createIndex('remote_sessions', ['controller_id'], { name: 'idx_sessions_controller' });

  // ============================================
  // AUDIT_LOGS
  // ============================================
  pgm.createTable('audit_logs', {
    id: { type: 'bigserial', primaryKey: true },
    org_id: {
      type: 'uuid',
      notNull: true,
      references: '"organizations"',
      onDelete: 'CASCADE',
    },
    actor_id: {
      type: 'uuid',
      references: '"users"',
    },
    action: { type: 'varchar(100)', notNull: true },
    target_type: { type: 'varchar(50)' },
    target_id: { type: 'uuid' },
    metadata: { type: 'jsonb' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.sql(`
    CREATE INDEX idx_audit_org_time ON audit_logs(org_id, created_at DESC);
  `);
};

/**
 * @param {import('node-pg-migrate').MigrationBuilder} pgm
 */
exports.down = (pgm) => {
  pgm.dropTable('audit_logs');
  pgm.dropTable('remote_sessions');
  pgm.dropTable('devices');
  pgm.dropTable('directories');
  pgm.dropTable('memberships');
  pgm.dropTable('users');
  pgm.dropTable('organizations');
};
