class Invidious::Database::Migrator
  MIGRATIONS_TABLE = "public.invidious_migrations"

  # Arbitrary, fixed key for the session-level advisory lock that serializes
  # migrations across concurrently-starting Invidious instances.
  ADVISORY_LOCK_KEY = 0x1_2D10_1D10_i64

  class_getter migrations = [] of Invidious::Database::Migration.class

  def initialize(@db : DB::Database)
  end

  def migrate
    # Hold a session-level advisory lock for the whole run so that two
    # instances starting simultaneously can't run the same migration twice.
    #
    # The lock and every migration statement run on this single, explicitly
    # checked-out connection. Routing all work through one connection keeps
    # the advisory lock effective (it is session-scoped) and avoids checking
    # out additional connections while this one is held — which would
    # deadlock/time-out on a pool configured with a small max_pool_size.
    @db.using_connection do |conn|
      conn.exec("SELECT pg_advisory_lock($1)", ADVISORY_LOCK_KEY)
      begin
        run_migrations(conn)
      ensure
        conn.exec("SELECT pg_advisory_unlock($1)", ADVISORY_LOCK_KEY)
      end
    end
  end

  private def run_migrations(conn : DB::Connection)
    versions = load_versions(conn)

    ran_migration = false
    load_migrations.sort_by(&.version)
      .each do |migration|
        next if versions.includes?(migration.version)

        puts "Running migration: #{migration.class.name}"
        migration.migrate(conn)
        ran_migration = true
      end

    puts "No migrations to run." unless ran_migration
  end

  def pending_migrations? : Bool
    @db.using_connection do |conn|
      versions = load_versions(conn)

      load_migrations.sort_by(&.version)
        .any? { |migration| !versions.includes?(migration.version) }
    end
  end

  private def load_migrations : Array(Invidious::Database::Migration)
    self.class.migrations.map(&.new(@db))
  end

  private def load_versions(conn : DB::Connection) : Array(Int64)
    create_migrations_table(conn)
    conn.query_all("SELECT version FROM #{MIGRATIONS_TABLE}", as: Int64)
  end

  private def create_migrations_table(conn : DB::Connection)
    conn.exec <<-SQL
      CREATE TABLE IF NOT EXISTS #{MIGRATIONS_TABLE} (
        id bigserial PRIMARY KEY,
        version bigint NOT NULL
      )
    SQL

    # Prevent a migration version from being recorded twice (e.g. if two
    # instances ever race past the advisory lock).
    conn.exec <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS invidious_migrations_version_idx
        ON #{MIGRATIONS_TABLE} (version)
    SQL
  end
end
