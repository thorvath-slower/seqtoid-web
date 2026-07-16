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
require "English" # $CHILD_STATUS -- the shell-out exit codes below are load-bearing guards
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

  # Resolve ONE env var exactly the way the app will see it (chamber exec injects the config
  # as env vars). Read one at a time: `printenv A B C` silently omits a missing var, which
  # shifts every later value up a slot and makes a multi-var read misreport what resolved.
  def chamber_env(service, var)
    `chamber exec #{service} -- printenv #{var} 2>/dev/null`.strip
  end

  # Every param name under a chamber service's SSM path (raw API -- see the case notes in
  # :provision for why chamber's own write/delete cannot address these by name).
  #
  # FAILS LOUDLY on purpose. This swallowed stderr and returned [] on error, which made both
  # callers no-op SILENTLY: the duplicate sweep deleted nothing and the isolation assert passed
  # VACUOUSLY (no names -> no duplicates found -> "verified"), so a provision exited 0 while
  # leaving the sandbox pointed at the dev master. The provisioner role was missing
  # ssm:GetParametersByPath, so this failed on EVERY run and nothing ever said so. A check that
  # cannot fail is not a check. A chamber service path is never legitimately empty, so an empty
  # result is an error too, not an answer.
  # Delete SSM params by full name, in API-limit batches. Also fails loudly: this used to send both
  # stdout and stderr to /dev/null and ignore the exit status, so an IAM denial looked exactly like a
  # successful delete -- which is how :teardown reported "deleted N params" while deleting none.
  def ssm_delete_params!(names)
    names.each_slice(10) do |batch|
      out = IO.popen(["aws", "ssm", "delete-parameters", "--names", *batch], err: [:child, :out], &:read)
      raise "aws ssm delete-parameters failed (exit #{$CHILD_STATUS.exitstatus}): #{out.strip}" unless $CHILD_STATUS.success?
    end
  end

  # NOTE THE TRAILING SLASH on --path, it is load-bearing. GetParametersByPath authorises against the
  # PATH itself, not its children: `--path /idseq-sandbox-pr-23-web` is checked against the resource
  # `parameter/idseq-sandbox-pr-23-web`, which the provisioner policy does NOT match (it grants
  # `parameter/idseq-sandbox-pr-*-web/*`, i.e. the children). `--path /idseq-sandbox-pr-23-web/` is
  # checked against `parameter/idseq-sandbox-pr-23-web/`, which DOES match `/*`. This is also why
  # `chamber export` from dev works while a bare-path CLI call gets AccessDenied -- chamber queries
  # with the slash. Verified against the live role 2026-07-16.
  def ssm_param_names(service)
    out = `aws ssm get-parameters-by-path --path /#{service}/ --recursive --query 'Parameters[].Name' --output text 2>&1`
    raise "aws ssm get-parameters-by-path failed for /#{service} (exit #{$CHILD_STATUS.exitstatus}): #{out.strip}" unless $CHILD_STATUS.success?

    names = out.split
    raise "aws ssm get-parameters-by-path returned NO params for /#{service}; refusing to treat that as 'nothing to do'" if names.empty?

    names
  end

  desc "Provision a per-PR sandbox: isolated schema + scoped user + its own SSM path"
  task :provision do
    require "securerandom"
    pr = sandbox_pr_number!
    n = sandbox_names(pr)
    env = ENV.fetch("ENVIRONMENT", "dev")
    src_service = ENV["SANDBOX_SRC_CHAMBER_SERVICE"] || "idseq-#{env}-web"
    sandbox_bucket = ENV["SANDBOX_SAMPLES_BUCKET"] || "seqtoid-sandbox"

    puts "[sandbox:provision] pr=#{pr} schema=#{n[:schema]} user=#{n[:user]} ssm=#{n[:ssm]}"

    # REUSE the sandbox's existing password when one is already stored, and only mint a new one
    # on a genuinely fresh sandbox. Argo recreates this hook on every sync, so two provision Jobs
    # can overlap; if each minted its own password they would race (A: ALTER USER pw_a -> B: ALTER
    # USER pw_b -> A writes pw_a to SSM) and leave SSM disagreeing with the DB, which the app can
    # only report as "Access denied". Reusing makes a re-provision idempotent and the overlap benign.
    existing_pw = `aws ssm get-parameter --name /#{n[:ssm]}/DB_PASSWORD --with-decryption --query Parameter.Value --output text 2>/dev/null`.strip
    password = existing_pw.empty? || existing_pw == "None" ? SecureRandom.hex(24) : existing_pw

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
    # KEY CASE IS THE WHOLE BALLGAME HERE (#697). The three chamber verbs disagree about case:
    #   - `chamber import` copies keys VERBATIM        -> dev's /DB_USERNAME (= idseqmaster) lands as-is
    #   - `chamber write`  LOWERCASES the key          -> `write DB_USERNAME x` stores /db_username
    #   - `chamber exec`   UPPERCASES keys for env     -> /DB_USERNAME and /db_username BOTH become $DB_USERNAME
    # So overriding the import with `chamber write` did not override anything: it created a SECOND,
    # distinct param, and exec then picked between the two NON-DETERMINISTICALLY. A sandbox would
    # sometimes come up as the dev MASTER user against the shared dev Aurora, and sometimes not, from
    # byte-identical inputs. `chamber delete <svc> db_username` lowercases too, so it can never remove
    # the imported UPPERCASE key -- which is why re-ordering the deletes made no difference.
    #
    # Fix at the mechanism: normalise the exported config to ONE case and apply the overrides BEFORE
    # importing, so no key can ever collide with another spelling of itself. No `chamber write` here --
    # its lowercasing is what created the duplicate in the first place. Proven against the live dev
    # config 2026-07-16 (IT-ARS #23 e2e): dev carries 34 uppercase + 2 lowercase keys.
    require "json"
    require "tempfile"
    Tempfile.create(["dev-config", ".json"]) do |f|
      sh!("chamber export --format json #{src_service} > #{f.path}")
      config = JSON.parse(File.read(f.path))
      scoped = config.each_with_object({}) { |(k, v), h| h[k.upcase] = v }
      scoped["DB_USERNAME"] = n[:user]
      scoped["DB_PASSWORD"] = password
      scoped["DB_NAME"] = n[:schema]
      scoped["SAMPLES_BUCKET_NAME"] = sandbox_bucket
      scoped["SAMPLES_BUCKET_NAME_V1"] = sandbox_bucket
      # The sandbox serves on its OWN host, so it needs its OWN SERVER_DOMAIN; importing dev's
      # pointed all three consumers at dev. Most visibly it made the sandbox return 403 "Blocked
      # hosts" on every page: config/environments/development.rb allowlists ENV["SERVER_DOMAIN"],
      # and application.rb's `.seqtoid.org` entry does NOT cover us -- Rails 7.2 compiles a leading
      # dot with SUBDOMAIN_REGEX = /(?:[a-z0-9-]+\.)/ and a `?`, i.e. AT MOST ONE label, so it
      # allows dev.seqtoid.org but not pr-23.dev.seqtoid.org (two labels). Setting this exact host
      # is tighter than widening the allowlist to a wildcard, and also fixes rack_cors and the
      # bulk-download callback URLs (app/models/bulk_download.rb), which both read SERVER_DOMAIN and
      # were sending sandbox traffic to dev. Host must match the appset's ingress.host
      # (pr-<N>.dev.seqtoid.org); override via SANDBOX_SERVER_DOMAIN if that ever changes.
      scoped["SERVER_DOMAIN"] = ENV["SANDBOX_SERVER_DOMAIN"] || "https://pr-#{pr}.dev.seqtoid.org"
      File.write(f.path, JSON.pretty_generate(scoped))
      # Import (not write) so the scoped values land under the SAME uppercase keys the app reads, and
      # overwrite the imported dev values in place rather than racing them. Doing this in one import
      # also means the path never has a window with the config half-missing, so an overlapping Job or
      # a pod booting mid-provision sees a consistent (if briefly older) config, never a broken one.
      sh!("chamber import #{n[:ssm]} #{f.path}")
    end

    # Sweep any lower-case leftovers from provisions that ran the old `chamber write` path. They are
    # invisible to chamber (it would lowercase the name and match the wrong key), so enumerate and
    # delete them through the raw SSM API. Any key that is not already canonical uppercase is a
    # duplicate spelling of one we just imported and can only cause an exec collision.
    stale = ssm_param_names(n[:ssm]).reject { |name| name.split("/").last == name.split("/").last.upcase }
    ssm_delete_params!(stale)
    puts "[sandbox:provision] removed #{stale.size} lower-case duplicate param(s)"

    # Assert isolation held BEFORE the pod is allowed to boot, resolving each value exactly as the app
    # will (chamber exec). Verify every scoped credential, not just the username: a sandbox missing
    # DB_PASSWORD/DB_NAME falls back toward the dev master creds, which is the failure this exists to
    # prevent. Also assert the collision itself is gone -- with duplicate spellings present these
    # checks are a COIN FLIP that passes ~half the time and certifies nothing.
    # POLL, do not snapshot. GetParametersByPath is eventually consistent: immediately after the
    # deletes above it still lists the names it just removed, so asserting on a single read failed the
    # Job with a FATAL naming keys that were already gone. Wait for the listing to actually converge,
    # and only then decide. Still fails closed -- if the duplicates are real they never clear and we
    # abort with the same message, just after the window instead of before it.
    deadline = Time.now + 120
    dupes = {}
    loop do
      dupes = ssm_param_names(n[:ssm]).map { |name| name.split("/").last }.group_by(&:upcase).select { |_, v| v.size > 1 }
      break if dupes.empty? || Time.now > deadline

      sleep 5
    end
    unless dupes.empty?
      abort("[sandbox:provision] FATAL: #{n[:ssm]} still has case-duplicate keys #{dupes.values.flatten.sort.inspect} " \
            "after waiting for the SSM listing to converge. chamber exec would pick between them " \
            "non-deterministically. See platform-overhaul #697.")
    end
    resolved_user = chamber_env(n[:ssm], "DB_USERNAME")
    resolved_name = chamber_env(n[:ssm], "DB_NAME")
    if resolved_user != n[:user]
      abort("[sandbox:provision] FATAL: DB_USERNAME resolved to '#{resolved_user}', expected '#{n[:user]}'. " \
            "Refusing to provision a sandbox that is not DB-isolated. See platform-overhaul #697.")
    end
    if chamber_env(n[:ssm], "DB_PASSWORD").blank?
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

    # Delete every param under the sandbox SSM path. Enumerate + delete via the aws CLI (the chamber
    # service `X` maps to SSM path `/X/`); this is more robust than parsing `chamber list` output.
    # Both calls now raise on failure -- they previously discarded stderr AND the exit status, so the
    # missing ssm:GetParametersByPath grant made this print "deleted 0 SSM params" and orphan every
    # sandbox's config forever, with no error anywhere. Tolerate ONLY the already-empty case.
    ssm_path = "/#{n[:ssm]}"
    names = begin
      ssm_param_names(n[:ssm])
    rescue RuntimeError => e
      raise unless e.message.include?("returned NO params")

      [] # genuinely already torn down
    end
    ssm_delete_params!(names)
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
