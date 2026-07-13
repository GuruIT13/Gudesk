exports.up = (pgm) => {
  pgm.createTable('enrollment_tokens', {
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
    created_by: {
      type: 'uuid',
      notNull: true,
      references: '"users"',
    },
    token_hash: { type: 'varchar(64)', notNull: true, unique: true },
    expires_at: { type: 'timestamptz', notNull: true },
    used_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('enrollment_tokens', ['org_id'], { name: 'idx_enrollment_tokens_org' });
  pgm.createIndex('enrollment_tokens', ['token_hash'], { name: 'idx_enrollment_tokens_hash' });
};

exports.down = (pgm) => {
  pgm.dropTable('enrollment_tokens');
};
