# Per-PR preview sandbox provisioning (#616).
#
# These tasks run ONLY inside a preview sandbox's provision/teardown Jobs (the chart's
# preview-*-job.yaml), as the elevated seqtoid-web-provisioner IRSA role, wrapped in
# `chamber exec idseq-<env>-web` so they hold the shared config + the MASTER DB creds.
# They are NEVER run by app pods (those hold only the scoped seqtoid-web-preview role).
#
# provision: create an isolated schema + a per-PR DB user scoped to that schema, then
#   seed the sandbox's own SSM path (a copy of the shared dev config with the DB
#   connection overridden to the scoped user + schema). The pod then boots against its
#   OWN creds + schema; even holding those creds it cannot reach idseq_dev.
# teardown: drop the schema + user and delete the SSM path when the PR closes.
#
# Hard guards: SANDBOX_PR_NUMBER must be a positive integer; the schema/user names are
# built ONLY from it (never free-form), so these tasks can only ever touch idseq_pr_<N>
# / sbx_pr_<N> -- never idseq_dev or any other schema.
namespace :sandbox do
  def sandbox_pr_number!
    raw = ENV["SANDBOX_PR_NUMBER"].to_s
    raise "SANDBOX_PR_NUMBER must be a positive integer (got #{raw.inspect})" unless raw.match?(/\A[1-9][0-9]*\z/)
    raw
  end

  def sandbox_names(pr)
    { schema: "idseq_pr_#{pr}", user: "sbx_pr_#{pr}", ssm: "idseq-sandbox-pr-#{pr}-web" }
  end

  # Raw admin connection from the chamber-injected master creds (NOT the Rails pool,
  # which points at a specific schema). Used only to run DDL / user management.
  def admin_client
    require "mysql2"
    Mysql2::Client.new(
      host:     ENV.fetch("RDS_ADDRESS"),
      port:     (ENV["DB_PORT"] || 3306).to_i,
      username: ENV.fetch("DB_USERNAME"),
      password: ENV.fetch("DB_PASSWORD")
    )
  end

  def sh!(cmd)
    puts "+ #{cmd.gsub(/(db_password|IDENTIFIED BY)\s+\S+/i, '\1 [redacted]')}"
    raise "command failed: #{cmd}" unless system(cmd)
  end

  desc "Provision a per-PR sandbox: isolated schema + scoped user + its own SSM path"
  task :provision do
    require "securerandom"
    pr = sandbox_pr_number!
    n = sandbox_names(pr)
    env = ENV.fetch("ENVIRONMENT", "dev")
    src_service = ENV["SANDBOX_SRC_CHAMBER_SERVICE"] || "idseq-#{env}-web"
    password = SecureRandom.hex(24)

    puts "[sandbox:provision] pr=#{pr} schema=#{n[:schema]} user=#{n[:user]} ssm=#{n[:ssm]}"

    # 1) Schema + scoped user. Idempotent; ALTER USER keeps the password current on a
    #    re-provision (a PR re-sync). GRANT is scoped to THIS schema only -- the user
    #    physically cannot touch idseq_dev.
    c = admin_client
    c.query("CREATE DATABASE IF NOT EXISTS `#{n[:schema]}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
    c.query("CREATE USER IF NOT EXISTS '#{n[:user]}'@'%' IDENTIFIED BY '#{c.escape(password)}'")
    c.query("ALTER USER '#{n[:user]}'@'%' IDENTIFIED BY '#{c.escape(password)}'")
    c.query("GRANT ALL PRIVILEGES ON `#{n[:schema]}`.* TO '#{n[:user]}'@'%'")
    c.query("FLUSH PRIVILEGES")
    c.close

    # 2) Seed the sandbox SSM path = a copy of the shared config, then override the DB
    #    connection to the scoped user + schema (rds_address stays the shared Aurora).
    #    chamber uses the provisioner role: it can read src_service + write the sandbox path.
    require "tempfile"
    Tempfile.create(["dev-config", ".json"]) do |f|
      sh!("chamber export --format json #{src_service} > #{f.path}")
      sh!("chamber import #{n[:ssm]} #{f.path}")
    end
    # Override the DB + S3 config copied from dev with the sandbox-scoped values.
    #
    # These MUST be written UPPERCASE. chamber stores every key uppercased and injects env vars by the
    # stored key, so `chamber import` from dev lands DB_USERNAME / SAMPLES_BUCKET_NAME (uppercase), and
    # writing lowercase `db_username` created a SECOND, DISTINCT key rather than overriding the import.
    # The pod then saw BOTH, and the imported uppercase value won -- so a sandbox connected to the dev
    # Aurora as the MASTER user (DB_USERNAME=idseqmaster) and pointed S3 at dev's samples bucket. It
    # failed closed only by luck (the master password did not match the scoped one), and did so
    # non-deterministically. Writing the same UPPERCASE keys overwrites the import in place. See #697.
    sandbox_bucket = ENV["SANDBOX_SAMPLES_BUCKET"] || "seqtoid-sandbox"

    # ORDER MATTERS -- clean up stale duplicates FIRST, then write the canonical keys LAST.
    # This block used to run AFTER the writes below, which silently destroyed the sandbox: chamber
    # normalises/uppercases keys, so `chamber delete <svc> db_password` resolves onto the canonical
    # DB_PASSWORD that had just been written. A provision would report "done" while DB_PASSWORD and
    # DB_NAME were missing; the pod then fell back to Rails defaults and tried the dev MASTER user with
    # no password ("Access denied for user 'idseqmaster' ... using password: NO") and the sandbox never
    # booted. Deleting before writing makes the writes last-write-wins and unclobberable, and is also
    # safe if two provision Jobs overlap (Argo recreates this hook on every sync). Caught by the
    # 2026-07-16 IT-ARS e2e (PR #23). See platform-overhaul #697.
    %w[db_username db_password db_name samples_bucket_name samples_bucket_name_v1].each do |stale|
      sh!("chamber delete #{n[:ssm]} #{stale} || true")
    end

    sh!("chamber write #{n[:ssm]} DB_USERNAME #{n[:user]}")
    sh!("chamber write #{n[:ssm]} DB_PASSWORD #{password}")
    sh!("chamber write #{n[:ssm]} DB_NAME #{n[:schema]}")
    sh!("chamber write #{n[:ssm]} SAMPLES_BUCKET_NAME #{sandbox_bucket}")
    sh!("chamber write #{n[:ssm]} SAMPLES_BUCKET_NAME_V1 #{sandbox_bucket}")

    # Assert isolation held before the pod is allowed to boot. Verify EVERY scoped credential, not just
    # the username: a sandbox missing DB_PASSWORD/DB_NAME silently falls back to the dev master creds,
    # which is exactly the failure this check exists to prevent. Fail the Job loudly instead.
    # (chamber exec resolves the same precedence the app will see.)
    resolved = `chamber exec #{n[:ssm]} -- printenv DB_USERNAME DB_PASSWORD DB_NAME`.split("\n").map(&:strip)
    resolved_user, resolved_pass, resolved_name = resolved
    if resolved_user != n[:user]
      abort("[sandbox:provision] FATAL: DB_USERNAME resolved to '#{resolved_user}', expected '#{n[:user]}'. " \
            "Refusing to provision a sandbox that is not DB-isolated. See platform-overhaul #697.")
    end
    if resolved_pass.blank?
      abort("[sandbox:provision] FATAL: DB_PASSWORD did not resolve for #{n[:ssm]}. The pod would fall back " \
            "to the dev MASTER creds. Refusing to provision. See platform-overhaul #697.")
    end
    if resolved_name != n[:schema]
      abort("[sandbox:provision] FATAL: DB_NAME resolved to '#{resolved_name}', expected '#{n[:schema]}'. " \
            "Refusing to provision a sandbox that would target the wrong schema. See platform-overhaul #697.")
    end

    puts "[sandbox:provision] done -- pod may now boot with CHAMBER_SERVICE=#{n[:ssm]} DB_NAME=#{n[:schema]}"
  end

  desc "Tear down a per-PR sandbox: drop the schema + user and delete its SSM path"
  task :teardown do
    pr = sandbox_pr_number!
    n = sandbox_names(pr)

    puts "[sandbox:teardown] pr=#{pr} dropping schema=#{n[:schema]} user=#{n[:user]} ssm=#{n[:ssm]}"

    c = admin_client
    c.query("DROP DATABASE IF EXISTS `#{n[:schema]}`")
    c.query("DROP USER IF EXISTS '#{n[:user]}'@'%'")
    c.query("FLUSH PRIVILEGES")
    c.close

    # Delete every param under the sandbox SSM path. Enumerate + delete via the aws CLI
    # (the chamber service `X` maps to SSM path `/X/`); this is more robust than parsing
    # `chamber list` output. Idempotent: no-op if the path is already empty.
    require "shellwords"
    ssm_path = "/#{n[:ssm]}"
    names = `aws ssm get-parameters-by-path --path #{Shellwords.escape(ssm_path)} --recursive --query 'Parameters[].Name' --output text 2>/dev/null`.split
    names.each_slice(10) do |batch|
      system("aws", "ssm", "delete-parameters", "--names", *batch, out: File::NULL, err: File::NULL)
    end
    puts "[sandbox:teardown] deleted #{names.size} SSM params under #{ssm_path}"

    puts "[sandbox:teardown] done"
  end

  # Idempotent seed for the sandbox migrate hook. db:seed (db/seeds.rb) uses
  # AppConfig.create, which raises on a schema that already has these rows -- so it fails
  # on ANY re-sync of a sandbox (a PR push re-runs the migrate hook against the existing
  # schema). Guard it: only run db:seed on a truly fresh schema (no app_configs yet).
  # The first sync seeds the (dev) SFN ARNs + launched features; later re-syncs skip it.
  desc "Run db:seed only if the sandbox schema has not been seeded yet (idempotent)"
  task seed_once: :environment do
    if AppConfig.count.zero?
      puts "[sandbox:seed_once] fresh schema -- running db:seed"
      Rake::Task["db:seed"].invoke
    else
      puts "[sandbox:seed_once] app_configs already present (#{AppConfig.count}) -- skipping db:seed"
    end
  end
end
