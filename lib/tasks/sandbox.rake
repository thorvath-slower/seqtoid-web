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
    sh!("chamber write #{n[:ssm]} db_username #{n[:user]}")
    sh!("chamber write #{n[:ssm]} db_password #{password}")
    sh!("chamber write #{n[:ssm]} db_name #{n[:schema]}")

    # Point S3 at the sandbox bucket. The copied config carries dev's SAMPLES_BUCKET_NAME,
    # but the sandbox IRSA role can only WRITE seqtoid-sandbox/* -- leaving dev's bucket
    # here would make every upload/pipeline S3 write fail with AccessDenied. Override to
    # the sandbox bucket (the role's write scope); per-PR keys are separated by the
    # sandbox's own DB references. (SAMPLES_BUCKET_NAME + the _V1 variant the app reads.)
    sandbox_bucket = ENV["SANDBOX_SAMPLES_BUCKET"] || "seqtoid-sandbox"
    sh!("chamber write #{n[:ssm]} samples_bucket_name #{sandbox_bucket}")
    sh!("chamber write #{n[:ssm]} samples_bucket_name_v1 #{sandbox_bucket}")

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
