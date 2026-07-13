# CZID-597 (Export-control Layer 3 / #285) -- restricted-party HOLDS table. A hold is placed on a subject
# or item when its Descartes screen produces a HIT (or the screen errors/times out -- fail-closed). The
# hold is RELEASED only after a human compliance officer adjudicates the Incident Manager record. ADDITIVE
# ONLY -- no existing table is touched. Inert until CZID-596's ScreeningService is enabled (OFF by default).
class CreateHolds < ActiveRecord::Migration[7.0]
  def change
    create_table :holds, if_not_exists: true do |t|
      # The held subject/item. Same subject-agnostic string ref as screening_results (a user id, sample id,
      # etc); subject_type disambiguates when set.
      t.string :subject_ref, null: false
      t.string :subject_type

      # Why the hold exists: a screening hit, or a fail-closed error/timeout. Free-form string mapped from
      # Hold::REASONS so the record is explicit.
      t.string :reason, null: false

      # The screening_results row that triggered this hold. Nullable: a fail-closed error/timeout may not
      # have a persisted screening row (e.g. the vendor was unreachable).
      t.bigint :screening_result_id

      # When the hold was released (adjudicated clear / false hit). NULL == still active (Hold.active).
      t.datetime :released_at

      t.timestamps precision: 6
    end

    add_index :holds, :screening_result_id, if_not_exists: true
    # "active holds for this subject" lookups (Hold.active scope + per-subject filter).
    add_index :holds, [:subject_ref, :released_at], if_not_exists: true
  end
end
